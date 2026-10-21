pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."

/**
 * VisualizerService — drives the pill's 4-bar meter from cava, the console
 * audio visualizer, instead of a canned animation loop (island/Eq.qml).
 *
 * The process runs ONLY while MediaService.playing is true AND at least one
 * Island window's Eq consumer is actually on screen (anyWindowVisible,
 * registered/unregistered by island/Island.qml -- see eqConsumerVisible
 * there). This mirrors the resting pill's own rule (see
 * island/IslandRestItem.qml's clockComponent comment): an always-on meter
 * loop was measured at 6% idle CPU and defeats the frame clock's sleep. No
 * music, or music but nothing showing the meter (auto-hidden/parked
 * off-screen) -> no process -> genuinely idle.
 *
 * Failure handling was worked out empirically against this Quickshell
 * build (0.2.1), not guessed:
 *   - `Process.onErrorOccurred` is declared in quickshell-io.qmltypes but
 *     is NOT an assignable QML property in this build ("Cannot assign to
 *     non-existent property"), so it cannot be used.
 *   - A missing binary (cava not installed) never fires `exited` at all --
 *     only `running` flips back to false, with Quickshell itself logging a
 *     WARN. A real binary that exits fast (bad args/config) DOES fire
 *     `exited`, quickly, with a real exit code.
 * So the one signal that reliably covers both failure shapes is `running`
 * going false while MediaService.playing is still true -- that can only
 * mean cava stopped on its own, not because we asked it to. That is the
 * single point where `disabledForSession` latches: don't respawn in a
 * tight loop, log once, and let a future MediaService.playing transition
 * (the next track) be the only thing that tries again.
 */
QtObject {
    id: root

    readonly property int barCount: 4

    property var _levels: [0, 0, 0, 0]
    readonly property var levels: _levels
    property bool available: false

    // ---- spectrum (64-bin) -----------------------------------------------
    //
    // BATTERY GATE. This 64-bin cava is the expensive one (measured on the
    // T480 on battery with just a browser video playing: ~17% CPU for the
    // cava process alone, plus the QML redraws its stream of `spectrum`
    // changes drags along). It never runs while BatteryService.onBattery.
    // Consumers register through setSpectrumVisible(): components/
    // VinylDisc.qml's ring and panels/DashboardMediaCard.qml. Neither is in
    // the live shell since the glass dashboard (panels/DashboardSlim.qml)
    // replaced them -- only render harnesses load them -- so today this
    // cava never starts at all; the battery gate keeps it off on battery
    // if a consumer returns (TempoService then loses its onset feed, see
    // its own header). The edge visualizer is NOT a consumer -- it spawns
    // its own per-screen cava. Plugging in flips `running` back on through the binding below,
    // no extra wiring.
    //
    // Separate from `levels`/`available` above on purpose -- this feeds the
    // dashboard Now Playing card's circular ring (panels/DashboardMediaCard
    // .qml), a different consumer with a different cava process/config
    // (scripts/cava/spectrum.conf), so a failure or an idle ring can never
    // touch island/Eq.qml's already-shipped 4-bar meter or vice versa.
    readonly property int spectrumBarCount: 64
    property var _spectrum: []
    readonly property var spectrum: _spectrum
    property bool spectrumAvailable: false
    property bool spectrumDisabledForSession: false
    property bool spectrumWarned: false
    property bool sawSpectrumExitThisRun: false
    property int lastSpectrumExitCode: -1

    Component.onCompleted: {
        const zeros = []
        for (let i = 0; i < root.spectrumBarCount; i++) zeros.push(0)
        root._spectrum = zeros
    }

    // Same visibility-gating pattern as _visibleWindows/anyWindowVisible
    // below, keyed separately so the dashboard ring and the island pill
    // register/unregister independently of each other.
    property var _spectrumVisibleWindows: ({})
    property bool anySpectrumVisible: false
    function setSpectrumVisible(key: string, vis: bool): void {
        if (vis)
            root._spectrumVisibleWindows[key] = true
        else
            delete root._spectrumVisibleWindows[key]
        root.anySpectrumVisible =
            Object.keys(root._spectrumVisibleWindows).length > 0
    }

    function warnSpectrumOnce(message: string): void {
        if (root.spectrumWarned)
            return
        root.spectrumWarned = true
        console.warn("Odyssey VisualizerService (spectrum):", message)
    }

    // Lighter damping than the 4-bar meter's: no inter-bar mean-blend here
    // (that would flatten the ring back down to a near-uniform circle,
    // defeating the point of a 64-bin spectrum), just per-bin sqrt
    // compression plus the same asymmetric attack/decay lerp so bars don't
    // visibly jitter frame to frame.
    function parseSpectrumFrame(line: string): void {
        const parts = line.split(";").filter(part => part.length > 0)
        if (parts.length < root.spectrumBarCount)
            return

        const next = []
        for (let i = 0; i < root.spectrumBarCount; i++) {
            const raw = Number(parts[i])
            const clamped = Number.isFinite(raw)
                ? Math.max(0, Math.min(1, raw / 1000)) : 0
            const target = Math.sqrt(clamped)
            const prev = root._spectrum[i] || 0
            const alpha = target > prev ? root._attackAlpha : root._decayAlpha
            next.push(prev + (target - prev) * alpha)
        }
        root._spectrum = next
        root.spectrumAvailable = true
    }

    property bool disabledForSession: false
    property bool warned: false
    property bool sawExitThisRun: false
    property int lastExitCode: -1

    // ---- visibility gating ---------------------------------------------
    // cava must not run just because music is playing -- it must also not
    // run when nothing on screen is actually reading its output (the pill
    // parked off-screen behind Config.island.autoHide, or a monitor whose
    // island is disabled entirely). Each Island.qml window registers itself
    // here by a unique key while its Eq consumer is genuinely on screen;
    // the process only runs while at least one is. A plain object used as a
    // set, not a count, so a window that registers "visible" twice in a row
    // (a redundant binding re-evaluation) can't double-decrement later.
    property var _visibleWindows: ({})
    property bool anyWindowVisible: false
    function setWindowVisible(key: string, vis: bool): void {
        if (vis)
            root._visibleWindows[key] = true
        else
            delete root._visibleWindows[key]
        root.anyWindowVisible = Object.keys(root._visibleWindows).length > 0
    }

    function warnOnce(message: string): void {
        if (root.warned)
            return
        root.warned = true
        console.warn("Odyssey VisualizerService:", message)
    }

    // ---- damping ---------------------------------------------------------
    // Calm, musical motion instead of a literal spectrum readout:
    //  1. sqrt compression narrows the amplitude range (a quiet bar and a
    //     loud bar read less like an on/off strobe).
    //  2. each bar blends 30% toward the group mean, so the four bars move
    //     more like one breathing shape than four independent needles.
    //  3. asymmetric attack/decay -- fast rise (~75ms tau), slow fall
    //     (~300ms tau) -- so a beat still snaps in but decays like a real
    //     meter's ballistics instead of chattering back down every frame.
    // Tau -> per-frame alpha at cava's own 30fps (scripts/cava/eq.conf):
    // alpha = 1 - exp(-dt/tau), dt = 1/30s.
    readonly property real _attackAlpha: 0.36   // tau ~75ms
    readonly property real _decayAlpha: 0.10    // tau ~300ms
    readonly property real _meanBlend: 0.30

    function parseFrame(line: string): void {
        const parts = line.split(";").filter(part => part.length > 0)
        if (parts.length < root.barCount)
            return

        const compressed = []
        let sum = 0
        for (let i = 0; i < root.barCount; i++) {
            const raw = Number(parts[i])
            const clamped = Number.isFinite(raw) ? Math.max(0, Math.min(1, raw / 1000)) : 0
            const c = Math.sqrt(clamped)
            compressed.push(c)
            sum += c
        }
        const mean = sum / root.barCount

        const next = []
        for (let i = 0; i < root.barCount; i++) {
            const target = compressed[i] * (1 - root._meanBlend) + mean * root._meanBlend
            const prev = root._levels[i] || 0
            const alpha = target > prev ? root._attackAlpha : root._decayAlpha
            next.push(prev + (target - prev) * alpha)
        }
        root._levels = next
        root.available = true
    }

    property Process cavaProcess: Process {
        id: cavaProcess
        command: ["cava", "-p", Quickshell.shellDir + "/scripts/cava/eq.conf"]
        running: MediaService.playing && !root.disabledForSession
            && root.anyWindowVisible

        stdout: SplitParser {
            onRead: data => root.parseFrame(data)
        }

        onExited: (exitCode, exitStatus) => {
            root.sawExitThisRun = true
            root.lastExitCode = exitCode
        }

        onRunningChanged: {
            if (cavaProcess.running) {
                root.sawExitThisRun = false
                root.lastExitCode = -1
                return
            }
            root.available = false
            root._levels = [0, 0, 0, 0]
            // We stopped it on purpose (playback paused/stopped, nothing on
            // screen is showing it right now, or an earlier failure already
            // latched) -- nothing to report.
            if (!MediaService.playing || !root.anyWindowVisible || root.disabledForSession)
                return
            root.disabledForSession = true
            root.warnOnce(root.sawExitThisRun
                ? "cava exited unexpectedly (code " + root.lastExitCode
                    + ") -- falling back to the resting profile for this session"
                : "cava failed to start (is it installed?) -- falling back "
                    + "to the resting profile for this session")
        }
    }

    // Second, independent cava process for the 64-bin ring (see the
    // `spectrum` block above). Only runs while music is playing AND the
    // dashboard Now Playing card's ring is actually on screen -- an idle
    // dashboard tab or a closed island must not keep this running any more
    // than the 4-bar meter's own process should.
    property Process cavaSpectrumProcess: Process {
        id: cavaSpectrumProcess
        command: ["cava", "-p", Quickshell.shellDir + "/scripts/cava/spectrum.conf"]
        running: MediaService.playing && !root.spectrumDisabledForSession
            && root.anySpectrumVisible && !BatteryService.onBattery

        stdout: SplitParser {
            onRead: data => root.parseSpectrumFrame(data)
        }

        onExited: (exitCode, exitStatus) => {
            root.sawSpectrumExitThisRun = true
            root.lastSpectrumExitCode = exitCode
        }

        onRunningChanged: {
            if (cavaSpectrumProcess.running) {
                root.sawSpectrumExitThisRun = false
                root.lastSpectrumExitCode = -1
                return
            }
            root.spectrumAvailable = false
            const zeros = []
            for (let i = 0; i < root.spectrumBarCount; i++) zeros.push(0)
            root._spectrum = zeros
            // Going on battery is a deliberate stop too (see the BATTERY
            // GATE note above) -- it must never latch
            // spectrumDisabledForSession, or plugging back in would not
            // bring the spectrum back.
            if (!MediaService.playing || !root.anySpectrumVisible
                    || root.spectrumDisabledForSession || BatteryService.onBattery)
                return
            root.spectrumDisabledForSession = true
            root.warnSpectrumOnce(root.sawSpectrumExitThisRun
                ? "cava (spectrum) exited unexpectedly (code "
                    + root.lastSpectrumExitCode
                    + ") -- ring falls back to a static profile for this session"
                : "cava (spectrum) failed to start -- ring falls back to a "
                    + "static profile for this session")
        }
    }
}
