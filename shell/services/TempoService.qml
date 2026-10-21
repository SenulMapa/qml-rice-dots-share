pragma Singleton
import QtQuick
import "."
import "../core"

/**
 * TempoService — estimates the current track's BPM from the existing
 * 64-bin cava spectrum feed (VisualizerService.spectrum), so VinylDisc's
 * disc/ring spin speed can track the real song instead of spinning at a
 * fixed, always-too-fast rate.
 *
 * METHOD. No dedicated audio pipe of our own (aubio's live JACK mode was
 * tried against the real desktop -- `pw-jack aubiotrack -j` connected via
 * pw-link to the default sink's monitor genuinely receiving audio (verified
 * with `pw-record` + wav inspection) produced zero beat timestamps over a
 * 14s window against a normal pop track, and the routing itself (manual
 * pw-link to whichever sink is default *right now*) does not survive an
 * output switch, which this shell already treats as a live variable via
 * default-sink changes -- so the "robust live pipe" branch the brief
 * offered is not actually robust here). Instead: a spectral-flux onset
 * envelope over the low band, autocorrelated over a rolling ~8s window.
 * This reuses a stream the shell already runs (no new process).
 *
 * FRAME-RATE INDEPENDENT SAMPLING. spectrum.conf's cava framerate is a
 * moving target (30fps historically, desktop-first work elsewhere in this
 * branch raises it towards the monitor's own refresh rate), and
 * onSpectrumChanged fires however often cava actually emits a frame, not
 * on any schedule this service controls. So the raw per-frame onset values
 * are resampled onto a fixed WALL-CLOCK grid (`binDuration`, real seconds
 * via Date.now(), not a frame count) before they ever reach the history
 * buffer -- each bin keeps the loudest onset seen inside it (a kick landing
 * between two fast frames must not be averaged away). The autocorrelation
 * below then always operates on one bin = one fixed time slice, so its lag
 * -> BPM math stays correct regardless of the underlying cava rate.
 *
 * ONSET ENVELOPE. Each new spectrum frame's low band (bins 0..7, the bass
 * end of the 50-10000Hz range spectrum.conf already extracts) is averaged
 * into one energy scalar; the onset strength is its half-wave-rectified
 * frame-to-frame delta (standard spectral flux) -- kicks and bass hits
 * produce a strong positive spike, decays and steady tone do not.
 *
 * AUTOCORRELATION. The last ~8s of binned onset values (240 bins at the
 * fixed 20Hz grid) are mean-centred and autocorrelated over an EXTENDED lag
 * range (60-200 BPM, wider than the 70-180 target) so an octave error
 * (correlating with every other beat, or with half-beats) still shows up
 * inside the search window instead of outside it. The winning lag is then
 * folded (halved/doubled) into the canonical 70-180 BPM band before being
 * reported.
 *
 * CONFIDENCE. `available` only goes true once the window has enough
 * history AND the winning lag's normalised score clears a floor -- a flat
 * or arrhythmic passage (no clear periodicity) reports unavailable rather
 * than a noisy number, and VinylDisc falls back to its fixed default rpm.
 *
 * SMOOTHING. The raw per-window estimate is retargeted onto a slow,
 * critically-damped MotionValue (bpmSpring) -- VinylDisc reads
 * `TempoService.bpm`/`TempoService.available`, never the raw estimate, so
 * a track's tempo reading glides rather than snapping bar to bar.
 *
 * ON BATTERY the spectrum cava is deliberately not run (see the BATTERY
 * GATE note in VisualizerService.qml), so there is no onset feed. Going on
 * battery marks the reading unavailable and clears the window, so VinylDisc
 * uses its fixed default rpm rather than holding the last track's BPM
 * (which would be wrong the moment the track changes, with nothing to
 * correct it). Plugging back in starts a fresh window and re-estimates
 * after ~6s of live audio, same as a new track.
 */
QtObject {
    id: root

    readonly property int lowBandCount: 8
    // Fixed WALL-CLOCK resample grid -- deliberately decoupled from
    // spectrum.conf's cava framerate (see header). 20Hz is dense enough to
    // resolve a 180 BPM beat (3Hz) with headroom, and cheap either way this
    // is only touched a few times a second, not per rendered frame.
    readonly property real sampleDt: 0.05 // 20Hz bins
    readonly property int historySize: 240 // ~8s at 20Hz

    property real _binStartTime: -1 // seconds, Date.now()/1000
    property real _binMaxFlux: 0

    readonly property real minBpm: 70
    readonly property real maxBpm: 180
    // Wider search range so a genuine half/double-time correlation peak is
    // still inside the window before folding, not clipped off at the edge.
    readonly property real searchMinBpm: 60
    readonly property real searchMaxBpm: 200

    property var _history: []
    property int _filled: 0
    property real _prevEnergy: 0
    property bool _prevEnergySet: false

    property real bpm: 0
    property bool available: false

    property MotionValue bpmSpring: MotionValue {
        id: bpmSpring
        // Slow, no-overshoot: a tempo reading changing speed should glide,
        // never snap or ring.
        omega: 1.1
        zeta: 1.0
        unit: "px"
    }

    Component.onCompleted: _reset()

    function _reset(): void {
        const h = []
        for (let i = 0; i < root.historySize; i++) h.push(0)
        root._history = h
        root._filled = 0
        root._prevEnergySet = false
        root._binStartTime = -1
        root._binMaxFlux = 0
        root._lastEstimateTime = -1
    }

    // Only estimate while a track is actually playing -- a paused/stopped
    // player must not keep contributing stale onset history to the window,
    // and a fresh play (new track) starts the window clean.
    property bool _wasPlaying: false
    property Connections _playingWatch: Connections {
        target: MediaService
        function onPlayingChanged(): void {
            if (MediaService.playing && !root._wasPlaying) root._reset()
            root._wasPlaying = MediaService.playing
            if (!MediaService.playing) {
                root.available = false
                bpmSpring.target = bpmSpring.value // freeze, don't decay to 0
            }
        }
    }

    property Connections _batteryWatch: Connections {
        target: BatteryService
        function onOnBatteryChanged(): void {
            // Either direction: the feed stops/starts, so any history is
            // either stale (battery) or has a hole in it (back on AC).
            root._reset()
            if (BatteryService.onBattery) {
                root.available = false
                bpmSpring.target = bpmSpring.value // freeze, don't decay to 0
            }
        }
    }

    property Connections _spectrumWatch: Connections {
        target: VisualizerService
        function onSpectrumChanged(): void {
            if (!MediaService.playing || !VisualizerService.spectrumAvailable)
                return
            root._sample()
        }
    }

    // Called however often cava actually emits a spectrum frame -- could be
    // 30/s or 240/s depending on spectrum.conf, or irregular under load.
    // Only the flux VALUE is computed here; time-grid resampling happens
    // in _pushBin below, keyed off Date.now(), never off how many times
    // this function has been called.
    function _sample(): void {
        const spectrum = VisualizerService.spectrum
        let sum = 0
        const n = Math.min(root.lowBandCount, spectrum.length)
        if (n === 0) return
        for (let i = 0; i < n; i++) sum += (spectrum[i] || 0)
        const energy = sum / n

        const flux = root._prevEnergySet ? Math.max(0, energy - root._prevEnergy) : 0
        root._prevEnergy = energy
        root._prevEnergySet = true

        root._pushBin(flux)
    }

    property real _lastEstimateTime: -1

    // Resample onto the fixed `sampleDt` wall-clock grid: keep the loudest
    // onset seen inside the current bin (a spike must not get averaged
    // away by whatever the underlying cava rate happens to be), and only
    // commit a bin to history once real time has actually advanced past
    // its duration.
    function _pushBin(flux: real): void {
        const now = Date.now() / 1000
        if (root._binStartTime < 0) {
            root._binStartTime = now
            root._binMaxFlux = flux
            return
        }
        root._binMaxFlux = Math.max(root._binMaxFlux, flux)
        if (now - root._binStartTime < root.sampleDt)
            return

        const h = root._history
        h.shift()
        h.push(root._binMaxFlux)
        root._history = h
        root._filled = Math.min(root.historySize, root._filled + 1)
        root._binStartTime = now
        root._binMaxFlux = 0

        // Re-estimate roughly once a second of WALL-CLOCK time, not once
        // every N bins -- stays correct even if bins arrive at a slightly
        // uneven cadence.
        if (root._filled >= 120
                && (root._lastEstimateTime < 0 || now - root._lastEstimateTime >= 1.0)) {
            root._lastEstimateTime = now
            root._estimate()
        }
    }

    function _estimate(): void {
        const h = root._history
        const w = root._filled
        const start = root.historySize - w
        let mean = 0
        for (let i = start; i < root.historySize; i++) mean += h[i]
        mean /= w
        const centered = []
        for (let i = start; i < root.historySize; i++) centered.push(h[i] - mean)

        const minLag = Math.max(2, Math.floor(60 / root.searchMaxBpm / root.sampleDt))
        const maxLag = Math.min(centered.length - 1,
            Math.ceil(60 / root.searchMinBpm / root.sampleDt))
        if (maxLag <= minLag) return

        let bestLag = -1
        let bestScore = -Infinity
        for (let lag = minLag; lag <= maxLag; lag++) {
            let score = 0
            const count = centered.length - lag
            for (let i = 0; i < count; i++) score += centered[i] * centered[i + lag]
            score /= count
            if (score > bestScore) {
                bestScore = score
                bestLag = lag
            }
        }
        if (bestLag < 0) return

        // Confidence: winning score vs the zero-lag variance -- a flat/
        // noisy envelope has no strong periodic peak relative to its own
        // energy.
        let zeroLag = 0
        for (let i = 0; i < centered.length; i++) zeroLag += centered[i] * centered[i]
        zeroLag /= centered.length
        const confidence = zeroLag > 1e-9 ? bestScore / zeroLag : 0

        let candidateBpm = 60 / (bestLag * root.sampleDt)
        // Fold any octave error into the canonical 70-180 band.
        while (candidateBpm < root.minBpm) candidateBpm *= 2
        while (candidateBpm > root.maxBpm) candidateBpm /= 2

        const confident = confidence > 0.18
        root.available = confident
        if (confident) {
            root.bpm = candidateBpm
            bpmSpring.target = candidateBpm
        }
    }

    // Public smoothed reading -- what VinylDisc actually consumes.
    readonly property real smoothedBpm: bpmSpring.value
}
