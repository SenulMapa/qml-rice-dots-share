// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   W   I   D   E   S                                                      │
// │   4×2 widget faces                                                       │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell
import Quickshell.Widgets

import "../services" as DeskServices
import "../components"

// TODO: components not yet ported

// 4×2 faces: the 2×2 grid with the right half filled in. The mark, label,
// reading and caption stay where they are on the square; whatever the square
// had no room for goes on the right. Faces read services, not modules. Modules
// with no row here fall back to their island detail.
Item {
    id: root

    property string moduleId: ""

    // Colours resolved by the widget. Faces read this rather than `Theme`.
    property var ink: DeskServices.DeskDesktopService.inkFor(null)

    // The desktop row, for faces that draw what it names (a note).
    property var row: null

    readonly property var components: ({
        battery: batteryWide,
        volume: volumeWide,
        brightness: brightnessWide,
        network: networkWide,
        bluetooth: bluetoothWide,
        updates: updatesWide,
        weather: weatherWide,
        github: githubWide,
        stats: statsWide,
        claude: claudeWide,
        timer: timerWide,
        pet: petWide,
        media: mediaWide,
        clock: clockWide,
        calendar: calendarWide,
        notes: notesWide,
        tasks: tasksWide,
        photo: photoWide
    })

    Loader {
        anchors.fill: parent
        active: root.components[root.moduleId] !== undefined
        sourceComponent: root.components[root.moduleId] ?? null
    }

    // Fallback for a module id with no entry in `components` above (every
    // desktop module this port ships has one, so this is normally dead).
    // impasto falls back to the bar's own island detail (bar/Module.qml)
    // here; that's the bar, which this port deliberately does not bring in
    // (see HANDOVER.md), so an unmapped module just says so instead of
    // reaching for a component that was never ported.
    Loader {
        anchors.centerIn: parent
        active: root.components[root.moduleId] === undefined
        sourceComponent: unavailable
    }

    Component {
        id: unavailable

        Text {
            text: root.moduleId !== "" ? `"${root.moduleId}" has no desktop face` : ""
            color: root.ink.textMuted ?? root.ink.text
            font.family: DeskServices.DeskTheme.fontFamily
            font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
            wrapMode: Text.WordWrap
            width: 140
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ── GAUGES ──────────────────────────────────────────────────────────────
    //
    // Percentages are repeated as a bar on the right, which shows at a glance
    // whether the value is high or low.

    Component {
        id: batteryWide

        WidgetFace {

            ink: root.ink
            label: "Battery"
            reading: DeskServices.DeskBatteryService.available ? `${DeskServices.DeskBatteryService.percent}%` : "—"
            note: DeskServices.DeskBatteryService.available ? DeskServices.DeskBatteryService.estimate : "no battery"
            extraShare: 0.42

            BatteryWidget { size: 40; glyphColor: root.ink.text; track: root.ink.dim }

            extra: [
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 8

                    UsageBar {

                        trackColor: root.ink.raised
                        width: parent.width
                        progress: DeskServices.DeskBatteryService.percent / 100
                        fillColor: DeskServices.DeskBatteryService.tint
                    }

                    Text {
                        width: parent.width
                        text: !DeskServices.DeskBatteryService.available ? ""
                            : DeskServices.DeskBatteryService.watts > 0
                            ? `${DeskServices.DeskBatteryService.watts.toFixed(1)} W · ${DeskServices.DeskBatteryService.energy.toFixed(1)} Wh`
                            : `${DeskServices.DeskBatteryService.energy.toFixed(1)} Wh`
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        font.family: DeskServices.DeskTheme.fontFamily
                        font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                        color: root.ink.muted
                    }
                }
            ]
        }
    }

    Component {
        id: volumeWide

        WidgetFace {

            ink: root.ink
            label: "Volume"
            reading: DeskServices.DeskAudioService.muted ? "Muted" : `${DeskServices.DeskAudioService.volume}%`
            note: DeskServices.DeskAudioService.muted ? "output silenced" : "output"
            tint: DeskServices.DeskAudioService.muted ? root.ink.muted : root.ink.text
            extraShare: 0.42

            RingIndicator {
                anchors.fill: parent
                thickness: 3
                progress: DeskServices.DeskAudioService.muted ? 0 : DeskServices.DeskAudioService.volume / 100
                trackColor: root.ink.dim
                fillColor: root.ink.text

                Text {
                    anchors.centerIn: parent
                    text: DeskServices.DeskAudioService.icon
                    font.family: DeskServices.DeskTheme.fontMono
                    font.pixelSize: 16
                    color: DeskServices.DeskAudioService.muted ? root.ink.muted : root.ink.text
                }
            }

            extra: [
                UsageBar {
                    trackColor: root.ink.raised
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    progress: DeskServices.DeskAudioService.muted ? 0 : DeskServices.DeskAudioService.volume / 100
                    fillColor: root.ink.text
                }
            ]
        }
    }

    Component {
        id: brightnessWide

        WidgetFace {

            ink: root.ink
            label: "Brightness"
            reading: DeskServices.DeskBrightnessService.available ? `${DeskServices.DeskBrightnessService.percent}%` : "—"
            note: DeskServices.DeskBrightnessService.available ? "backlight" : "no backlight"
            extraShare: 0.42

            RingIndicator {
                anchors.fill: parent
                thickness: 3
                progress: DeskServices.DeskBrightnessService.percent / 100
                trackColor: root.ink.dim
                fillColor: root.ink.text

                Text {
                    anchors.centerIn: parent
                    text: DeskServices.DeskBrightnessService.icon
                    font.family: DeskServices.DeskTheme.fontMono
                    font.pixelSize: 16
                    color: root.ink.text
                }
            }

            extra: [
                UsageBar {
                    trackColor: root.ink.raised
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    progress: DeskServices.DeskBrightnessService.percent / 100
                    fillColor: root.ink.text
                }
            ]
        }
    }

    Component {
        id: claudeWide

        WidgetFace {

            ink: root.ink
            label: "Claude"
            reading: !DeskServices.DeskClaudeService.available ? "—"
                : DeskServices.DeskClaudeService.sessionMeasured
                ? DeskServices.DeskClaudeService.percent(DeskServices.DeskClaudeService.sessionFraction)
                : DeskServices.DeskClaudeService.compact(DeskServices.DeskClaudeService.blockTokens)
            note: !DeskServices.DeskClaudeService.available ? "no usage found"
                : DeskServices.DeskClaudeService.sessionMeasured
                ? `of this block · ${DeskServices.DeskClaudeService.compact(DeskServices.DeskClaudeService.blockTokens)}`
                : `this block · ${DeskServices.DeskClaudeService.messages(DeskServices.DeskClaudeService.blockMessages)}`
            extraShare: 0.42

            ClaudeMark {
                anchors.centerIn: parent
                width: 32
                height: 32
                color: DeskServices.DeskClaudeService.tint
            }

            extra: [
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 8
                    visible: DeskServices.DeskClaudeService.available

                    UsageBar {

                        trackColor: root.ink.raised
                        width: parent.width
                        progress: DeskServices.DeskClaudeService.gauge
                        fillColor: DeskServices.DeskClaudeService.tint
                    }

                    Text {
                        width: parent.width
                        text: DeskServices.DeskClaudeService.resetsIn
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        font.family: DeskServices.DeskTheme.fontFamily
                        font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                        color: root.ink.muted
                    }
                }
            ]
        }
    }

    // ── DETAILS ─────────────────────────────────────────────────────────────

    Component {
        id: statsWide

        WidgetFace {

            ink: root.ink
            label: "System"
            reading: `${DeskServices.DeskStatsService.cpu.toFixed(0)}%`
            note: `RAM ${Math.round(DeskServices.DeskStatsService.memoryFraction * 100)}% · load ${DeskServices.DeskStatsService.load[0].toFixed(2)}`
            extraShare: 0.45

            Text {
                anchors.centerIn: parent
                text: "󰻠"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 30
                color: root.ink.text
            }

            extra: [
                Sparkline {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 48
                    values: DeskServices.DeskStatsService.cpuHistory
                    stroke: root.ink.accent
                }
            ]
        }
    }

    Component {
        id: weatherWide

        WidgetFace {

            ink: root.ink
            id: weather

            readonly property var hoursAhead: {
                const hour = DeskServices.DeskWeatherService.clock.date.getHours()
                return (DeskServices.DeskWeatherService.available ? (DeskServices.DeskWeatherService.hourly ?? []) : [])
                    .filter(block => block.tomorrow || block.hour > hour)
                    .slice(0, 3)
            }

            label: DeskServices.DeskWeatherService.place || "Weather"
            reading: DeskServices.DeskWeatherService.available ? `${DeskServices.DeskWeatherService.temperature}°` : "--°"
            note: !DeskServices.DeskWeatherService.available ? "no forecast"
                : DeskServices.DeskWeatherService.description !== ""
                ? `${DeskServices.DeskWeatherService.description} · ${DeskServices.DeskWeatherService.high}° / ${DeskServices.DeskWeatherService.low}°`
                : `${DeskServices.DeskWeatherService.high}° / ${DeskServices.DeskWeatherService.low}°`
            extraShare: 0.45

            Text {
                anchors.centerIn: parent
                text: DeskServices.DeskWeatherService.available ? DeskServices.DeskWeatherService.glyph : "󰅤"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 34
                color: root.ink.text
            }

            extra: [
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
                                spacing: 2

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: {
                                        const hour = `${block.modelData.hour}`.padStart(2, "0")
                                        return block.modelData.tomorrow
                                            ? `${hour}⁺` : `${hour}h`
                                    }
                                    font.family: DeskServices.DeskTheme.fontMono
                                    font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                                    color: root.ink.muted
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: block.modelData.glyph
                                    font.family: DeskServices.DeskTheme.fontMono
                                    font.pixelSize: 20
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
            ]
        }
    }

    Component {
        id: updatesWide

        WidgetFace {

            ink: root.ink
            label: "Updates"
            reading: DeskServices.DeskUpdatesService.available || DeskServices.DeskUpdatesService.checking
                ? `${DeskServices.DeskUpdatesService.count}` : "—"
            note: DeskServices.DeskUpdatesService.checking
                ? "checking"
                : (!DeskServices.DeskUpdatesService.available ? "cannot check"
                    : (DeskServices.DeskUpdatesService.count === 0 ? "up to date" : "pending"))
            tint: DeskServices.DeskUpdatesService.count === 0 ? root.ink.muted : root.ink.text
            extraShare: 0.45

            Text {
                anchors.centerIn: parent
                text: "󰏖"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 30
                color: DeskServices.DeskUpdatesService.count === 0 ? root.ink.muted : root.ink.text
            }

            extra: [
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: DeskServices.DeskUpdatesService.available ? DeskServices.DeskUpdatesService.packages.slice(0, 4) : []

                        Text {
                            required property var modelData

                            width: parent.width
                            text: modelData
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideLeft
                            font.family: DeskServices.DeskTheme.fontMono
                            font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                            color: root.ink.muted
                        }
                    }
                }
            ]
        }
    }

    Component {
        id: bluetoothWide

        WidgetFace {

            ink: root.ink
            label: "Bluetooth"
            reading: DeskServices.DeskBluetoothService.summary
            note: !DeskServices.DeskBluetoothService.available ? "no adapter"
                : (DeskServices.DeskBluetoothService.enabled ? "adapter on" : "adapter off")
            extraShare: 0.42

            Text {
                anchors.centerIn: parent
                text: DeskServices.DeskBluetoothService.icon
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 30
                color: DeskServices.DeskBluetoothService.enabled ? root.ink.text : root.ink.muted
            }

            extra: [
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    spacing: 3

                    Repeater {
                        model: DeskServices.DeskBluetoothService.connectedDevices.slice(0, 3)

                        Text {
                            required property var modelData

                            width: parent.width
                            text: modelData.name
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            font.family: DeskServices.DeskTheme.fontFamily
                            font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                            color: root.ink.muted
                        }
                    }
                }
            ]
        }
    }

    // The name and the state are the whole content, so they take the full
    // width.
    Component {
        id: networkWide

        WidgetFace {

            ink: root.ink
            label: "Network"
            reading: DeskServices.DeskNetworkService.connectionName
            note: DeskServices.DeskNetworkService.stateLine

            Text {
                anchors.centerIn: parent
                text: DeskServices.DeskNetworkService.icon
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 30
                color: DeskServices.DeskNetworkService.online ? root.ink.text : root.ink.muted
            }
        }
    }

    // ── CONTROLS ────────────────────────────────────────────────────────────
    //
    // The controls go in the extra area, so these stay on the same grid as the
    // rest.

    Component {
        id: timerWide

        WidgetFace {

            ink: root.ink
            label: "Timer"
            reading: DeskServices.DeskTimerService.running ? DeskServices.DeskTimerService.display : "—"
            note: DeskServices.DeskTimerService.running
                ? (DeskServices.DeskTimerService.label !== "" ? DeskServices.DeskTimerService.label : "counting down")
                : "nothing running"
            tint: DeskServices.DeskTimerService.running ? root.ink.text : root.ink.muted
            extraShare: 0.4

            RingIndicator {
                anchors.fill: parent
                thickness: 3
                progress: DeskServices.DeskTimerService.progress
                trackColor: root.ink.dim
                fillColor: DeskServices.DeskTheme.indicatorTimer
            }

            extra: [
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    spacing: 10

                    PillButton {
                        text: DeskServices.DeskTimerService.running
                            ? (DeskServices.DeskTimerService.paused ? "Resume" : "Hold") : "5 min"
                        implicitHeight: 30
                        // Milliseconds: the service counts in Timer units.
                        onClicked: {
                            if (!DeskServices.DeskTimerService.running)
                                DeskServices.DeskTimerService.start(5 * 60 * 1000, "")
                            else
                                DeskServices.DeskTimerService.toggle()
                        }
                    }

                    IconButton {

                        iconColor: root.ink.text
                        icon: "󰅖"
                        iconSize: 13
                        enabled: DeskServices.DeskTimerService.running
                        opacity: DeskServices.DeskTimerService.running ? 1 : 0.35
                        onClicked: DeskServices.DeskTimerService.cancel()
                    }
                }
            ]
        }
    }

    Component {
        id: mediaWide

        WidgetFace {

            ink: root.ink
            label: DeskServices.DeskMediaService.artist !== "" ? DeskServices.DeskMediaService.artist : "Media"
            reading: DeskServices.DeskMediaService.title !== "" ? DeskServices.DeskMediaService.title
                : (DeskServices.DeskMediaService.available ? DeskServices.DeskMediaService.identity : "Nothing playing")
            note: !DeskServices.DeskMediaService.available ? "no player"
                : (DeskServices.DeskMediaService.playing ? "playing" : "paused")
            extraShare: 0.4

            ClippingRectangle {
                anchors.fill: parent
                radius: width * DeskServices.DeskTheme.pictureCorner
                color: root.ink.raised

                Image {
                    anchors.fill: parent
                    source: DeskServices.DeskMediaService.artUrl
                    visible: source != "" && status === Image.Ready
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 80
                    sourceSize.height: 80
                }

                Text {
                    anchors.centerIn: parent
                    visible: DeskServices.DeskMediaService.artUrl === ""
                    text: "󰎇"
                    font.family: DeskServices.DeskTheme.fontMono
                    font.pixelSize: 18
                    color: root.ink.muted
                }
            }

            extra: [
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    spacing: 16
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
            ]
        }
    }

    Component {
        id: petWide

        WidgetFace {

            ink: root.ink
            label: DeskServices.DeskPetService.name !== "" ? DeskServices.DeskPetService.name : "Pet"
            reading: DeskServices.DeskPetService.hatched ? `Lv ${DeskServices.DeskPetService.level}` : "Egg"
            note: DeskServices.DeskPetService.moodLine
            extraShare: 0.4

            RingIndicator {
                anchors.fill: parent
                thickness: 3
                progress: DeskServices.DeskPetService.progress
                trackColor: root.ink.dim
                fillColor: root.ink.text
            }

            extra: [
                PetFace {
                    anchors.centerIn: parent
                    size: 56
                    lively: true
                }
            ]
        }
    }

    // ── TIME ────────────────────────────────────────────────────────────────

    Component {
        id: clockWide

        WidgetFace {

            ink: root.ink
            id: clockFace

            readonly property string format: DeskServices.DeskSettings.clockShowsSeconds
                ? DeskServices.DeskSettings.clockFormat.replace("mm", "mm:ss")
                : DeskServices.DeskSettings.clockFormat

            label: Qt.formatDateTime(clock.date, "dddd")
            reading: Qt.formatDateTime(clock.date, clockFace.format)
            note: Qt.formatDateTime(clock.date, "d MMMM yyyy")

            SystemClock {
                id: clock
                precision: DeskServices.DeskSettings.clockShowsSeconds
                    ? SystemClock.Seconds : SystemClock.Minutes
            }

            Text {
                anchors.centerIn: parent
                text: "󰥔"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 30
                color: root.ink.text
            }
        }
    }

    // The week around today; the month is the 4×4 face.
    Component {
        id: calendarWide

        Item {
            id: week

            // Pressing a day with tasks shows that day's list, as on the 4×4.
            // The week returns via the arrow or when the pointer leaves.
            property string picked: ""

            HoverHandler {
                onHoveredChanged: {
                    if (!hovered)
                        week.picked = ""
                }
            }

            WidgetFace {

                ink: root.ink
                id: calendarFace

                anchors.fill: parent
                opacity: week.picked === "" ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }

                readonly property date today: calendarClock.date

                // The same label and reading as the square, so the wide face
                // adds the week without rearranging anything.
                label: Qt.formatDateTime(calendarClock.date, "MMMM")
                reading: `${calendarFace.today.getDate()}`
                // Today's count if any; else the next task due; else the
                // weekday.
                note: {
                    const left = DeskServices.DeskTasksService.pendingOn(DeskServices.DeskTasksService.todayKey)
                    if (left > 0)
                        return `${left} to do today`
                    const next = DeskServices.DeskTasksService.next
                    if (next)
                        return `${next.text} · ${DeskServices.DeskTasksService.dueLabel(next.due)}`
                    return Qt.formatDateTime(calendarClock.date, "dddd")
                }
                extraShare: 0.5

                SystemClock {
                    id: calendarClock
                    precision: SystemClock.Minutes
                }

                Text {
                    anchors.centerIn: parent
                    text: "󰃭"
                    font.family: DeskServices.DeskTheme.fontMono
                    font.pixelSize: 30
                    color: root.ink.text
                }

                extra: [
                    Row {
                        anchors.fill: parent

                        Repeater {
                            model: 7

                            Item {
                                id: day

                                required property int index

                                // Monday first, the way the month is laid out.
                                readonly property date date: {
                                    const base = new Date(calendarFace.today)
                                    const shift = (base.getDay() + 6) % 7
                                    base.setDate(base.getDate() - shift + day.index)
                                    return base
                                }

                                readonly property bool today:
                                    day.date.getDate() === calendarFace.today.getDate()
                                    && day.date.getMonth() === calendarFace.today.getMonth()

                                readonly property string key: DeskServices.DeskTasksService.dayKey(day.date)
                                readonly property int tasks: DeskServices.DeskTasksService.countOn(day.key)
                                readonly property int pending: DeskServices.DeskTasksService.pendingOn(day.key)

                                width: parent.width / 7
                                height: parent.height

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Qt.formatDateTime(day.date, "ddd").charAt(0)
                                        font.family: DeskServices.DeskTheme.fontFamily
                                        font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                                        color: root.ink.muted
                                    }

                                    Rectangle {
                                        width: 24
                                        height: 24
                                        radius: 12
                                        color: day.today ? root.ink.accent : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            anchors.verticalCenterOffset: day.tasks > 0 ? -1 : 0
                                            text: `${day.date.getDate()}`
                                            font.family: DeskServices.DeskTheme.fontFamily
                                            font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                                            font.weight: day.today ? Font.DemiBold : Font.Normal
                                            color: day.today ? root.ink.accentText : root.ink.text
                                        }

                                        // A task due that day: the accent while
                                        // any is open, muted once done.
                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 2
                                            visible: day.tasks > 0
                                            width: 3
                                            height: 3
                                            radius: 1.5
                                            color: day.today ? root.ink.accentText
                                                : (day.pending > 0 ? root.ink.accent : root.ink.muted)
                                        }
                                    }
                                }

                                HoverHandler {
                                    enabled: day.tasks > 0
                                    cursorShape: Qt.PointingHandCursor
                                }

                                TapHandler {
                                    enabled: day.tasks > 0
                                    gesturePolicy: TapHandler.ReleaseWithinBounds
                                    onTapped: week.picked = day.key
                                }
                            }
                        }
                    }
                ]
            }

            DayTasks {
                anchors.fill: parent
                anchors.margins: 18
                day: week.picked
                opacity: week.picked !== "" ? 1 : 0
                visible: opacity > 0
                ink: ({
                    text: root.ink.text, muted: root.ink.muted, accent: root.ink.accent,
                    accentText: root.ink.accentText, raised: root.ink.raised,
                    red: DeskServices.DeskTheme.red, rule: root.ink.dim
                })
                onBack: week.picked = ""

                Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }
            }
        }
    }

    // The 2×2 plus the next three tasks, with checkboxes.
    Component {
        id: tasksWide

        WidgetFace {

            ink: root.ink
            label: "Tasks"
            reading: `${DeskServices.DeskTasksService.pending}`
            note: DeskServices.DeskTasksService.pending === 0
                ? (DeskServices.DeskTasksService.count === 0 ? "nothing yet" : "all done")
                : DeskServices.DeskTasksService.summary
            tint: DeskServices.DeskTasksService.overdue.length > 0 ? DeskServices.DeskTheme.red : root.ink.text
            extraShare: 0.55

            Text {
                anchors.centerIn: parent
                text: "󰄲"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 30
                color: root.ink.text
            }

            extra: [
                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Repeater {
                        model: DeskServices.DeskTasksService.queue.slice(0, 3)

                        TaskRow {
                            required property var modelData

                            width: parent.width
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
            ]
        }
    }

    // A note is its text at any size; see `NoteFace`.
    Component {
        id: notesWide

        NoteFace { ink: root.ink; row: root.row; family: "4x2" }
    }

    // A picture of your own; see `PhotoFace`.
    Component {
        id: photoWide

        PhotoFace { ink: root.ink; row: root.row; family: "4x2" }
    }

    // Half a year of the contribution wall; see `GithubFace`.
    Component {
        id: githubWide

        GithubFace { ink: root.ink; family: "4x2" }
    }
}
