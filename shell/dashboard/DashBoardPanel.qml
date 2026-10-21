// Simplified port of impasto's bar/island/BoardPanel.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// A kanban board of real tasks (desktop/services/DeskTasksService.qml,
// already shipped by the desktop port), one column per state (to do /
// doing / done). Upstream's drag-between-columns reordering was not
// ported; a task advances one state on tap instead (setState via
// DeskTasksService.stateAfter), and a new task can still be added per
// column -- the data model and its persistence (tasks.json) are entirely
// real and shared with DashControls.TasksBlock/CalendarCard.

import QtQuick
import QtQuick.Layouts
import "../desktop/services" as Desk
import "components" as DashComponents
import "../components"

ColumnLayout {
    id: root

    signal closed()

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 10

        Repeater {
            model: Desk.DeskTasksService.states

            DashComponents.Card {
                id: column
                required property var modelData

                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: 8

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: column.modelData.icon + "  " + column.modelData.label
                            font.family: Desk.DeskTheme.fontFamily
                            font.pixelSize: Desk.DeskTheme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Desk.DeskTheme.text
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: Desk.DeskTasksService.countIn(column.modelData.id)
                            font.family: Desk.DeskTheme.fontMono
                            font.pixelSize: Desk.DeskTheme.fontSizeLabel
                            color: Desk.DeskTheme.textMuted
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: Desk.DeskTasksService.inState(column.modelData.id)

                        delegate: Squircle {
                            required property var modelData
                            width: ListView.view ? ListView.view.width : 0
                            height: label.implicitHeight + 12
                            radius: Desk.DeskTheme.radiusSmall
                            color: Desk.DeskTheme.islandSurfaceHover

                            Text {
                                id: label
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 8
                                text: modelData.text
                                wrapMode: Text.Wrap
                                font.family: Desk.DeskTheme.fontFamily
                                font.pixelSize: Desk.DeskTheme.fontSizeSmall
                                color: Desk.DeskTheme.text
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Desk.DeskTasksService.setState(
                                    modelData.key,
                                    Desk.DeskTasksService.stateAfter(modelData.state))
                            }
                        }
                    }

                    DashComponents.QuickTile {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        icon: "󰐕"
                        label: "New task"
                        detail: ""
                        onToggled: Desk.DeskTasksService.add("New task", "", column.modelData.id)
                    }
                }
            }
        }
    }
}
