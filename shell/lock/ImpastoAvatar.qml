pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import "../desktop/services" as Desk

// ported from impasto components/Avatar.qml, verbatim except: Theme ->
// Desk.DeskTheme (Theme.hairline/islandSurface/text -> DeskTheme's own
// equivalents, see desktop/services/DeskTheme.qml).
//
// A round picture, or initials when there is none (the common case: most
// machines have no `~/.face`).
Item {
    id: root

    property string source: ""
    property string initials: "?"
    property color ring: Desk.DeskTheme.hairline

    implicitWidth: 86
    implicitHeight: 86

    ClippingRectangle {
        anchors.fill: parent
        radius: width / 2
        color: Desk.DeskTheme.islandSurface
        border.color: root.ring
        border.width: 2
        contentUnderBorder: true

        Image {
            id: picture

            anchors.fill: parent
            source: root.source !== "" ? `file://${root.source}` : ""
            visible: root.source !== "" && picture.status === Image.Ready
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: Math.round(root.width * 2)
            sourceSize.height: Math.round(root.height * 2)
        }

        Text {
            anchors.centerIn: parent
            visible: !picture.visible
            text: root.initials
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: Math.round(root.height * 0.36)
            font.weight: Font.Light
            color: Desk.DeskTheme.text
        }
    }
}
