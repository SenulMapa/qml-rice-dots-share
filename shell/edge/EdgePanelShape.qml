import QtQuick
import QtQuick.Shapes
import "../core"

/**
 * EdgePanelShape -- the "attached-to-the-edge, morphing out" panel body
 * for VolumeEdgeGauge (owner feedback: "the volume container doesn't
 * morph out of the corners" -- it must be flush against the screen edge
 * and flare into it, Caelestia-drawer style, not a free-floating tank).
 *
 * A single QtQuick.Shapes ShapePath. Geometry is authored in (k, y) space
 * -- k = distance from the docked edge (k=0 is flush against the physical
 * screen edge, k=width is the outer/far side) -- then mapped to real x via
 * `_x(k) = edgeX + dir*k`. That map is the ONLY thing that differs between
 * the left-dock (HDMI) and right-dock (DP) instance, so the two mirror
 * exactly with no duplicated geometry.
 *
 * Two corner families:
 *   - OUTER corners (far side, k=width): ordinary convex rounded corners,
 *     center inset by (r,r) from the mathematical corner -- ships never
 *     touch these; a plain rounded rect edge.
 *   - EDGE fillets (k=0, top and bottom): CONCAVE -- center sits AT the
 *     mathematical edge-corner (no inset), so the quarter-disk nearest
 *     that corner is excluded from the panel. The remaining boundary
 *     curves smoothly from the panel's flat top/bottom edge into the
 *     dead-flush vertical line against the screen edge, which is what
 *     reads as "panel and bezel are one continuous surface".
 *
 * Every arc's start/end angle is computed via atan2 (not hand-picked),
 * because atan2 already bakes in `dir` -- the same formula produces the
 * correct mirrored sweep for both docks without a separate sign table
 * that would need re-deriving (and re-breaking) per mirror.
 *
 * `topFillet`/`bottomFillet` independently collapse to 0 near a screen
 * corner (driven by the caller, VolumeEdgeGauge.qml) -- flaring into a
 * bezel that isn't there (because the panel is flush with the monitor's
 * REAL corner) reads as a bite taken out of the screen, so that fillet
 * is squared off instead. A near-zero radius degenerates safely: the
 * PathLine and PathAngleArc both collapse to the same point, i.e. a
 * plain square corner, not a rendering artefact.
 */
Shape {
    id: root

    required property string dockEdge   // "left" or "right"
    property real cornerRadius: Theme.u(0.45)
    property real topFillet: cornerRadius
    property real bottomFillet: cornerRadius
    property color fillColor: Theme.surfaceContainer

    preferredRendererType: Shape.CurveRenderer
    antialiasing: true
    visible: width > 0.5 && height > 0.5

    readonly property bool _mirrored: dockEdge === "left"
    readonly property real _dir: _mirrored ? 1 : -1
    readonly property real _edgeX: _mirrored ? 0 : width

    readonly property real _rTF: _clampR(topFillet)
    readonly property real _rBF: _clampR(bottomFillet)
    readonly property real _rTO: _clampR(cornerRadius)
    readonly property real _rBO: _clampR(cornerRadius)

    function _clampR(r) {
        return Math.max(0.01, Math.min(r, width, height / 2))
    }

    function _x(k) { return root._edgeX + root._dir * k }

    // Angle (degrees) of point (k,y) as seen from center (ck,cy), with
    // `dir` folded into dx so mirroring is already accounted for.
    function _ang(k, y, ck, cy) {
        const dx = root._dir * (k - ck)
        const dy = y - cy
        return Math.atan2(dy, dx) * 180 / Math.PI
    }

    // Minor-arc sweep from a0 to a1, normalised to (-180, 180].
    function _sweep(a0, a1) {
        let d = a1 - a0
        while (d > 180) d -= 360
        while (d <= -180) d += 360
        return d
    }

    readonly property real _w: width
    readonly property real _h: height

    ShapePath {
        fillColor: root.fillColor
        strokeWidth: -1

        startX: root._x(root._w - root._rTO)
        startY: 0

        // Top straight edge, outer corner -> edge fillet start.
        PathLine { x: root._x(root._rTF); y: 0 }
        // Top concave fillet: flat top edge flares into the flush edge line.
        PathAngleArc {
            moveToStart: false
            centerX: root._x(0); centerY: 0
            radiusX: root._rTF; radiusY: root._rTF
            startAngle: root._ang(root._rTF, 0, 0, 0)
            sweepAngle: root._sweep(
                root._ang(root._rTF, 0, 0, 0),
                root._ang(0, root._rTF, 0, 0))
        }
        // Flush vertical line against the physical screen edge.
        PathLine { x: root._x(0); y: root._h - root._rBF }
        // Bottom concave fillet: edge line flares back into the flat bottom.
        PathAngleArc {
            moveToStart: false
            centerX: root._x(0); centerY: root._h
            radiusX: root._rBF; radiusY: root._rBF
            startAngle: root._ang(0, root._h - root._rBF, 0, root._h)
            sweepAngle: root._sweep(
                root._ang(0, root._h - root._rBF, 0, root._h),
                root._ang(root._rBF, root._h, 0, root._h))
        }
        // Bottom straight edge, edge fillet end -> outer corner start.
        PathLine { x: root._x(root._w - root._rBO); y: root._h }
        // Bottom-left (outer) convex corner.
        PathAngleArc {
            moveToStart: false
            centerX: root._x(root._w - root._rBO); centerY: root._h - root._rBO
            radiusX: root._rBO; radiusY: root._rBO
            startAngle: root._ang(root._w - root._rBO, root._h,
                root._w - root._rBO, root._h - root._rBO)
            sweepAngle: root._sweep(
                root._ang(root._w - root._rBO, root._h,
                    root._w - root._rBO, root._h - root._rBO),
                root._ang(root._w, root._h - root._rBO,
                    root._w - root._rBO, root._h - root._rBO))
        }
        // Outer straight edge (the far side, away from the screen edge).
        PathLine { x: root._x(root._w); y: root._rTO }
        // Top-left (outer) convex corner, closing back to the start point.
        PathAngleArc {
            moveToStart: false
            centerX: root._x(root._w - root._rTO); centerY: root._rTO
            radiusX: root._rTO; radiusY: root._rTO
            startAngle: root._ang(root._w, root._rTO,
                root._w - root._rTO, root._rTO)
            sweepAngle: root._sweep(
                root._ang(root._w, root._rTO, root._w - root._rTO, root._rTO),
                root._ang(root._w - root._rTO, 0, root._w - root._rTO, root._rTO))
        }
    }
}
