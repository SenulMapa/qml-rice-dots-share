// Adapted from impasto's bar/island/controls/TasksBlock.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// The pending-task queue (overdue and due-soonest first, per
// DeskTasksService.queue), each with a tap-to-toggle checkbox. Simplified
// from upstream's own column layout to a plain scrolling list -- no fake
// data, every row is a real task from DeskTasksService's tasks.json.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../desktop/services" as Desk
import "../components" as DashComponents

DashComponents.Card {
    id: root
    padding: 10
    property int cols: 2
    property int rows: 3

    // Ported from upstream's own `panelRequested` (a row opens the board on
    // that task); this port's board is DashBoardPanel.qml, reached via
    // BlockFace/DashControlsPanel's existing "board" panel route.
    signal panelRequested(string panel)

    readonly property var queue: Desk.DeskTasksService.queue

    Text {
        anchors.centerIn: parent
        visible: root.queue.length === 0
        text: "No tasks"
        font.family: Desk.DeskTheme.fontFamily
        font.pixelSize: Desk.DeskTheme.fontSizeSmall
        color: Desk.DeskTheme.textMuted
    }

    ListView {
        anchors.fill: parent
        visible: root.queue.length > 0
        clip: true
        spacing: 4
        model: root.queue

        delegate: RowLayout {
            id: row
            required property var modelData
            width: ListView.view ? ListView.view.width : 0
            spacing: 8

            readonly property bool overdue: Desk.DeskTasksService.isOverdue(row.modelData)

            Rectangle {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 16
                radius: 4
                color: "transparent"
                border.color: row.overdue ? Desk.DeskTheme.red : Desk.DeskTheme.islandBorder
                border.width: 1.5

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Desk.DeskTasksService.toggle(row.modelData.key)
                }
            }

            Text {
                Layout.fillWidth: true
                text: row.modelData.text
                elide: Text.ElideRight
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeSmall
                color: Desk.DeskTheme.text

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: root.panelRequested("board")
                }
            }

            Text {
                visible: row.modelData.due !== ""
                text: Desk.DeskTasksService.dueLabel(row.modelData.due)
                font.family: Desk.DeskTheme.fontMono
                font.pixelSize: Desk.DeskTheme.fontSizeLabel
                color: row.overdue ? Desk.DeskTheme.red : Desk.DeskTheme.textMuted
            }
        }
    }
}
