import QtQuick
import QtQuick.Shapes
import "../core"
import "../services"

/**
 * PlayIcon - a drawn play triangle for video/GIF badges.
 *
 * Uses Shape to draw a filled triangle, avoiding font glyphs that may not be
 * available or render as tofu. All geometry via Theme.u(k).
 */
Item {
    id: root

    property color color: AdaptiveColor.glassTextDim
    property real size: Theme.u(0.2)

    implicitWidth: size
    implicitHeight: size

    Shape {
        anchors.centerIn: parent
        width: root.size
        height: root.size

        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"

            // Triangle pointing right: vertices at (0, 0), (size, size/2), (0, size)
            startX: 0
            startY: 0
            PathLine { x: root.size; y: root.size / 2 }
            PathLine { x: 0; y: root.size }
            PathLine { x: 0; y: 0 }
        }
    }
}
