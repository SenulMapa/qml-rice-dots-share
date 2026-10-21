// Simplified port of impasto's bar/island/PackagesPanel.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// The full update list, real data throughout via
// desktop/services/DeskUpdatesService.qml (already shipped by the desktop
// port -- checkupdates/pacman/AUR via scripts/desktop/updates.py).

import QtQuick
import QtQuick.Layouts
import "../desktop/services" as Desk
import "components" as DashComponents

ColumnLayout {
    id: root

    signal closed()

    spacing: 10

    Component.onCompleted: Desk.DeskUpdatesService.subscribe()
    Component.onDestruction: Desk.DeskUpdatesService.release()

    RowLayout {
        Layout.fillWidth: true

        Text {
            Layout.fillWidth: true
            text: Desk.DeskUpdatesService.count + " update" + (Desk.DeskUpdatesService.count === 1 ? "" : "s")
                + (Desk.DeskUpdatesService.aur ? " · AUR" : "")
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: Desk.DeskTheme.fontSizeSmall
            font.weight: Font.DemiBold
            color: Desk.DeskTheme.text
        }

        DashComponents.QuickTile {
            Layout.preferredWidth: 90
            Layout.preferredHeight: 36
            label: Desk.DeskUpdatesService.checking ? "Checking…" : "Refresh"
            onToggled: Desk.DeskUpdatesService.refresh()
        }
    }

    DashComponents.Card {
        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: 6

        Text {
            anchors.centerIn: parent
            visible: Desk.DeskUpdatesService.packages.length === 0
            text: Desk.DeskUpdatesService.available ? "System is up to date" : "Update check unavailable"
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: Desk.DeskTheme.fontSizeSmall
            color: Desk.DeskTheme.textMuted
        }

        ListView {
            anchors.fill: parent
            visible: Desk.DeskUpdatesService.packages.length > 0
            clip: true
            spacing: 2
            model: Desk.DeskUpdatesService.packages

            delegate: RowLayout {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: modelData.name ?? modelData
                    elide: Text.ElideRight
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.text
                }

                Text {
                    visible: !!modelData.version
                    text: modelData.version ?? ""
                    font.family: Desk.DeskTheme.fontMono
                    font.pixelSize: Desk.DeskTheme.fontSizeLabel
                    color: Desk.DeskTheme.textMuted
                }
            }
        }
    }
}
