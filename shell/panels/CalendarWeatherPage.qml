import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

// Island "calendar" page: the month grid and agenda beside the weather
// (showcase screens/calendar-weather.html, 720 wide). Both halves read the
// same services the standalone CalendarPage and WeatherPage use; nothing
// here starts a poller.
//
// Ink only. With Config.appearance.ink off the page hosts the two existing
// pages side by side, unchanged, so the old look stays reachable.
Item {
    id: root

    readonly property bool ink: Config.appearance.ink

    // Agenda rows for the selected day: [{ time: "09:30", title, calendar }].
    // No calendar provider is connected yet, same as CalendarPage.events.
    property var events: []

    property date displayedMonth: new Date(ShellState.now.getFullYear(),
        ShellState.now.getMonth(), 1)
    property date selectedDate: new Date(ShellState.now.getFullYear(),
        ShellState.now.getMonth(), ShellState.now.getDate())
    readonly property var monthCells: buildMonthCells()
    readonly property var weekdayLabels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    // Five days after today, the same window calendar-weather.html shows.
    readonly property var nextDays: WeatherService.forecast.slice(1, 6)
    readonly property real rangeLow: nextDays.length > 0
        ? Math.min(...nextDays.map(day => day.low)) : 0
    readonly property real rangeHigh: nextDays.length > 0
        ? Math.max(...nextDays.map(day => day.high)) : 1
    readonly property real rangeSpan: Math.max(1, rangeHigh - rangeLow)

    // Ink: the page's content height, including the 24px showcase padding
    // (split between this page and the host's own Theme.space4 margins).
    // island/IslandController.qml sizes the calendar body to this.
    readonly property real contentHeight: inkRow.implicitHeight
        + 2 * Math.max(0, 24 - Theme.space4)

    function sameDay(first, second): bool {
        return first.getFullYear() === second.getFullYear()
            && first.getMonth() === second.getMonth()
            && first.getDate() === second.getDate()
    }

    // Monday-first, six rows, like the showcase.
    function buildMonthCells(): var {
        const year = displayedMonth.getFullYear()
        const month = displayedMonth.getMonth()
        const lead = (new Date(year, month, 1).getDay() + 6) % 7
        const cells = []
        for (let index = 0; index < 42; index++) {
            const date = new Date(year, month, index - lead + 1)
            cells.push({
                date: date,
                day: date.getDate(),
                inMonth: date.getMonth() === month,
                today: sameDay(date, ShellState.now)
            })
        }
        return cells
    }

    function changeMonth(offset): void {
        displayedMonth = new Date(displayedMonth.getFullYear(),
            displayedMonth.getMonth() + offset, 1)
    }

    function selectDate(date): void {
        selectedDate = date
        if (date.getMonth() !== displayedMonth.getMonth()
                || date.getFullYear() !== displayedMonth.getFullYear())
            displayedMonth = new Date(date.getFullYear(), date.getMonth(), 1)
    }

    Loader {
        anchors.fill: parent
        active: !root.ink
        sourceComponent: RowLayout {
            anchors.fill: parent
            spacing: Theme.space3
            WeatherPage {
                Layout.preferredWidth: 300
                Layout.fillHeight: true
            }
            CalendarPage {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }

    // The island host already insets every page by Theme.space4, so the
    // showcase's 24px padding is only the remainder.
    RowLayout {
        id: inkRow
        anchors.fill: parent
        anchors.margins: Math.max(0, 24 - Theme.space4)
        spacing: 28
        visible: root.ink

        // ---- Calendar and agenda (376 wide) ----
        ColumnLayout {
            Layout.preferredWidth: 376
            Layout.fillHeight: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: Qt.formatDate(root.displayedMonth, "MMMM yyyy")
                    color: Theme.t1
                    font.family: Theme.fontUi
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.3
                    elide: Text.ElideRight
                }

                Row {
                    spacing: 4
                    Repeater {
                        model: [
                            { glyph: "chevron_left", step: -1 },
                            { glyph: "chevron_right", step: 1 }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 32
                            height: 32
                            radius: 16
                            color: navHover.hovered ? Theme.inkRaised : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: modelData.glyph
                                color: Theme.t2
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 20
                            }
                            HoverHandler { id: navHover }
                            TapHandler { onTapped: root.changeMonth(modelData.step) }
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: 12
                columns: 7
                rowSpacing: 2
                columnSpacing: 0

                Repeater {
                    model: root.weekdayLabels
                    delegate: Text {
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: modelData
                        color: Theme.t3
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                }

                Repeater {
                    model: root.monthCells
                    delegate: Item {
                        id: cell
                        required property var modelData
                        readonly property bool selected: root.sameDay(modelData.date, root.selectedDate)
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40

                        Rectangle {
                            id: disc
                            width: 32
                            height: 32
                            radius: 16
                            y: 4
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: cell.modelData.today ? Theme.fillOn
                                : cell.selected ? Theme.inkRaised : "transparent"
                        }
                        Text {
                            anchors.centerIn: disc
                            text: cell.modelData.day
                            color: cell.modelData.today ? Theme.glyphOn
                                : cell.modelData.inMonth ? Theme.t1 : Theme.t3
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: cell.modelData.today ? Font.DemiBold : Font.Medium
                        }
                        TapHandler { onTapped: root.selectDate(cell.modelData.date) }
                    }
                }
            }

            Text {
                Layout.topMargin: 20
                Layout.bottomMargin: 4
                Layout.preferredHeight: 16
                text: Qt.formatDate(root.selectedDate, "dddd d MMMM")
                color: Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                visible: root.events.length === 0
                verticalAlignment: Text.AlignVCenter
                leftPadding: 4
                text: "Nothing scheduled"
                color: Theme.t2
                font.family: Theme.fontUi
                font.pixelSize: 13
            }

            Repeater {
                model: root.events.slice(0, 3)
                delegate: Squircle {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    radius: 14
                    color: index === 0 ? Theme.inkRaised : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
                        spacing: 14

                        Text {
                            Layout.preferredWidth: 44
                            text: modelData.time
                            color: Theme.t2
                            font.family: Config.appearance.monoFontFamily
                            font.pixelSize: 12
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.title
                            color: Theme.t1
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: modelData.calendar
                            color: Theme.t3
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        // ---- Weather (268 wide) ----
        ColumnLayout {
            Layout.preferredWidth: 268
            Layout.fillHeight: true
            spacing: 0

            // No location configured: a calm empty state at the top of the
            // column, level with the calendar header.
            ColumnLayout {
                Layout.fillWidth: true
                visible: !WeatherService.configured
                spacing: 8

                Icon {
                    name: "cloud-off"
                    size: 28
                    color: Theme.t3
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Set a location in Settings → Weather"
                    color: Theme.t2
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                Layout.topMargin: 4
                visible: WeatherService.configured
                text: Config.weather.locationName
                color: Theme.t2
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: 13
            }
            Text {
                Layout.topMargin: 6
                Layout.preferredHeight: 92
                visible: WeatherService.available
                text: WeatherService.temperatureLabel
                color: Theme.t1
                lineHeight: 92
                lineHeightMode: Text.FixedHeight
                font.family: Theme.fontSerif
                font.pixelSize: 96
                font.letterSpacing: -2
            }
            RowLayout {
                Layout.topMargin: 6
                Layout.preferredHeight: 22
                spacing: 8
                visible: WeatherService.available

                Text {
                    text: WeatherService.icon
                    color: Theme.t1
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 18
                }
                Text {
                    Layout.fillWidth: true
                    text: WeatherService.condition
                    color: Theme.t1
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.preferredHeight: 17
                visible: WeatherService.available
                text: "High " + Math.round(WeatherService.highTemperature) + "° · Low "
                    + Math.round(WeatherService.lowTemperature) + "°"
                color: Theme.t2
                font.family: Theme.fontUi
                font.pixelSize: 13
            }
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                visible: WeatherService.configured && !WeatherService.available
                wrapMode: Text.WordWrap
                text: WeatherService.statusLabel
                color: Theme.t2
                font.family: Theme.fontUi
                font.pixelSize: 13
            }

            // Next hours: the same hourly list WeatherPage reads.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 18
                spacing: 0
                visible: WeatherService.available

                Repeater {
                    model: WeatherService.hourlyForecast.slice(0, 6)
                    delegate: ColumnLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.time
                            color: index === 0 ? Theme.t1 : Theme.t3
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            font.weight: index === 0 ? Font.DemiBold : Font.Medium
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredHeight: 18
                            text: modelData.icon
                            color: Theme.t1
                            font.family: Config.appearance.monoFontFamily
                            font.pixelSize: 18
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.temperature + "°"
                            color: Theme.t1
                            font.family: Theme.fontSerif
                            font.pixelSize: 22
                        }
                    }
                }
            }

            Text {
                Layout.topMargin: 18
                Layout.preferredHeight: 16
                visible: WeatherService.available
                text: "Next five days"
                color: Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Repeater {
                model: root.nextDays
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    spacing: 10
                    visible: WeatherService.available

                    Text {
                        Layout.preferredWidth: 50
                        text: modelData.day + " " + Number(modelData.date.slice(8, 10))
                        color: Theme.t1
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.preferredWidth: 18
                        text: modelData.icon
                        color: Theme.t1
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 18
                    }
                    Text {
                        Layout.preferredWidth: 34
                        horizontalAlignment: Text.AlignRight
                        text: modelData.low + "°"
                        color: Theme.t3
                        font.family: Theme.fontSerif
                        font.pixelSize: 18
                    }
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 4

                        Rectangle {
                            anchors.fill: parent
                            radius: 2
                            color: Theme.inkRaised
                        }
                        Rectangle {
                            readonly property real start: parent.width
                                * (modelData.low - root.rangeLow) / root.rangeSpan
                            readonly property real length: parent.width
                                * (modelData.high - modelData.low) / root.rangeSpan
                            x: start
                            width: Math.max(4, length)
                            height: parent.height
                            radius: 2
                            color: Theme.fillOn
                        }
                    }
                    Text {
                        Layout.preferredWidth: 34
                        text: modelData.high + "°"
                        color: Theme.t1
                        font.family: Theme.fontSerif
                        font.pixelSize: 18
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
