// Ported from impasto's components/QuickTile.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// A toggle that states what it is doing ("Bluetooth · WH-1000XM4", not
// "On"). The on state shows on the icon badge; filling the whole tile would
// turn a panel of toggles into blocks of accent.
//
// Adaptation: Theme -> DeskTheme (desktop port's token forwarder over the
// shell's real adaptive Theme).

import QtQuick
import QtQuick.Layouts
import "../../desktop/services" as Desk
import "../../components"

Squircle {
    id: root

    property string icon: ""
    property string label: ""
    property string detail: ""
    property bool active: false
    property bool available: true
    property bool expandable: false

    signal toggled()
    signal expanded()

    radius: Desk.DeskTheme.radiusMedium
    opacity: root.available ? 1 : 0.45

    color: mouse.containsMouse ? Desk.DeskTheme.islandSurfaceHover : Desk.DeskTheme.islandSurface
    borderColor: root.active ? Desk.DeskTheme.accent : Desk.DeskTheme.islandBorder
    borderWidth: 1

    Behavior on color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }
    Behavior on borderColor { ColorAnimation { duration: Desk.DeskTheme.durationFast } }
    Behavior on opacity { NumberAnimation { duration: Desk.DeskTheme.durationFast } }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 11

        Rectangle {
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            Layout.alignment: Qt.AlignVCenter
            radius: width / 2
            color: root.active ? Desk.DeskTheme.accent : Desk.DeskTheme.islandSurfaceHover

            Behavior on color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }

            Text {
                anchors.centerIn: parent
                text: root.icon
                font.family: Desk.DeskTheme.fontMono
                font.pixelSize: 16
                color: root.active ? Desk.DeskTheme.accentText : Desk.DeskTheme.textMuted

                Behavior on color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1
            Layout.rightMargin: root.expandable ? 16 : 0

            Text {
                Layout.fillWidth: true
                text: root.label
                elide: Text.ElideRight
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Desk.DeskTheme.text
            }

            Text {
                Layout.fillWidth: true
                text: root.detail
                elide: Text.ElideRight
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeLabel
                color: root.active ? Desk.DeskTheme.accent : Desk.DeskTheme.textMuted

                Behavior on color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.available
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    Item {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 28
        visible: root.expandable

        Text {
            anchors.centerIn: parent
            text: "󰅂"
            font.family: Desk.DeskTheme.fontMono
            font.pixelSize: 13
            color: chevron.containsMouse ? Desk.DeskTheme.accent : Desk.DeskTheme.textMuted

            Behavior on color { ColorAnimation { duration: Desk.DeskTheme.durationFast } }
        }

        MouseArea {
            id: chevron
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.available
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded()
        }
    }
}
