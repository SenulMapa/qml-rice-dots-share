// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import QtQuick.Layouts
import "../core"

/**
 * CalendarWidget -- month grid with prev/next navigation, ported from
 * end4-ii's sidebarRight/calendar/CalendarWidget.qml. Re-derives the month
 * grid with plain Date math instead of porting its calendar_layout.js +
 * CalendarDayButton/CalendarHeaderButton component chain -- those existed
 * to serve ii's Material ripple/hover chrome, which this port's flat/
 * no-card style drops anyway. Scroll-to-change-month and PageUp/PageDown
 * are also dropped (no keyboard focus model for desktop widgets in this
 * shell); the two chevrons ii already exposed cover the same need with a
 * click.
 */
Item {
    id: root

    property int monthShift: 0
    readonly property date viewingDate: {
        const d = new Date()
        d.setDate(1)
        d.setMonth(d.getMonth() + root.monthShift)
        return d
    }
    readonly property date today: new Date()

    // Flat 42-cell (6 week x 7 day) list of {day, inMonth, isToday}, built
    // with plain Date arithmetic. Row-major order (index = week*7 + day)
    // matches GridLayout's columns:7 auto-wrap exactly, so this feeds
    // straight into a Repeater below with no reshaping needed.
    readonly property var days: root.buildDays(root.viewingDate)

    function buildDays(viewing: date): var {
        const year = viewing.getFullYear()
        const month = viewing.getMonth()
        const firstOfMonth = new Date(year, month, 1)
        // Qt's getDay(): 0=Sunday .. 6=Saturday. Grid starts Monday, so
        // shift Sunday to the end of the week.
        const firstWeekday = (firstOfMonth.getDay() + 6) % 7
        const gridStart = new Date(year, month, 1 - firstWeekday)

        const cells = []
        for (let i = 0; i < 42; i++) {
            const cellDate = new Date(gridStart)
            cellDate.setDate(gridStart.getDate() + i)
            cells.push({
                day: cellDate.getDate(),
                inMonth: cellDate.getMonth() === month,
                isToday: cellDate.toDateString() === root.today.toDateString()
            })
        }
        return cells
    }

    readonly property var weekdayLabels: ["M", "T", "W", "T", "F", "S", "S"]

    // Fixed-cell grid: 7 EQUAL columns computed once from the available
    // width, shared by the weekday header row and every day cell below it
    // (same GridLayout, see grid below) -- previously the header row and
    // each week's row were separate RowLayouts, each sizing its own
    // columns from ITS OWN children's implicit widths ("31"/"1" vs
    // "10"/"11" vs single-letter headers), so columns drifted out of
    // alignment row to row instead of forming a real grid. Row height is
    // cell width * 0.8 per spec, rather than however much vertical space
    // ColumnLayout happened to hand the day grid.
    readonly property real gridWidth: root.width - Theme.space3 * 2
    readonly property real cellWidth: root.gridWidth / 7
    readonly property real cellHeight: root.cellWidth * 0.8

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space3
        spacing: Theme.space2

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: Qt.formatDate(root.viewingDate, "MMMM yyyy")
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textBody
                font.weight: Font.DemiBold
                color: Theme.surfaceText
                elide: Text.ElideRight
            }
            Text {
                text: "‹"
                font.pixelSize: Theme.textTitle
                color: Theme.surfaceVariantText
                MouseArea { anchors.fill: parent; anchors.margins: -Theme.space2
                    onClicked: root.monthShift-- }
            }
            Text {
                text: "›"
                font.pixelSize: Theme.textTitle
                color: Theme.surfaceVariantText
                MouseArea { anchors.fill: parent; anchors.margins: -Theme.space2
                    onClicked: root.monthShift++ }
            }
        }

        GridLayout {
            id: grid
            Layout.fillWidth: true
            columns: 7
            rowSpacing: 0
            columnSpacing: 0

            Repeater {
                model: root.weekdayLabels
                Text {
                    Layout.preferredWidth: root.cellWidth
                    Layout.preferredHeight: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.textSmall
                    color: Theme.surfaceVariantText
                }
            }

            Repeater {
                model: root.days
                Item {
                    required property var modelData
                    Layout.preferredWidth: root.cellWidth
                    Layout.preferredHeight: root.cellHeight
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.day
                        opacity: parent.modelData.inMonth ? 1 : 0.35
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Theme.textSmall
                        font.weight: parent.modelData.isToday ? Font.Bold : Font.Normal
                        color: parent.modelData.isToday
                            ? Theme.primary : Theme.surfaceText
                    }
                }
            }
        }
    }
}
