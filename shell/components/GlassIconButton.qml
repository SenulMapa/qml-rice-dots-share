import QtQuick
import "../core"
import "../services"

/**
 * GlassIconButton -- a round glass button with a Material Symbols glyph
 * (transport controls, power). `prominent` makes it an activeFill disc for
 * the one primary action in a group (play/pause).
 */
Item {
    id: root

    property string icon: ""
    property real size: 40
    property bool prominent: false
    property bool available: true
    signal clicked()

    implicitWidth: size
    implicitHeight: size
    opacity: available ? 1 : 0.4

    Item {
        anchors.fill: parent
        scale: area.pressed ? 0.9 : (area.containsMouse ? 1.05 : 1)
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        GlassMaterial {
            anchors.fill: parent
            radius: width / 2
            active: root.prominent
            shadow: 0.07
            shadowSpread: 10
            rimWidth: 5
            tintAlpha: area.containsMouse ? 0.32 : 0.22
        }

        Text {
            anchors.centerIn: parent
            text: root.icon
            font.family: "Material Symbols Rounded"
            font.pixelSize: Math.round(root.size * 0.52)
            font.variableAxes: ({ "FILL": 1 })
            color: Config.appearance.ink
                ? (root.prominent ? Theme.glyphOn : Theme.t1)
                : (root.prominent ? AdaptiveColor.activeFillText : AdaptiveColor.glassText)
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.available
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
