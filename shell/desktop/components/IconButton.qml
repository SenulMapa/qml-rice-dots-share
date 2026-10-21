// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   I C O N   B U T T O N                                                  │
// │   square icon action                                                     │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import "../services" as DeskServices
import "../../components"


// Square icon button, transparent until hovered.
Squircle {
    id: root

    property string icon: ""
    property int iconSize: 13
    property color iconColor: DeskServices.DeskTheme.text
    property bool active: false

    signal clicked()

    implicitWidth: 32
    implicitHeight: 28
    radius: DeskServices.DeskTheme.radiusSmall

    color: root.active ? DeskServices.DeskTheme.accent
        : (mouse.containsMouse ? DeskServices.DeskTheme.islandSurfaceHover : "transparent")
    borderColor: root.active ? DeskServices.DeskTheme.accent
        : (mouse.containsMouse ? DeskServices.DeskTheme.islandBorder : "transparent")
    borderWidth: 1

    Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }
    Behavior on borderColor { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }

    Text {
        anchors.centerIn: parent
        text: root.icon
        font.family: DeskServices.DeskTheme.fontMono
        font.pixelSize: root.iconSize
        color: root.active ? DeskServices.DeskTheme.accentText
            : (mouse.containsMouse ? DeskServices.DeskTheme.accent : root.iconColor)

        Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
