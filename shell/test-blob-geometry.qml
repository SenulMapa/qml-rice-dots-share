// Unit test for core/BlobGeometry.qml -- the Now Playing card's animated
// mask blob (panels/DashboardMediaCard.qml). Verifies the three invariants
// the owner asked for:
//   1. amplitude never exceeds the requested 3-6% band
//   2. the anchor ring never self-intersects across a full beat cycle
//   3. the ring's area (a cheap proxy for "how much of the slot is still
//      covered") never collapses -- it stays close to its resting value
// ...plus that generatePath() actually closes (start point == end point of
// the final segment), which is what keeps the mask from tearing open.
import QtQuick
import Quickshell
import "core"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    Timer {
        interval: 0; running: true; repeat: false
        onTriggered: root.run()
    }

    function run() {
        // ---- amplitude bound: 3-6% of the viewBox, as requested -------
        root.ok("amplitude_within_requested_band",
            BlobGeometry.ampFraction >= 0.03 && BlobGeometry.ampFraction <= 0.06,
            "" + BlobGeometry.ampFraction)

        // ---- periods are all in the requested 6-10s slow/incommensurate
        // band, and none share an exact period (which would just be a
        // slower version of the same beat, not independent motion). -----
        let periodsOk = true
        const seen = []
        for (let i = 0; i < BlobGeometry.anchors.length; i++) {
            const px = BlobGeometry.periodX[i], py = BlobGeometry.periodY[i]
            if (px < 6 || px > 10 || py < 6 || py > 10)
                periodsOk = false
            if (seen.indexOf(px) >= 0 || seen.indexOf(py) >= 0)
                periodsOk = false
            seen.push(px, py)
        }
        root.ok("periods_slow_and_distinct", periodsOk)

        // ---- sweep a bit over 12s (covers at least one full cycle of the
        // shortest 6.1s period) and check every sample. ------------------
        const restArea = BlobGeometry.ringArea(BlobGeometry.animatedAnchors(0))
        let maxDeviation = { x: 0, y: 0 }
        let anyIntersect = false
        let minAreaRatio = 1
        let maxAreaRatio = 1
        const dt = 0.2
        for (let t = 0; t <= 12.2; t += dt) {
            const ring = BlobGeometry.animatedAnchors(t)
            for (let i = 0; i < ring.length; i++) {
                const dx = Math.abs(ring[i].x - BlobGeometry.anchors[i].x)
                const dy = Math.abs(ring[i].y - BlobGeometry.anchors[i].y)
                if (dx > maxDeviation.x) maxDeviation.x = dx
                if (dy > maxDeviation.y) maxDeviation.y = dy
            }
            if (BlobGeometry.ringSelfIntersects(ring))
                anyIntersect = true
            const ratio = BlobGeometry.ringArea(ring) / restArea
            if (ratio < minAreaRatio) minAreaRatio = ratio
            if (ratio > maxAreaRatio) maxAreaRatio = ratio
        }

        root.ok("anchor_deviation_within_amplitude",
            maxDeviation.x <= BlobGeometry.ampX + 0.01
                && maxDeviation.y <= BlobGeometry.ampY + 0.01,
            "dx=" + maxDeviation.x.toFixed(2) + " dy=" + maxDeviation.y.toFixed(2)
                + " ampX=" + BlobGeometry.ampX.toFixed(2)
                + " ampY=" + BlobGeometry.ampY.toFixed(2))

        root.ok("never_self_intersects_over_a_full_cycle", !anyIntersect)

        // A ~4.5%-amplitude wobble of independent points should never come
        // close to halving or doubling the ring's area -- this is a loose
        // sanity bound (not the true bezier-fill fraction) that would catch
        // a gross regression (e.g. a sign error blowing amplitude up).
        root.ok("area_stays_close_to_rest",
            minAreaRatio >= 0.85 && maxAreaRatio <= 1.15,
            "min=" + minAreaRatio.toFixed(3) + " max=" + maxAreaRatio.toFixed(3))

        // ---- generatePath() actually closes ----------------------------
        const t = 5.5
        const path = BlobGeometry.generatePath(t)
        const p0 = BlobGeometry.anchorPositionAt(0, t)
        const startMatch = path.match(/^M(-?[\d.]+) (-?[\d.]+)/)
        root.ok("path_starts_at_animated_p0",
            !!startMatch
                && Math.abs(Number(startMatch[1]) - p0.x) < 0.01
                && Math.abs(Number(startMatch[2]) - p0.y) < 0.01,
            path.slice(0, 24))
        // Last two numbers before the closing Z are the final curve's end
        // point, which by construction (segment P7->P0) must equal p0.
        const beforeZ = path.slice(0, path.length - 1)
        const nums = beforeZ.match(/-?[\d.]+/g)
        const lastX = Number(nums[nums.length - 2])
        const lastY = Number(nums[nums.length - 1])
        root.ok("path_closes_back_to_animated_p0",
            Math.abs(lastX - p0.x) < 0.01 && Math.abs(lastY - p0.y) < 0.01,
            lastX + "," + lastY + " vs " + p0.x + "," + p0.y)

        console.log("=== BLOB GEOMETRY TEST ===")
        for (const line of root.log)
            console.log(line)
        const failed = root.log.filter(l => l.startsWith("FAIL")).length
        console.log("=== " + (root.log.length - failed) + "/"
            + root.log.length + " passed ===")
        Qt.quit()
    }
}
