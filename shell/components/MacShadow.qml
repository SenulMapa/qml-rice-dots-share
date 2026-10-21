import QtQuick

/**
 * MacShadow -- soft shadow from stacked translucent rounded rects.
 *
 * Deliberately not a MultiEffect: stacked rects render on every Qt scene
 * graph backend (the offscreen render harnesses use the software one, where
 * shader effects draw nothing) and cost nothing per frame. Put it behind the
 * shape it shadows with the same size; the glow extends outside the bounds
 * and never affects layout.
 */
Item {
    id: root

    property real radius: 10
    property real spread: 14        // how far the shadow reaches past the edge
    property real shadowOpacity: 0.4
    property real yOffset: 6
    property int steps: 6
    property color shadowColor: "black"

    Repeater {
        model: root.steps
        Squircle {
            required property int index
            readonly property real t: (index + 1) / root.steps
            readonly property real grow: root.spread * t - root.spread * 0.35
            x: -grow
            y: -grow + root.yOffset
            width: root.width + 2 * grow
            height: root.height + 2 * grow
            radius: Math.max(0, root.radius + grow)
            color: Qt.rgba(root.shadowColor.r, root.shadowColor.g, root.shadowColor.b,
                           root.shadowOpacity / root.steps * 1.6 * (1 - t * 0.55))
        }
    }
}
