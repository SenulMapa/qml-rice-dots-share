// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   P I L L   B U T T O N                                                  │
// │   capsule action · fills with the accent when active                     │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Layouts
import "../services" as DeskServices


// Capsule action button. `active` fills it with the accent, which is how the
// Quick Controls show a radio or profile that is currently on.
Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property bool active: false
    property bool enabled: true
    property int horizontalPadding: 10

    signal clicked()

    readonly property bool filled: root.active
    readonly property color foreground: root.filled ? DeskServices.DeskTheme.accentText : DeskServices.DeskTheme.text

    implicitHeight: 28
    implicitWidth: layout.implicitWidth + root.horizontalPadding * 2
    radius: DeskServices.DeskTheme.radiusPill
    opacity: root.enabled ? 1 : 0.4

    color: root.filled
        ? (mouse.containsMouse ? DeskServices.DeskTheme.accentHover : DeskServices.DeskTheme.accent)
        : (mouse.containsMouse ? DeskServices.DeskTheme.islandSurfaceHover : DeskServices.DeskTheme.islandSurface)
    border.color: root.filled ? DeskServices.DeskTheme.accent
        : (mouse.containsMouse ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.islandBorder)
    border.width: 1

    Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }
    Behavior on border.color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }
    Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }

    RowLayout {
        id: layout
        anchors.centerIn: parent
        spacing: 6

        Text {
            visible: root.icon !== ""
            text: root.icon
            font.family: DeskServices.DeskTheme.fontMono
            font.pixelSize: 12
            color: root.filled ? DeskServices.DeskTheme.accentText : DeskServices.DeskTheme.accent
        }

        Text {
            visible: root.text !== ""
            text: root.text
            font.family: DeskServices.DeskTheme.fontFamily
            font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
            font.weight: root.filled ? Font.DemiBold : Font.Normal
            color: root.foreground
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
