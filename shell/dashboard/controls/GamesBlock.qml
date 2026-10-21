// Ported from impasto's bar/island/controls/GamesBlock.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// Arcade block. One row: the mark, the last best and Play. Two rows: the
// last three games. `Play` opens DashGamesPanel (the earlier dashboard-port
// phase's real score/best-run catalogue, not upstream's arcade UI -- see
// HANDOVER.md) via the same `panelRequested("games")` route the top row's
// door button already uses.
//
// Adaptation: Theme -> Desk.DeskTheme; GamesService -> Desk.DeskGamesService
// (already shipped by the desktop port, same entry()/tintOf()/bestOf()/
// lastPlayed/ranked shape).

import QtQuick
import QtQuick.Layouts

import "../../desktop/services" as Desk
import "../../desktop/components" as DeskComponents
import "../components" as DashComponents
import "../../components"

DashComponents.Card {
    id: root

    property int rows: 1

    signal panelRequested(string panel)

    readonly property string last: Desk.DeskGamesService.lastPlayed
    readonly property var lastEntry: Desk.DeskGamesService.entry(root.last)

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Squircle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 10
                color: Qt.rgba(Desk.DeskTheme.accent.r, Desk.DeskTheme.accent.g, Desk.DeskTheme.accent.b, 0.2)

                Text {
                    anchors.centerIn: parent
                    text: "󰊗"
                    font.family: Desk.DeskTheme.fontMono
                    font.pixelSize: 17
                    color: Desk.DeskTheme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    text: "Games"
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Desk.DeskTheme.text
                }

                Text {
                    Layout.fillWidth: true
                    text: root.lastEntry
                        ? `${root.lastEntry.name} · best ${Desk.DeskGamesService.bestOf(root.last)}`
                        : "Nothing played yet"
                    elide: Text.ElideRight
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeLabel
                    color: Desk.DeskTheme.textMuted
                }
            }

            DeskComponents.PillButton {
                text: "Play"
                implicitHeight: 26
                onClicked: root.panelRequested("games")
            }
        }

        Repeater {
            model: root.rows >= 2 ? Desk.DeskGamesService.ranked.slice(0, 3) : []

            RowLayout {
                id: row

                required property var modelData

                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.preferredWidth: 18
                    horizontalAlignment: Text.AlignHCenter
                    text: row.modelData.icon
                    font.family: Desk.DeskTheme.fontMono
                    font.pixelSize: 13
                    color: Desk.DeskGamesService.tintOf(row.modelData.id)
                }

                Text {
                    Layout.fillWidth: true
                    text: row.modelData.name
                    elide: Text.ElideRight
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.text
                }

                Text {
                    text: `${Desk.DeskGamesService.bestOf(row.modelData.id)}`
                    font.family: Desk.DeskTheme.fontMono
                    font.pixelSize: Desk.DeskTheme.fontSizeLabel
                    color: Desk.DeskTheme.textMuted
                }
            }
        }

        Item {
            Layout.fillHeight: true
            visible: root.rows >= 2
        }
    }
}
