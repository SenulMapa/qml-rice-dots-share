// Simplified port of impasto's bar/island/PetPanel.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// The pet family shelf: the active pet large, the rest of the hatched
// family as a row you can switch to, feed/play, and adopt a new egg once
// one is owed. Real state throughout via
// desktop/services/DeskPetService.qml (already shipped by the desktop
// port).

import QtQuick
import QtQuick.Layouts
import "../desktop/services" as Desk
import "../desktop/components" as DeskComponents
import "components" as DashComponents
import "../components"

ColumnLayout {
    id: root

    signal closed()

    spacing: 12

    Component.onCompleted: Desk.DeskPetService.subscribe()
    Component.onDestruction: Desk.DeskPetService.release()

    DashComponents.Card {
        Layout.fillWidth: true
        Layout.preferredHeight: 160
        padding: 14

        RowLayout {
            anchors.fill: parent
            spacing: 16

            DeskComponents.PetFace {
                Layout.preferredWidth: 100
                Layout.preferredHeight: 100
                size: 96
                lively: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: Desk.DeskPetService.name || "No pet yet"
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeLarge
                    font.weight: Font.DemiBold
                    color: Desk.DeskTheme.text
                }

                Text {
                    visible: Desk.DeskPetService.pet !== null
                    text: "Level " + Desk.DeskPetService.level + " · " + Desk.DeskPetService.moodLine
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.textMuted
                }

                DeskComponents.UsageBar {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: Desk.DeskPetService.pet !== null
                    progress: Desk.DeskPetService.progress
                }

                RowLayout {
                    spacing: 8
                    visible: Desk.DeskPetService.pet !== null

                    DashComponents.QuickTile {
                        Layout.preferredWidth: 90
                        Layout.preferredHeight: 40
                        label: "Feed"
                        icon: "󰉛"
                        available: Desk.DeskPetService.canFeed
                        onToggled: Desk.DeskPetService.feed()
                    }
                    DashComponents.QuickTile {
                        Layout.preferredWidth: 90
                        Layout.preferredHeight: 40
                        label: "Play"
                        icon: "󱠡"
                        available: Desk.DeskPetService.canPlay
                        onToggled: Desk.DeskPetService.play()
                    }
                }

                DashComponents.QuickTile {
                    Layout.preferredWidth: 140
                    Layout.preferredHeight: 40
                    visible: Desk.DeskPetService.pet === null
                    label: "Adopt an egg"
                    icon: "󰞌"
                    onToggled: Desk.DeskPetService.adopt()
                }
            }
        }
    }

    Text {
        visible: Desk.DeskPetService.family.length > 1
        text: "Family"
        font.family: Desk.DeskTheme.fontFamily
        font.pixelSize: Desk.DeskTheme.fontSizeLabel
        color: Desk.DeskTheme.textMuted
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: Desk.DeskPetService.family.length > 1

        Repeater {
            model: Desk.DeskPetService.family

            Squircle {
                required property var modelData
                required property int index

                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
                radius: Desk.DeskTheme.radiusMedium
                color: index === Desk.DeskPetService.activeIndex
                    ? Desk.DeskTheme.accent : Desk.DeskTheme.islandSurface
                borderColor: Desk.DeskTheme.islandBorder
                borderWidth: 1

                DeskComponents.PetFace {
                    anchors.centerIn: parent
                    size: 40
                    record: modelData
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Desk.DeskPetService.bringOut(index)
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
