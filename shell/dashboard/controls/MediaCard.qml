// Ported from impasto's bar/island/controls/MediaCard.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// The player, with room for artwork and transport.
//
// Adaptation: Theme -> DeskTheme; MediaService -> DeskMediaService (the
// desktop port's MPRIS adapter, extended above with position/length/
// seekable/canPrevious/canNext for this card).

import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../../desktop/services" as Desk
import "../../desktop/components" as DeskComponents
import "../components" as DashComponents

DashComponents.Card {
    id: root
    property int cols: 2
    property int rows: 2

    Component.onCompleted: Desk.DeskMediaService.subscribe()
    Component.onDestruction: Desk.DeskMediaService.release()

    Text {
        anchors.centerIn: parent
        visible: !Desk.DeskMediaService.available
        text: "Nothing playing"
        font.family: Desk.DeskTheme.fontFamily
        font.pixelSize: Desk.DeskTheme.fontSizeSmall
        color: Desk.DeskTheme.textMuted
    }

    ColumnLayout {
        anchors.fill: parent
        visible: Desk.DeskMediaService.available
        spacing: 11

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ClippingRectangle {
                Layout.preferredWidth: 58
                Layout.preferredHeight: 58
                radius: width * Desk.DeskTheme.pictureCorner
                color: Desk.DeskTheme.islandSurfaceHover

                Image {
                    id: art
                    anchors.fill: parent
                    source: Desk.DeskMediaService.artUrl
                    visible: source !== "" && status === Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 116
                    sourceSize.height: 116
                }

                Text {
                    anchors.centerIn: parent
                    visible: !art.visible
                    text: "󰎇"
                    font.family: Desk.DeskTheme.fontMono
                    font.pixelSize: 22
                    color: Desk.DeskTheme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: Desk.DeskMediaService.title
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeRegular
                    font.weight: Font.DemiBold
                    color: Desk.DeskTheme.text
                }

                Text {
                    Layout.fillWidth: true
                    text: Desk.DeskMediaService.artist
                    elide: Text.ElideRight
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.textMuted
                }
            }
        }

        Item { Layout.fillHeight: true }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 3
            visible: Desk.DeskMediaService.seekable
            radius: 1.5
            color: Desk.DeskTheme.islandSurfaceHover

            Rectangle {
                width: parent.width * Desk.DeskMediaService.progress
                height: parent.height
                radius: parent.radius
                color: Desk.DeskTheme.accent

                Behavior on width {
                    NumberAnimation { duration: 900; easing.type: Easing.Linear }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: root.clock(Desk.DeskMediaService.position)
                visible: Desk.DeskMediaService.seekable
                font.family: Desk.DeskTheme.fontMono
                font.pixelSize: Desk.DeskTheme.fontSizeLabel
                color: Desk.DeskTheme.textMuted
            }

            Item { Layout.fillWidth: true }

            DeskComponents.IconButton {
                icon: "󰒮"
                iconSize: 15
                enabled: Desk.DeskMediaService.canPrevious
                opacity: Desk.DeskMediaService.canPrevious ? 1 : 0.35
                onClicked: Desk.DeskMediaService.previous()
            }

            DeskComponents.IconButton {
                icon: Desk.DeskMediaService.playing ? "󰏤" : "󰐊"
                iconSize: 18
                onClicked: Desk.DeskMediaService.toggle()
            }

            DeskComponents.IconButton {
                icon: "󰒭"
                iconSize: 15
                enabled: Desk.DeskMediaService.canNext
                opacity: Desk.DeskMediaService.canNext ? 1 : 0.35
                onClicked: Desk.DeskMediaService.next()
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.clock(Desk.DeskMediaService.length)
                visible: Desk.DeskMediaService.seekable
                font.family: Desk.DeskTheme.fontMono
                font.pixelSize: Desk.DeskTheme.fontSizeLabel
                color: Desk.DeskTheme.textMuted
            }
        }
    }

    function clock(seconds: real): string {
        const total = Math.max(0, Math.floor(seconds))
        const minutes = Math.floor(total / 60)
        const remainder = total % 60
        return `${minutes}:${remainder < 10 ? "0" : ""}${remainder}`
    }
}
