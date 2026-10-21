import QtQuick
import "../core"

/**
 * BlobSurface -- QML wrapper around shaders/blob.frag.qsb: the one shape
 * that IS the pill, its satellites, and every morph between them
 * (docs/superpowers/specs/2026-09-23-blob-rebuild-design.md section 1).
 *
 * `bodies` is up to 4 objects `{x, y, w, h, r}` in this item's own local
 * pixel space (bodies[0] = pill, [1] = left satellite, [2] = right
 * satellite, [3] = spare/unused). A body with w<=0 or h<=0 is treated as
 * absent by the shader. `neckK` is `[k1, k2]`, the smooth-min fusion
 * strength for bodies 1 and 2 into body 0.
 *
 * This item's own width/height should be set to the window's fixed
 * width/height (or the enclosing surface region) -- NOT resized per state;
 * only the `bodies` rects move. Callers still get to clip per-body content
 * against `bodies[i]` themselves (this item only draws the shape).
 */
Item {
    id: root

    property var bodies: [
        { x: 0, y: 0, w: 0, h: 0, r: 0 },
        { x: 0, y: 0, w: 0, h: 0, r: 0 },
        { x: 0, y: 0, w: 0, h: 0, r: 0 },
        { x: 0, y: 0, w: 0, h: 0, r: 0 }
    ]
    property var neckK: [0, 0]
    property color fillColor: Theme.surfaceContainer
    property real rim: 0.5
    property real rimWidth: 8
    property real outline: 0.45
    property real outlineWidth: 1.4
    property real shadow: 0.13
    // Ink: even 1px white ring just outside the edge (alpha), unlit.
    property real ring: 0

    function _rect(b) {
        return Qt.vector4d(b ? b.x : 0, b ? b.y : 0, b ? b.w : 0, b ? b.h : 0)
    }

    ShaderEffect {
        id: effect
        anchors.fill: parent

        readonly property vector4d rect0: root._rect(root.bodies[0])
        readonly property vector4d rect1: root._rect(root.bodies[1])
        readonly property vector4d rect2: root._rect(root.bodies[2])
        readonly property vector4d rect3: root._rect(root.bodies[3])
        readonly property vector4d radius: Qt.vector4d(
            root.bodies[0] ? root.bodies[0].r : 0,
            root.bodies[1] ? root.bodies[1].r : 0,
            root.bodies[2] ? root.bodies[2].r : 0,
            root.bodies[3] ? root.bodies[3].r : 0)
        readonly property size neckK: Qt.size(
            root.neckK && root.neckK.length > 0 ? root.neckK[0] : 0,
            root.neckK && root.neckK.length > 1 ? root.neckK[1] : 0)
        readonly property size resolution: Qt.size(root.width, root.height)
        readonly property color fillColor: root.fillColor
        readonly property real rim: root.rim
        readonly property real rimWidth: root.rimWidth
        readonly property real outline: root.outline
        readonly property real outlineWidth: root.outlineWidth
        readonly property real shadow: root.shadow
        readonly property real ring: root.ring

        fragmentShader: "../shaders/blob.frag.qsb"
    }
}
