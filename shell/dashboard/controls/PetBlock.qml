// Simplified port of impasto's bar/island/controls/PetBlock.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// The pet's face, mood and the feed/play buttons. Tapping the face opens
// the pet panel. Real state throughout: desktop/components/PetFace.qml and
// desktop/services/DeskPetService.qml (already shipped by the desktop
// port) own the record/mood/cooldowns -- nothing here is re-derived.

import QtQuick
import QtQuick.Layouts
import "../../desktop/services" as Desk
import "../../desktop/components" as DeskComponents
import "../components" as DashComponents

DashComponents.Card {
    id: root
    padding: 12
    property int rows: 2

    signal panelRequested(string panel)

    Component.onCompleted: Desk.DeskPetService.subscribe()
    Component.onDestruction: Desk.DeskPetService.release()

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Item {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                Layout.alignment: Qt.AlignVCenter

                DeskComponents.PetFace {
                    id: face
                    anchors.centerIn: parent
                    size: 46
                    lively: true
                    scale: faceMouse.containsMouse ? 1.08 : 1

                    Behavior on scale {
                        NumberAnimation { duration: Desk.DeskTheme.durationFast; easing.type: Desk.DeskTheme.easing }
                    }
                }

                MouseArea {
                    id: faceMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.panelRequested("pet")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: Desk.DeskPetService.name || "No pet yet"
                    elide: Text.ElideRight
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeRegular
                    font.weight: Font.DemiBold
                    color: Desk.DeskTheme.text
                }

                Text {
                    Layout.fillWidth: true
                    text: Desk.DeskPetService.pet ? `Level ${Desk.DeskPetService.level} · ${Desk.DeskPetService.moodLine}` : "Adopt one from the pet panel"
                    elide: Text.ElideRight
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.textMuted
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: Desk.DeskPetService.pet !== null

            DeskComponents.PillButton {
                text: "Feed"
                icon: "󰉛"
                enabled: Desk.DeskPetService.canFeed
                onClicked: Desk.DeskPetService.feed()
            }

            DeskComponents.PillButton {
                text: "Play"
                icon: "󱠡"
                enabled: Desk.DeskPetService.canPlay
                onClicked: Desk.DeskPetService.play()
            }
        }
    }
}
