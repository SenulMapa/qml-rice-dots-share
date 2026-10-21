// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   L   A   R   G   E   S                                                  │
// │   4×4 widget faces                                                       │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import "../services" as DeskServices
import "../components"

// TODO: components not yet ported

// 4×4 faces, for modules with more to show. The same grid: the mark, label and
// reading stay in place and the extra content goes in the middle. Media and the
// calendar are written out, because their content is the widget. The analogue
// clock is `analogue/Dial.qml`.
Item {
    id: root

    property string moduleId: ""

    // Colours resolved by the widget. Faces read this rather than `Theme`.
    property var ink: DeskServices.DeskDesktopService.inkFor(null)

    // The desktop row, for faces that draw what it names (a note).
    property var row: null

    readonly property var components: ({
        calendar: calendarLarge,
        weather: weatherLarge,
        stats: statsLarge,
        media: mediaLarge,
        claude: claudeLarge,
        notes: notesLarge,
        tasks: tasksLarge,
        photo: photoLarge
    })

    Loader {
        anchors.fill: parent
        sourceComponent: root.components[root.moduleId] ?? null
    }

    // ── ON THE GRID ─────────────────────────────────────────────────────────

    Component {
        id: weatherLarge

        WidgetFace {

            ink: root.ink
            id: weather

            readonly property var hoursAhead: {
                const hour = DeskServices.DeskWeatherService.clock.date.getHours()
                return (DeskServices.DeskWeatherService.available ? (DeskServices.DeskWeatherService.hourly ?? []) : [])
                    .filter(block => block.tomorrow || block.hour > hour)
                    .slice(0, 4)
            }

            label: DeskServices.DeskWeatherService.place || "Weather"
            reading: DeskServices.DeskWeatherService.available ? `${DeskServices.DeskWeatherService.temperature}°` : "--°"
            note: !DeskServices.DeskWeatherService.available ? "no forecast"
                : DeskServices.DeskWeatherService.description !== ""
                ? `${DeskServices.DeskWeatherService.description} · feels ${DeskServices.DeskWeatherService.feelsLike}° · ${DeskServices.DeskWeatherService.high}° / ${DeskServices.DeskWeatherService.low}°`
                : `feels ${DeskServices.DeskWeatherService.feelsLike}° · ${DeskServices.DeskWeatherService.high}° / ${DeskServices.DeskWeatherService.low}°`

            Text {
                anchors.centerIn: parent
                text: DeskServices.DeskWeatherService.available ? DeskServices.DeskWeatherService.glyph : "󰅤"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 34
                color: root.ink.text
            }

            body: [
                Item {
                    anchors.fill: parent

                    // Divided arithmetically: a Layout sizes from its
                    // children's implicit widths, not from the space it was
                    // given.
                    Row {
                        anchors.fill: parent

                        Repeater {
                            model: weather.hoursAhead

                            Item {
                                id: block

                                required property var modelData

                                width: parent.width / Math.max(1, weather.hoursAhead.length)
                                height: parent.height

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: {
                                            const hour = `${block.modelData.hour}`.padStart(2, "0")
                                            return block.modelData.tomorrow
                                                ? `${hour}:00⁺` : `${hour}:00`
                                        }
                                        font.family: DeskServices.DeskTheme.fontMono
                                        font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                                        color: root.ink.muted
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: block.modelData.glyph
                                        font.family: DeskServices.DeskTheme.fontMono
                                        font.pixelSize: 26
                                        color: root.ink.text
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: `${block.modelData.temperature}°`
                                        font.family: DeskServices.DeskTheme.fontMono
                                        font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                                        color: root.ink.text
                                    }
                                }
                            }
                        }
                    }
                }
            ]
        }
    }

    Component {
        id: statsLarge

        WidgetFace {

            ink: root.ink
            label: "System"
            reading: `${DeskServices.DeskStatsService.cpu.toFixed(0)}%`
            note: `load ${DeskServices.DeskStatsService.load[0].toFixed(2)} · ${DeskServices.DeskStatsService.window}`

            Text {
                anchors.centerIn: parent
                text: "󰻠"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 30
                color: root.ink.text
            }

            // Three traces rather than four cards: at this size the recent
            // history is what is worth showing.
            body: [
                Column {
                    anchors.fill: parent
                    spacing: 10

                    Repeater {
                        model: [
                            { title: "Processor", reading: `${DeskServices.DeskStatsService.cpu.toFixed(0)}%`,
                              series: DeskServices.DeskStatsService.cpuHistory },
                            { title: "Memory",
                              reading: `${DeskServices.DeskStatsService.bytes(DeskServices.DeskStatsService.memoryUsed)}`,
                              series: DeskServices.DeskStatsService.memoryHistory },
                            { title: "Network",
                              reading: DeskServices.DeskStatsService.rate(DeskServices.DeskStatsService.networkDown),
                              series: DeskServices.DeskStatsService.downHistory }
                        ]

                        Item {
                            id: trace

                            required property var modelData

                            width: parent.width
                            height: (parent.height - 20) / 3

                            Text {
                                id: traceTitle

                                anchors.left: parent.left
                                anchors.top: parent.top
                                text: trace.modelData.title
                                font.family: DeskServices.DeskTheme.fontFamily
                                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                                color: root.ink.muted
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                text: trace.modelData.reading
                                font.family: DeskServices.DeskTheme.fontMono
                                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                                color: root.ink.text
                            }

                            Sparkline {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: traceTitle.bottom
                                anchors.bottom: parent.bottom
                                anchors.topMargin: 2
                                values: trace.modelData.series
                                stroke: root.ink.accent
                            }
                        }
                    }
                }
            ]
        }
    }

    Component {
        id: claudeLarge

        WidgetFace {

            ink: root.ink
            label: "Claude"
            reading: DeskServices.DeskClaudeService.available ? DeskServices.DeskClaudeService.compact(DeskServices.DeskClaudeService.blockTokens) : "—"
            note: !DeskServices.DeskClaudeService.available ? "no usage found"
                : `this block · ${DeskServices.DeskClaudeService.messages(DeskServices.DeskClaudeService.blockMessages)} · ${DeskServices.DeskClaudeService.resetsIn}`

            ClaudeMark {
                anchors.centerIn: parent
                width: 34
                height: 34
                color: DeskServices.DeskClaudeService.tint
            }

            body: [
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 16
                    visible: DeskServices.DeskClaudeService.available

                    // The percentage comes from the account's response headers,
                    // the same figure as the usage page. Without the account,
                    // the bar shows the block's elapsed time instead.
                    Column {
                        width: parent.width
                        spacing: 7

                        Text {
                            text: DeskServices.DeskClaudeService.sessionMeasured
                                ? `block · ${DeskServices.DeskClaudeService.percent(DeskServices.DeskClaudeService.sessionFraction)}`
                                : "block · against the busiest on record"
                            font.family: DeskServices.DeskTheme.fontFamily
                            font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                            color: root.ink.muted
                        }

                        UsageBar {

                            trackColor: root.ink.raised
                            width: parent.width
                            progress: DeskServices.DeskClaudeService.gauge
                            fillColor: DeskServices.DeskClaudeService.tint
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 7

                        Text {
                            text: DeskServices.DeskClaudeService.weeklyMeasured
                                ? `week · ${DeskServices.DeskClaudeService.percent(DeskServices.DeskClaudeService.weeklyFraction)}`
                                : `week · ${DeskServices.DeskClaudeService.compact(DeskServices.DeskClaudeService.weekTokens)}`
                            font.family: DeskServices.DeskTheme.fontFamily
                            font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                            color: root.ink.muted
                        }

                        UsageBar {

                            trackColor: root.ink.raised
                            width: parent.width
                            progress: DeskServices.DeskClaudeService.weeklyMeasured
                                ? DeskServices.DeskClaudeService.weeklyFraction
                                : (DeskServices.DeskClaudeService.peakWeekTokens > 0
                                    ? DeskServices.DeskClaudeService.weekTokens / DeskServices.DeskClaudeService.peakWeekTokens : 0)
                            fillColor: root.ink.accent
                        }
                    }

                    Text {
                        width: parent.width
                        text: `busiest block · ${DeskServices.DeskClaudeService.compact(DeskServices.DeskClaudeService.peakBlockTokens)}`
                        elide: Text.ElideRight
                        font.family: DeskServices.DeskTheme.fontFamily
                        font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                        color: root.ink.muted
                    }
                }
            ]
        }
    }

    // ── CUSTOM FACES ────────────────────────────────────────────────────────

    Component {
        id: calendarLarge

        Item {
            id: month

            readonly property date today: calendarClock.date

            // Pressing a day with tasks turns the widget into that day's list,
            // as in the control centre's month. The month returns via the arrow
            // or when the pointer leaves, so the widget never stays on a stale
            // day.
            property string picked: ""

            HoverHandler {
                onHoveredChanged: {
                    if (!hovered)
                        month.picked = ""
                }
            }

            readonly property var cells: {
                const year = month.today.getFullYear()
                const index = month.today.getMonth()
                const shift = (new Date(year, index, 1).getDay() + 6) % 7
                const total = new Date(year, index + 1, 0).getDate()
                const list = []
                for (let blank = 0; blank < shift; blank++)
                    list.push(0)
                for (let date = 1; date <= total; date++)
                    list.push(date)
                while (list.length % 7 !== 0)
                    list.push(0)
                return list
            }

            SystemClock {
                id: calendarClock
                precision: SystemClock.Minutes
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 10
                opacity: month.picked === "" ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }

                RowLayout {
                    Layout.fillWidth: true

                    // Ink: the month is a display title in Instrument Serif.
                    Text {
                        text: Qt.formatDateTime(month.today, "MMMM")
                        font.family: DeskServices.DeskTheme.inkMode
                            ? DeskServices.DeskTheme.fontNumeral : DeskServices.DeskTheme.fontFamily
                        font.pixelSize: DeskServices.DeskTheme.inkMode ? 36 : DeskServices.DeskTheme.fontSizeLarge
                        font.weight: DeskServices.DeskTheme.inkMode ? Font.Normal : Font.DemiBold
                        color: root.ink.text
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: Qt.formatDateTime(month.today, "yyyy")
                        font.family: DeskServices.DeskTheme.fontFamily
                        font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                        color: root.ink.muted
                    }
                }

                Grid {
                    id: grid

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7

                    readonly property real cellWidth: width / 7
                    readonly property real cellHeight: height / 7

                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]

                        Item {
                            required property var modelData

                            width: grid.cellWidth
                            height: grid.cellHeight

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                font.family: DeskServices.DeskTheme.fontFamily
                                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                                font.weight: Font.DemiBold
                                // Ink: weekday header in t3.
                                color: DeskServices.DeskTheme.inkMode ? root.ink.dim : root.ink.muted
                            }
                        }
                    }

                    Repeater {
                        model: month.cells

                        Item {
                            id: cell

                            required property int modelData

                            readonly property bool today:
                                cell.modelData === month.today.getDate()
                            readonly property string key: cell.modelData > 0
                                ? DeskServices.DeskTasksService.dayKey(new Date(month.today.getFullYear(),
                                    month.today.getMonth(), cell.modelData)) : ""
                            readonly property int tasks: cell.key !== "" ? DeskServices.DeskTasksService.countOn(cell.key) : 0
                            readonly property int pending: cell.key !== "" ? DeskServices.DeskTasksService.pendingOn(cell.key) : 0
                            readonly property bool picked: cell.key !== "" && month.picked === cell.key && !cell.today

                            width: grid.cellWidth
                            height: grid.cellHeight

                            Rectangle {
                                anchors.centerIn: parent
                                width: Math.min(parent.width, parent.height) - 6
                                height: width
                                radius: width / 2
                                visible: cell.today || cell.picked
                                color: cell.today ? root.ink.accent : "transparent"
                                border.color: root.ink.accent
                                border.width: cell.picked ? 1 : 0
                            }

                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: cell.tasks > 0 ? -1 : 0
                                visible: cell.modelData > 0
                                text: `${cell.modelData}`
                                font.family: DeskServices.DeskTheme.fontFamily
                                font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                                font.weight: cell.today ? Font.DemiBold : Font.Normal
                                color: cell.today ? root.ink.accentText : root.ink.text
                            }

                            // A task due that day.
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 4
                                visible: cell.tasks > 0
                                width: DeskServices.DeskTheme.inkMode ? 4 : 3
                                height: width
                                radius: width / 2
                                color: cell.today ? root.ink.accentText
                                    : (cell.pending > 0 ? root.ink.accent : root.ink.muted)
                            }

                            HoverHandler {
                                enabled: cell.tasks > 0
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                enabled: cell.tasks > 0
                                gesturePolicy: TapHandler.ReleaseWithinBounds
                                onTapped: month.picked = cell.key
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: root.ink.dim
                }

                // Today's tasks under the month: the count and up to two of
                // them.
                ColumnLayout {
                    id: agenda

                    readonly property string day: DeskServices.DeskTasksService.todayKey
                    readonly property var due: DeskServices.DeskTasksService.on(agenda.day)

                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        Layout.fillWidth: true
                        text: {
                            const name = agenda.day === DeskServices.DeskTasksService.todayKey ? "Today"
                                : Qt.formatDate(DeskServices.DeskTasksService.dateOf(agenda.day), "dddd d")
                            const n = agenda.due.length
                            const left = agenda.due.filter(task => task.state !== "done").length
                            return n === 0 ? `${name} · nothing due` : `${name} · ${left} of ${n} to do`
                        }
                        elide: Text.ElideRight
                        font.family: DeskServices.DeskTheme.fontFamily
                        font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                        font.weight: Font.DemiBold
                        color: root.ink.muted
                    }

                    Repeater {
                        model: agenda.due.slice(0, 2)

                        TaskRow {
                            required property var modelData

                            Layout.fillWidth: true
                            task: modelData
                            dated: false
                            ink: ({
                                text: root.ink.text, muted: root.ink.muted, accent: root.ink.accent,
                                accentText: root.ink.accentText, raised: root.ink.raised, red: DeskServices.DeskTheme.red
                            })
                            onOpened: {
                                DeskServices.DeskTasksService.open(modelData.key)
                                DeskServices.ModuleService.requestPanel("board")
                            }
                        }
                    }
                }
            }

            // ── ONE DAY ─────────────────────────────────────────────────────

            DayTasks {
                anchors.fill: parent
                anchors.margins: 22
                day: month.picked
                opacity: month.picked !== "" ? 1 : 0
                visible: opacity > 0
                ink: ({
                    text: root.ink.text, muted: root.ink.muted, accent: root.ink.accent,
                    accentText: root.ink.accentText, raised: root.ink.raised,
                    red: DeskServices.DeskTheme.red, rule: root.ink.dim
                })
                onBack: month.picked = ""

                Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }
            }
        }
    }

    // Album art at a useful size, with the transport under it.
    Component {
        id: mediaLarge

        Item {
            // As large as the room left after the text and the transport; sized
            // to the face's width it would push both out of a square face.
            ClippingRectangle {
                id: sleeve

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 22
                width: Math.min(parent.width - 44,
                                parent.height - 22 - 14 - 18 - info.implicitHeight)
                height: width
                radius: width * DeskServices.DeskTheme.pictureCorner
                color: root.ink.raised

                Image {
                    anchors.fill: parent
                    source: DeskServices.DeskMediaService.artUrl
                    visible: source != "" && status === Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 400
                    sourceSize.height: 400
                }

                Text {
                    anchors.centerIn: parent
                    visible: DeskServices.DeskMediaService.artUrl === ""
                    text: "󰎇"
                    font.family: DeskServices.DeskTheme.fontMono
                    font.pixelSize: 54
                    color: root.ink.muted
                }
            }

            ColumnLayout {
                id: info

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: sleeve.bottom
                anchors.bottom: parent.bottom
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                anchors.topMargin: 14
                anchors.bottomMargin: 18
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: DeskServices.DeskMediaService.title !== "" ? DeskServices.DeskMediaService.title
                        : (DeskServices.DeskMediaService.available ? DeskServices.DeskMediaService.identity : "Nothing playing")
                    elide: Text.ElideRight
                    font.family: DeskServices.DeskTheme.fontFamily
                    font.pixelSize: DeskServices.DeskTheme.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: root.ink.text
                }

                Text {
                    Layout.fillWidth: true
                    text: DeskServices.DeskMediaService.available ? DeskServices.DeskMediaService.artist : "no player"
                    elide: Text.ElideRight
                    font.family: DeskServices.DeskTheme.fontFamily
                    font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                    color: root.ink.muted
                }

                Item { Layout.fillHeight: true }

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 18
                    enabled: DeskServices.DeskMediaService.available
                    opacity: DeskServices.DeskMediaService.available ? 1 : 0.4

                    IconButton {

                        iconColor: root.ink.text
                        icon: "󰒮"
                        iconSize: 16
                        onClicked: DeskServices.DeskMediaService.previous()
                    }

                    IconButton {

                        iconColor: root.ink.text
                        icon: DeskServices.DeskMediaService.playing ? "󰏤" : "󰐊"
                        iconSize: 18
                        onClicked: DeskServices.DeskMediaService.toggle()
                    }

                    IconButton {

                        iconColor: root.ink.text
                        icon: "󰒭"
                        iconSize: 16
                        onClicked: DeskServices.DeskMediaService.next()
                    }
                }
            }
        }
    }

    // A note is its text at any size; see `NoteFace`.
    Component {
        id: notesLarge

        NoteFace { ink: root.ink; row: root.row; family: "4x4" }
    }

    // A picture of your own; see `PhotoFace`.
    Component {
        id: photoLarge

        PhotoFace { ink: root.ink; row: root.row; family: "4x4" }
    }

    // The 2×2 with its middle filled in: the next six tasks, soonest first,
    // each with its day and checkbox.
    Component {
        id: tasksLarge

        WidgetFace {

            ink: root.ink
            label: "Tasks"
            reading: `${DeskServices.DeskTasksService.pending}`
            note: DeskServices.DeskTasksService.pending === 0
                ? (DeskServices.DeskTasksService.count === 0 ? "nothing yet" : "all done")
                : DeskServices.DeskTasksService.summary
            tint: DeskServices.DeskTasksService.overdue.length > 0 ? DeskServices.DeskTheme.red : root.ink.text

            Text {
                anchors.centerIn: parent
                text: "󰄲"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 30
                color: root.ink.text
            }

            body: [
                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 2

                    Repeater {
                        model: DeskServices.DeskTasksService.queue.slice(0, 6)

                        TaskRow {
                            required property var modelData

                            width: parent.width
                            task: modelData
                            ink: ({
                                text: root.ink.text, muted: root.ink.muted, accent: root.ink.accent,
                                accentText: root.ink.accentText, raised: root.ink.raised, red: DeskServices.DeskTheme.red
                            })
                            onOpened: {
                                DeskServices.DeskTasksService.open(modelData.key)
                                DeskServices.ModuleService.requestPanel("board")
                            }
                        }
                    }
                }
            ]
        }
    }
}
