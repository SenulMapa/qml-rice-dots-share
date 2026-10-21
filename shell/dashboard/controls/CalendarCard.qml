// Simplified port of impasto's bar/island/controls/CalendarCard.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// A month grid with a dot under any day that has a task due
// (DeskTasksService.countOn/pendingOn), today highlighted, tap-to-select a
// day to see its tasks below. Upstream's own DayPicker component and its
// swipe-between-months gesture were not ported (time-boxed scope
// reduction, documented in HANDOVER.md); month navigation here is two plain
// arrow buttons instead.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../desktop/services" as Desk
import "../../desktop/components" as DeskComponents
import "../components" as DashComponents

DashComponents.Card {
    id: root
    padding: 12

    signal panelRequested(string panel)

    property date shownMonth: Desk.DeskTasksService.clock.date
    property string selectedDay: Desk.DeskTasksService.todayKey

    readonly property int daysInMonth: new Date(shownMonth.getFullYear(), shownMonth.getMonth() + 1, 0).getDate()
    readonly property int firstWeekday: new Date(shownMonth.getFullYear(), shownMonth.getMonth(), 1).getDay()

    function dayKeyAt(day: int): string {
        return Desk.DeskTasksService.dayKey(new Date(shownMonth.getFullYear(), shownMonth.getMonth(), day))
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: Qt.formatDate(root.shownMonth, "MMMM yyyy")
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Desk.DeskTheme.text
            }

            DeskComponents.IconButton {
                icon: "󰅁"
                iconSize: 12
                onClicked: {
                    const d = new Date(root.shownMonth)
                    d.setMonth(d.getMonth() - 1)
                    root.shownMonth = d
                }
            }
            DeskComponents.IconButton {
                icon: "󰅂"
                iconSize: 12
                onClicked: {
                    const d = new Date(root.shownMonth)
                    d.setMonth(d.getMonth() + 1)
                    root.shownMonth = d
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 7
            rowSpacing: 4
            columnSpacing: 2

            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]
                Text {
                    required property string modelData
                    Layout.preferredWidth: 22
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeLabel
                    color: Desk.DeskTheme.textMuted
                }
            }

            Repeater {
                model: root.firstWeekday
                Item { Layout.preferredWidth: 22; Layout.preferredHeight: 22 }
            }

            Repeater {
                model: root.daysInMonth

                Item {
                    id: cell
                    required property int index
                    readonly property int day: cell.index + 1
                    readonly property string key: root.dayKeyAt(cell.day)
                    readonly property bool today: cell.key === Desk.DeskTasksService.todayKey
                    readonly property bool selected: cell.key === root.selectedDay
                    readonly property int pending: Desk.DeskTasksService.pendingOn(cell.key)

                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: cell.selected ? Desk.DeskTheme.accent
                            : (cell.today ? Desk.DeskTheme.islandSurfaceHover : "transparent")

                        Text {
                            anchors.centerIn: parent
                            text: cell.day
                            font.family: Desk.DeskTheme.fontFamily
                            font.pixelSize: Desk.DeskTheme.fontSizeLabel
                            color: cell.selected ? Desk.DeskTheme.accentText : Desk.DeskTheme.text
                        }

                        Rectangle {
                            visible: cell.pending > 0 && !cell.selected
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 1
                            width: 4
                            height: 4
                            radius: 2
                            color: Desk.DeskTheme.accent
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedDay = cell.key
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: Desk.DeskTasksService.countOn(root.selectedDay) > 0
                ? Desk.DeskTasksService.on(root.selectedDay).map(t => t.text).join(" · ")
                : "No tasks due"
            elide: Text.ElideRight
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: Desk.DeskTheme.fontSizeLabel
            color: Desk.DeskTheme.textMuted
        }
    }
}
