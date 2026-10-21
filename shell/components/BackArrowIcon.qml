import QtQuick
import "../core"
import "../services"

/**
 * BackArrowIcon - a drawn "<-" glyph for round back buttons.
 *
 * The control-centre and satellite back buttons used to show the Unicode
 * character "‹" (U+2039), which reads as a thin, faint tick rather than an
 * arrow at icon sizes -- nothing like shots12's "←". Rendering it as three
 * plain Rectangles (arrowhead + stem) instead of a font glyph also sidesteps
 * the same font-coverage trap that broke the satellite scan icon (see
 * ControlDetailPanel.qml): no PUA codepoint to go missing from whichever
 * font ends up resolving it.
 */
Item {
    id: root

    property color color: AdaptiveColor.glassText
    property real thickness: Math.max(1.4, size * 0.15)
    property real size: Theme.u(0.36)

    implicitWidth: size
    implicitHeight: size

    readonly property real armLength: size * 0.5
    readonly property real vertexX: size * 0.16
    readonly property real centerY: size / 2

    Rectangle {
        width: root.armLength
        height: root.thickness
        radius: height / 2
        color: root.color
        x: root.vertexX
        y: root.centerY - height / 2
        transformOrigin: Item.Left
        rotation: -45
    }
    Rectangle {
        width: root.armLength
        height: root.thickness
        radius: height / 2
        color: root.color
        x: root.vertexX
        y: root.centerY - height / 2
        transformOrigin: Item.Left
        rotation: 45
    }
    Rectangle {
        x: root.vertexX
        y: root.centerY - height / 2
        width: root.size - root.vertexX
        height: root.thickness
        radius: height / 2
        color: root.color
    }
}
