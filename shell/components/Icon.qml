pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "../core"

/**
 * Icon -- one icon language for the ink shell.
 *
 * `name` is either a Lucide stroke icon ("wifi") from assets/icons/lucide, or
 * a filled transport glyph ("transport/play") from assets/icons/transport.
 * Both sources are pre-whitened (currentColor is #ffffff), so MultiEffect
 * colorization paints them in `color` with the same weight everywhere.
 */
Item {
    id: root

    property string name: ""
    property real size: 18
    property color color: Theme.t1

    readonly property string resolved: name.length === 0 ? ""
        : (name.indexOf("transport/") === 0
            ? "../assets/icons/" + name + ".svg"
            : "../assets/icons/lucide/" + name + ".svg")

    implicitWidth: size
    implicitHeight: size

    Image {
        id: glyph
        anchors.fill: parent
        source: root.resolved
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        smooth: true
        mipmap: true
        // MultiEffect colorization ignores the colour's alpha (a t3 icon came
        // out full white), so the alpha is applied as opacity instead.
        opacity: root.color.a
        // Same layer.effect pattern as LyricWheel: the MultiEffect tints the
        // item's own rendered layer, so no hidden source item is needed.
        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 1)
            brightness: 1.0
        }
    }
}
