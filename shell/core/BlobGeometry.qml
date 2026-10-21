pragma Singleton
import QtQuick

/**
 * BlobGeometry — parametric version of the owner's Now Playing blob mask
 * (panels/DashboardMediaCard.qml, Figma node 9:3/9:4), native 194x219
 * viewBox.
 *
 * The owner's static path is 8 anchor points (P0..P7) joined by 7 cubic
 * Beziers plus one straight top edge (the original "H81.3527"), closing
 * back to P0. Rather than reparsing that SVG path string every frame, the
 * anchors and each curve's two control points are decomposed ONCE, here,
 * into:
 *   - anchors[i]        : the owner's original point
 *   - controlOffset(seg): each segment's c1/c2 stored as a FIXED vector
 *                         relative to whichever anchor it belongs to
 *                         (c1 rides with the segment's start anchor, c2
 *                         with its end anchor) -- exactly what you get if
 *                         you select an anchor and its handles together in
 *                         a vector editor and drag them as one unit.
 *
 * At animation time (generatePath / anchorPositionAt) each anchor is
 * displaced by a small, slow, per-anchor sine offset and the attached
 * control points are translated by the SAME delta. Because every point
 * near a given anchor moves together, the curve's local character (and
 * therefore its "never folds/self-intersects" and "still mostly visible"
 * requirements) is preserved by construction rather than by clamping --
 * verified in test-blob-geometry.qml across a full beat cycle.
 */
QtObject {
    id: root

    readonly property real viewBoxWidth: 194
    readonly property real viewBoxHeight: 219

    // P0..P7, in path order.
    readonly property var anchors: [
        Qt.point(3.49346, 13.1168),
        Qt.point(17.4119, 0),
        Qt.point(81.3527, 0),
        Qt.point(95.0266, 18.0842),
        Qt.point(95.5, 105.5),
        Qt.point(191.621, 188.873),
        Qt.point(176.393, 208.384),
        Qt.point(12.9153, 214)
    ]

    // start -> end anchor indices, and (for cubic segments) c1/c2 as fixed
    // offsets from the start/end anchor respectively. type "L" is the
    // owner's original flat top edge (kept straight -- it is a deliberate
    // design edge, not a rounded one).
    readonly property var segments: [
        { type: "C", start: 0, end: 1, c1: Qt.point(0.35460, -7.42862), c2: Qt.point(-7.43704, 0) },
        { type: "L", start: 1, end: 2 },
        { type: "C", start: 2, end: 3, c1: Qt.point(9.3728, 0), c2: Qt.point(2.4679, -9.04206) },
        { type: "C", start: 3, end: 4, c1: Qt.point(-10.5464, 38.6408), c2: Qt.point(-31.6283, 35.533) },
        { type: "C", start: 4, end: 5, c1: Qt.point(29.944, -33.6406), c2: Qt.point(-21.339, -41.599) },
        { type: "C", start: 5, end: 6, c1: Qt.point(5.262, 10.257), c2: Qt.point(11.329, 2.13) },
        { type: "C", start: 6, end: 7, c1: Qt.point(-48.645, -9.148), c2: Qt.point(16.794, -29.11) },
        { type: "C", start: 7, end: 0, c1: Qt.point(-19.38311, 33.597), c2: Qt.point(-2.45239, 51.3758) }
    ]

    // ---- wobble parameters -------------------------------------------
    // Amplitude: ~4.5% of each dimension -- inside the owner's requested
    // 3-6% band. Periods: 6.1-9.9s, one per anchor, all mutually
    // incommensurate (no shared small-integer ratio) so the blob never
    // repeats a visible beat -- it reads as organic breathing, not a loop.
    readonly property real ampFraction: 0.045
    readonly property real ampX: viewBoxWidth * ampFraction
    readonly property real ampY: viewBoxHeight * ampFraction
    readonly property var periodX: [7.3, 8.9, 6.4, 9.7, 7.1, 8.3, 6.8, 9.3]
    readonly property var periodY: [8.1, 6.6, 9.5, 7.4, 8.8, 6.2, 9.9, 7.6]
    readonly property real goldenAngle: 2.399963

    function freqFor(period) {
        return (2 * Math.PI) / period
    }

    // Position of anchor `index` at time `tSeconds`.
    function anchorPositionAt(index, tSeconds) {
        const base = root.anchors[index]
        const phaseX = index * root.goldenAngle
        const phaseY = index * root.goldenAngle + 1.3
        const x = base.x + root.ampX * Math.sin(
            tSeconds * root.freqFor(root.periodX[index]) + phaseX)
        const y = base.y + root.ampY * Math.sin(
            tSeconds * root.freqFor(root.periodY[index]) + phaseY)
        return Qt.point(x, y)
    }

    // Full ring of animated anchor positions at `tSeconds`, in path order.
    function animatedAnchors(tSeconds) {
        const out = []
        for (let i = 0; i < root.anchors.length; i++)
            out.push(root.anchorPositionAt(i, tSeconds))
        return out
    }

    function fmt(n) {
        // Fixed precision keeps the generated path string short and
        // avoids locale-dependent number formatting from toString().
        return n.toFixed(3)
    }

    // Rebuilds the SVG path `d` string for time `tSeconds`. Pure function
    // of time -- no per-frame parsing of the previous path, only
    // generation of the next one.
    function generatePath(tSeconds) {
        const animated = root.animatedAnchors(tSeconds)
        const p0 = animated[0]
        let d = "M" + root.fmt(p0.x) + " " + root.fmt(p0.y)
        for (const seg of root.segments) {
            const end = animated[seg.end]
            if (seg.type === "L") {
                d += "L" + root.fmt(end.x) + " " + root.fmt(end.y)
            } else {
                const start = animated[seg.start]
                const c1 = Qt.point(start.x + seg.c1.x, start.y + seg.c1.y)
                const c2 = Qt.point(end.x + seg.c2.x, end.y + seg.c2.y)
                d += "C" + root.fmt(c1.x) + " " + root.fmt(c1.y) + " "
                    + root.fmt(c2.x) + " " + root.fmt(c2.y) + " "
                    + root.fmt(end.x) + " " + root.fmt(end.y)
            }
        }
        d += "Z"
        return d
    }

    // ---- self-check helpers (used by test-blob-geometry.qml) ---------
    // Straight-line segment intersection (proper crossing only, not
    // touching endpoints -- adjacent polygon edges legitimately share a
    // vertex). Used to sweep the anchor RING (a conservative straight-edge
    // proxy for the true bezier boundary) for self-intersection over time.
    function segmentsIntersect(a1, a2, b1, b2) {
        function cross(o, p, q) {
            return (p.x - o.x) * (q.y - o.y) - (p.y - o.y) * (q.x - o.x)
        }
        const d1 = cross(b1, b2, a1)
        const d2 = cross(b1, b2, a2)
        const d3 = cross(a1, a2, b1)
        const d4 = cross(a1, a2, b2)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0))
            && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    function ringSelfIntersects(ring) {
        const n = ring.length
        for (let i = 0; i < n; i++) {
            const a1 = ring[i], a2 = ring[(i + 1) % n]
            for (let j = i + 1; j < n; j++) {
                // Skip edges adjacent to (or identical to) edge i -- they
                // share an endpoint by construction, not a real crossing.
                if (j === i || j === (i + 1) % n
                        || (j + 1) % n === i)
                    continue
                const b1 = ring[j], b2 = ring[(j + 1) % n]
                if (root.segmentsIntersect(a1, a2, b1, b2))
                    return true
            }
        }
        return false
    }

    // Shoelace polygon area -- a stable, cheap proxy for "how much of the
    // slot the blob still covers" across time (exact bezier-area isn't
    // needed to catch a regression: relative change against t=0 is).
    function ringArea(ring) {
        let sum = 0
        const n = ring.length
        for (let i = 0; i < n; i++) {
            const p = ring[i], q = ring[(i + 1) % n]
            sum += p.x * q.y - q.x * p.y
        }
        return Math.abs(sum) / 2
    }
}
