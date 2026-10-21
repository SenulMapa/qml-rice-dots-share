pragma Singleton
import QtQuick
import Quickshell.Io
import "."

/**
 * Registered as the singleton type `MotionFrameProbe` (see core/qmldir),
 * NOT `FrameProbe` -- components/FrameProbe.qml already claims that name
 * in the Odyssey.Components module, and island/Island.qml (and others)
 * import both "../core" and "../components" unqualified, so reusing the
 * bare name here would make `FrameProbe` an ambiguous type reference and
 * fail to compile every file that does that. Different type, different
 * name, both modules stay importable together.
 *
 * FrameProbe -- Motion's own frame-timing probe, IPC-accessible.
 * (docs/superpowers/specs/2026-09-23-blob-rebuild-design.md section 2:
 * "core/FrameProbe.qml + IPC target `frameprobe` -> histogram + count of
 * intervals > 1.5x the refresh period, recording only while
 * Motion.activeCount>0".)
 *
 * DISTINCT FROM components/FrameProbe.qml. That one is a per-window,
 * env-gated (QMLRICE_TRACE_FRAMES=1) probe an Island window instantiates
 * to diagnose ITS OWN vsync via Window.frameSwapped -- useful for the
 * 60-vs-120Hz debugging it was built for, but not something you'd want
 * live/always-on or reachable by IPC. This file is the opposite: always
 * present (cheap -- see gating below), reachable via `qs ipc call
 * frameprobe report`, and answers "is the shell dropping frames RIGHT NOW,
 * globally, while something is actually animating" for the blob engine's
 * "0 over-budget frames during a scripted open/close cycle" done-criterion.
 *
 * GATING. The probe's own FrameAnimation runs only while
 * Motion.activeCount > 0 -- exactly the condition under which dropped
 * frames matter (a resting shell has nothing moving to judge). At rest
 * this costs zero callbacks/frame, same sleep architecture as Motion's own
 * clock.
 *
 * REFRESH PERIOD. This singleton has no window/screen binding (unlike
 * components/FrameProbe.qml, which reads a real per-window vsync via
 * anchorItem.Window.window.frameSwapped), so "the refresh period" is
 * estimated from the samples themselves: the P10 (10th percentile,
 * cheaper and more robust than a bare min against a single stray fast
 * frame) of the currently buffered intervals approximates the fastest
 * screen's real frame period during that window. "Over budget" is any
 * interval > 1.5x that estimate.
 *
 * NEVER wire QT_LOGGING_RULES render-loop categories into this or
 * anything else -- that crashed the shell once already (see the design
 * spec and HANDOVER.md).
 */
QtObject {
    id: root

    readonly property int bufferSize: 4096
    property var ring: new Array(bufferSize)
    property int writeIndex: 0
    property int sampleCount: 0

    // NOT a FrameAnimation of its own. A singleton has no window/Item
    // ancestry, and island/Island.qml's own header comment on
    // perWindowMotionClock already measured exactly this shape of
    // FrameAnimation (unparented, riding ambient paint activity) to NOT
    // reliably track any specific output's vsync -- which is why this
    // probe used to record almost nothing across a whole open/close cycle
    // (2 frames over 6 cycles): its clock was firing at whatever rate the
    // process happened to already be painting SOMETHING at, not the rate
    // the island's own springs were actually stepping.
    //
    // Fed instead by every real per-window FrameAnimation (Island.qml's
    // perWindowMotionClock) calling recordFrame(frameTime*1000) right
    // alongside its own Motion.tick() -- the exact driver already proven
    // to track each screen's real presentation rate. Multiple windows
    // (multi-monitor) each contribute their own samples; report() doesn't
    // need to know which window a sample came from, only whether frames
    // were being delivered on budget while something was animating.
    function recordFrame(ms): void {
        if (Motion.activeCount <= 0)
            return
        root.ring[root.writeIndex] = ms
        root.writeIndex = (root.writeIndex + 1) % root.bufferSize
        if (root.sampleCount < root.bufferSize)
            root.sampleCount++
    }

    function _sortedSamples() {
        const n = root.sampleCount
        const out = new Array(n)
        for (let i = 0; i < n; i++)
            out[i] = root.ring[i]
        out.sort((a, b) => a - b)
        return out
    }

    function _percentile(sorted, p) {
        if (sorted.length === 0)
            return 0
        const idx = Math.min(sorted.length - 1, Math.floor(p * sorted.length))
        return sorted[idx]
    }

    // Fixed millisecond bucket edges: <4, <8, <12, <16, <20, <28, <40, <60, >=60.
    readonly property var bucketEdges: [4, 8, 12, 16, 20, 28, 40, 60]

    function _histogram(sorted) {
        const counts = new Array(root.bucketEdges.length + 1).fill(0)
        for (const ms of sorted) {
            let bucket = root.bucketEdges.length
            for (let i = 0; i < root.bucketEdges.length; i++) {
                if (ms < root.bucketEdges[i]) { bucket = i; break }
            }
            counts[bucket]++
        }
        return counts
    }

    /**
     * Returns { count, refreshPeriodMs, overBudgetCount, overBudgetRatio,
     * p50, p95, p99, histogram, bucketEdges } and resets the buffer, same
     * as components/FrameProbe.qml's own report() cadence.
     */
    function report() {
        const sorted = root._sortedSamples()
        const n = sorted.length
        if (n === 0) {
            return {
                count: 0, refreshPeriodMs: 0, overBudgetCount: 0,
                overBudgetRatio: 0, p50: 0, p95: 0, p99: 0,
                histogram: new Array(root.bucketEdges.length + 1).fill(0),
                bucketEdges: root.bucketEdges
            }
        }
        const refreshPeriodMs = root._percentile(sorted, 0.10)
        const overBudgetThreshold = refreshPeriodMs * 1.5
        let overBudgetCount = 0
        for (const ms of sorted)
            if (ms > overBudgetThreshold)
                overBudgetCount++

        const result = {
            count: n,
            refreshPeriodMs: refreshPeriodMs,
            overBudgetCount: overBudgetCount,
            overBudgetRatio: overBudgetCount / n,
            p50: root._percentile(sorted, 0.50),
            p95: root._percentile(sorted, 0.95),
            p99: root._percentile(sorted, 0.99),
            histogram: root._histogram(sorted),
            bucketEdges: root.bucketEdges
        }

        root.writeIndex = 0
        root.sampleCount = 0
        return result
    }

    property IpcHandler ipc: IpcHandler {
        target: "frameprobe"

        function report(): string {
            const r = root.report()
            return JSON.stringify(r)
        }
    }
}
