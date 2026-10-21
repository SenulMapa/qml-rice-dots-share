import QtQuick
import "../core"
import "../services"

/**
 * GlassPillButton -- a capsule glass button with an optional Material
 * Symbols glyph and a label (glass redesign Phase 4): the shared shape for
 * every text action on a glass page (Back, Feed, Play, Save...), replacing
 * the old tinted-rectangle buttons. `prominent` makes it the page's one
 * activeFill action.
 */
Item {
    id: root

    property string icon: ""
    property string text: ""
    property bool prominent: false
    property bool available: true
    signal clicked()

    implicitHeight: 40
    implicitWidth: row.implicitWidth + 36
    opacity: available ? 1 : 0.4

    Item {
        anchors.fill: parent
        scale: area.pressed ? 0.96 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        GlassMaterial {
            anchors.fill: parent
            radius: height / 2
            active: root.prominent
            shadow: 0.07
            shadowSpread: 10
            rimWidth: 5
            tintAlpha: area.containsMouse ? 0.32 : 0.22
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.icon.length > 0
                text: root.icon
                font.family: "Material Symbols Rounded"
                font.pixelSize: 20
                font.variableAxes: ({ "FILL": 1 })
                color: Config.appearance.ink
                    ? (root.prominent ? Theme.glyphOn : Theme.t1)
                    : (root.prominent ? AdaptiveColor.activeFillText : AdaptiveColor.glassText)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.text.length > 0
                text: root.text
                font.family: Theme.fontUi
                font.pixelSize: 14
                font.weight: Font.Medium
                color: Config.appearance.ink
                    ? (root.prominent ? Theme.glyphOn : Theme.t1)
                    : (root.prominent ? AdaptiveColor.activeFillText : AdaptiveColor.glassText)
            }
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
