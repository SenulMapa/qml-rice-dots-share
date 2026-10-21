// Adapted from impasto's bar/island/controls/NotificationList.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet), swapped to
// use the shell's OWN notification stack rather than re-porting a second
// one: impasto's NotificationList/NotificationService is out of scope per
// the brief ("do not port impasto's ... notifications daemon"), and the
// shell already has a real one (services/NotificationService.qml +
// panels/NotificationCard.qml, shared with panels/NotificationCenter.qml).
// This card is a thin wrapper: the latest few real notifications, in the
// same card chrome as every other dashboard block.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../desktop/services" as Desk
import "../../services" as Shell
import "../../panels" as Panels
import "../components" as DashComponents

DashComponents.Card {
    id: root
    padding: 10
    property int cols: 2
    property int rows: 4

    readonly property var latest: Shell.NotificationService.history.slice(0, 3)

    Text {
        anchors.centerIn: parent
        visible: root.latest.length === 0
        text: "No notifications"
        font.family: Desk.DeskTheme.fontFamily
        font.pixelSize: Desk.DeskTheme.fontSizeSmall
        color: Desk.DeskTheme.textMuted
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.latest.length > 0
        spacing: 6

        Repeater {
            model: root.latest

            Panels.NotificationCard {
                required property var modelData
                Layout.fillWidth: true
                entry: modelData
            }
        }
    }
}
