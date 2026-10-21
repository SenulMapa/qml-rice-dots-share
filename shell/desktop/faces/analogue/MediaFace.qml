// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   M   E   D   I   A       F   A   C   E                                  │
// │   what is playing as a record · it turns while it plays                  │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../services" as DeskServices
import "../../components"

// TODO: components not yet ported

// A record on a turntable, with the title under it on a 2×2 and beside it on a
// 4×2, and the transport and progress under the text. At 4×4 the transport
// moves into the body and the album gets a line.
Instrument {
    id: face

    readonly property bool something: DeskServices.DeskMediaService.available

    line: DeskServices.DeskMediaService.title !== "" ? DeskServices.DeskMediaService.title
        : (face.something ? DeskServices.DeskMediaService.identity : "Nothing playing")
    reading: DeskServices.DeskMediaService.title !== "" ? DeskServices.DeskMediaService.title
        : (face.something ? DeskServices.DeskMediaService.identity : "Nothing playing")
    note: face.something
        ? `${DeskServices.DeskMediaService.artist !== "" ? DeskServices.DeskMediaService.artist + " · " : ""}${DeskServices.DeskMediaService.playing ? "playing" : "paused"}`
        : "no player on the bus"
    filled: true

    Record {
        anchors.centerIn: parent
        ink: face.ink
        size: Math.min(parent.width, parent.height)
        playing: DeskServices.DeskMediaService.playing
        art: DeskServices.DeskMediaService.artUrl
    }

    extra: [
        Column {
            visible: !face.large
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 8

            UsageBar {
                width: parent.width
                progress: DeskServices.DeskMediaService.progress
                fillColor: face.ink.accent
                trackColor: face.ink.raised
            }

            Row {
                spacing: 16

                IconButton {
                    iconColor: face.ink.text
                    icon: "󰒮"
                    iconSize: 16
                    onClicked: DeskServices.DeskMediaService.previous()
                }

                IconButton {
                    iconColor: face.ink.text
                    icon: DeskServices.DeskMediaService.playing ? "󰏤" : "󰐊"
                    iconSize: 18
                    onClicked: DeskServices.DeskMediaService.toggle()
                }

                IconButton {
                    iconColor: face.ink.text
                    icon: "󰒭"
                    iconSize: 16
                    onClicked: DeskServices.DeskMediaService.next()
                }
            }
        }
    ]

    body: [
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14

            Text {
                width: parent.width
                text: DeskServices.DeskMediaService.album !== "" ? DeskServices.DeskMediaService.album : DeskServices.DeskMediaService.identity
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeRegular
                color: face.ink.muted
            }

            UsageBar {
                width: parent.width
                progress: DeskServices.DeskMediaService.progress
                fillColor: face.ink.accent
                trackColor: face.ink.raised
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 28

                IconButton {
                    iconColor: face.ink.text
                    icon: "󰒮"
                    iconSize: 22
                    onClicked: DeskServices.DeskMediaService.previous()
                }

                IconButton {
                    iconColor: face.ink.text
                    icon: DeskServices.DeskMediaService.playing ? "󰏤" : "󰐊"
                    iconSize: 26
                    onClicked: DeskServices.DeskMediaService.toggle()
                }

                IconButton {
                    iconColor: face.ink.text
                    icon: "󰒭"
                    iconSize: 22
                    onClicked: DeskServices.DeskMediaService.next()
                }
            }
        }
    ]
}
