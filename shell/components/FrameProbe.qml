import QtQuick

/**
 * FrameProbe -- passive frame-timing probe, gated by QMLRICE_TRACE_FRAMES=1
 * (same pattern as the other QMLRICE_TRACE_* env gates -- grep QMLRICE_TRACE).
 * island/Island.qml only creates this inside an inactive Loader, so when the
 * gate is off nothing here is even constructed: zero cost.
 *
 * Samples FrameAnimation.frameTime (seconds since the previous frame) into a
 * preallocated ring buffer, keeping only "active" samples -- frames that
 * arrived under activeGapMs after the previous one -- so a long idle gap
 * between animations (the window asleep) is not recorded as one giant
 * dropped frame.
 *
 * CAVEAT (found chasing the 60-vs-120Hz island issue): this FrameAnimation
 * clock lives on a bare QtObject with no Item/window ancestry, same shape as
 * core/Motion.qml's own singleton clock used to be. An unparented
 * FrameAnimation does not track any ONE window's vsync -- it rides whatever
 * ambient paint activity already exists in the process, so historically this
 * probe reported near-identical ~8ms intervals on BOTH the 60Hz and 120Hz
 * screens. That number was measuring "the GUI animation-driver's cadence
 * somewhere in the process", never this window's own presentation rate.
 *
 * swaps= below is the number that actually answers the question: it counts
 * `anchorItem`'s OWN window's real frameSwapped signal (via the Window.window
 * attached property, which -- unlike this probe's own clock -- IS bound to
 * the specific QQuickWindow anchorItem lives in), so it reports genuine
 * per-output presentation counts: ~60/s on DP-1, ~120/s on HDMI-A-1 while
 * something is actually animating, ~0/s at rest on both.
 *
 * NOTE: while the gate is on, FrameAnimation.running keeps this window
 * painting every frame even at rest -- that is the probe's own overhead, not
 * the shell's normal behaviour, and is only acceptable because it is off by
 * default.
 *
 * Every reportIntervalMs this emits ONE console.log line per window and
 * resets:
 *   FRAMEPROBE <screenName> n=<count> p50=<ms> p95=<ms> p99=<ms> over20=<count> over34=<count> swaps=<perSecond>
 */
QtObject {
    id: root

    required property string screenName
    // Any Item that lives inside the window this probe should measure --
    // island/Island.qml passes its `surface`. Only used to reach the real
    // QQuickWindow via the Window attached property; never rendered.
    property Item anchorItem: null

    readonly property int bufferSize: 4096
    readonly property int reportIntervalMs: 10000
    readonly property real activeGapMs: 100

    property var ring: new Array(bufferSize)
    property int writeIndex: 0
    property int sampleCount: 0
    property int swapCount: 0

    property FrameAnimation clock: FrameAnimation {
        running: true
        onTriggered: {
            const intervalMs = frameTime * 1000.0
            if (intervalMs < root.activeGapMs) {
                root.ring[root.writeIndex] = intervalMs
                root.writeIndex = (root.writeIndex + 1) % root.bufferSize
                if (root.sampleCount < root.bufferSize)
                    root.sampleCount++
            }
        }
    }

    property Connections swapConnections: Connections {
        target: root.anchorItem ? root.anchorItem.Window.window : null
        function onFrameSwapped() { root.swapCount++ }
    }

    property Timer reportTimer: Timer {
        interval: root.reportIntervalMs
        running: true
        repeat: true
        onTriggered: root.report()
    }

    function percentile(sorted: var, p: real): real {
        const idx = Math.min(sorted.length - 1, Math.floor(p * sorted.length))
        return sorted[idx]
    }

    function report(): void {
        const swapsPerSec = root.swapCount / (root.reportIntervalMs / 1000.0)
        root.swapCount = 0

        const n = root.sampleCount
        if (n === 0) {
            console.log("FRAMEPROBE " + root.screenName
                + " n=0 p50=0 p95=0 p99=0 over20=0 over34=0"
                + " swaps=" + swapsPerSec.toFixed(1))
            return
        }

        const samples = new Array(n)
        for (let i = 0; i < n; i++)
            samples[i] = root.ring[i]
        samples.sort((a, b) => a - b)

        let over20 = 0
        let over34 = 0
        for (let i = 0; i < n; i++) {
            if (samples[i] > 20) over20++
            if (samples[i] > 34) over34++
        }

        console.log("FRAMEPROBE " + root.screenName + " n=" + n
            + " p50=" + root.percentile(samples, 0.50).toFixed(1)
            + " p95=" + root.percentile(samples, 0.95).toFixed(1)
            + " p99=" + root.percentile(samples, 0.99).toFixed(1)
            + " over20=" + over20 + " over34=" + over34
            + " swaps=" + swapsPerSec.toFixed(1))

        root.writeIndex = 0
        root.sampleCount = 0
    }
}
