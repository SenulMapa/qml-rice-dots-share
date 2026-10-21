// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   S   Q   U   A   R   E   S                                              │
// │   2×2 widget faces                                                       │
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

// Registry of 2×2 faces. Each is a WidgetFace: the module's bar mark, its main
// value and a caption. Faces read the same services as the bar modules and
// never reach into the modules themselves. Adding one is a Component here and a
// family in the catalogue.
Item {
    id: root

    property string moduleId: ""

    // Colours resolved by the widget. Faces read this rather than `Theme`.
    property var ink: DeskServices.DeskDesktopService.inkFor(null)

    // The desktop row, for faces that draw what it names (a note).
    property var row: null

    readonly property var components: ({
        battery: batterySquare,
        volume: volumeSquare,
        brightness: brightnessSquare,
        network: networkSquare,
        bluetooth: bluetoothSquare,
        updates: updatesSquare,
        weather: weatherSquare,
        github: githubSquare,
        stats: statsSquare,
        claude: claudeSquare,
        timer: timerSquare,
        pet: petSquare,
        games: gamesSquare,
        media: mediaSquare,
        clock: clockSquare,
        calendar: calendarSquare,
        notes: notesSquare,
        tasks: tasksSquare,
        photo: photoSquare
    })

    Loader {
        anchors.fill: parent
        sourceComponent: root.components[root.moduleId] ?? null
    }

    // ── READINGS ────────────────────────────────────────────────────────────

    Component {
        id: batterySquare

        WidgetFace {

            ink: root.ink
            // Every face shows something when there is no data: widgets are
            // always drawn.
            label: "Battery"
            reading: DeskServices.DeskBatteryService.available ? `${DeskServices.DeskBatteryService.percent}%` : "—"
            note: DeskServices.DeskBatteryService.available ? DeskServices.DeskBatteryService.estimate : "no battery"

            BatteryWidget { size: 40; glyphColor: root.ink.text; track: root.ink.dim }
        }
    }

    Component {
        id: volumeSquare

        WidgetFace {

            ink: root.ink
            label: "Volume"
            reading: DeskServices.DeskAudioService.muted ? "Muted" : `${DeskServices.DeskAudioService.volume}%`
            tint: DeskServices.DeskAudioService.muted ? root.ink.muted : root.ink.text

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
        }
    }

    Component {
        id: brightnessSquare

        WidgetFace {

            ink: root.ink
            label: "Brightness"
            reading: DeskServices.DeskBrightnessService.available ? `${DeskServices.DeskBrightnessService.percent}%` : "—"
            note: DeskServices.DeskBrightnessService.available ? "" : "no backlight"

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
        }
    }

    Component {
        id: networkSquare

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

    Component {
        id: bluetoothSquare

        WidgetFace {

            ink: root.ink
            label: "Bluetooth"
            reading: DeskServices.DeskBluetoothService.summary

            Text {
                anchors.centerIn: parent
                text: DeskServices.DeskBluetoothService.icon
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 30
                color: DeskServices.DeskBluetoothService.enabled ? root.ink.text : root.ink.muted
            }
        }
    }

    Component {
        id: updatesSquare

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

            Text {
                anchors.centerIn: parent
                text: "󰏖"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 30
                color: DeskServices.DeskUpdatesService.count === 0 ? root.ink.muted : root.ink.text
            }
        }
    }

    Component {
        id: weatherSquare

        WidgetFace {

            ink: root.ink
            label: DeskServices.DeskWeatherService.place || "Weather"
            reading: DeskServices.DeskWeatherService.available ? `${DeskServices.DeskWeatherService.temperature}°` : "--°"
            note: DeskServices.DeskWeatherService.available ? DeskServices.DeskWeatherService.description : "no forecast"

            Text {
                anchors.centerIn: parent
                text: DeskServices.DeskWeatherService.available ? DeskServices.DeskWeatherService.glyph : "󰅤"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 34
                color: root.ink.text
            }
        }
    }

    Component {
        id: statsSquare

        WidgetFace {

            ink: root.ink
            label: "System"
            reading: `${DeskServices.DeskStatsService.cpu.toFixed(0)}%`
            note: `RAM ${Math.round(DeskServices.DeskStatsService.memoryFraction * 100)}%`

            Text {
                anchors.centerIn: parent
                text: "󰻠"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: 30
                color: root.ink.text
            }
        }
    }

    Component {
        id: claudeSquare

        WidgetFace {

            ink: root.ink
            label: "Claude"
            reading: !DeskServices.DeskClaudeService.available ? "—"
                : DeskServices.DeskClaudeService.sessionMeasured
                ? DeskServices.DeskClaudeService.percent(DeskServices.DeskClaudeService.sessionFraction)
                : DeskServices.DeskClaudeService.compact(DeskServices.DeskClaudeService.blockTokens)
            note: !DeskServices.DeskClaudeService.available ? "no usage found"
                : (DeskServices.DeskClaudeService.sessionMeasured ? "of this block" : "this block")

            ClaudeMark {
                anchors.centerIn: parent
                width: 32
                height: 32
                color: root.ink.text
            }
        }
    }

    Component {
        id: timerSquare

        WidgetFace {

            ink: root.ink
            label: "Timer"
            reading: DeskServices.DeskTimerService.running ? DeskServices.DeskTimerService.display : "—"
            note: DeskServices.DeskTimerService.running
                ? (DeskServices.DeskTimerService.label !== "" ? DeskServices.DeskTimerService.label : "counting down")
                : "nothing running"
            tint: DeskServices.DeskTimerService.running ? root.ink.text : root.ink.muted

            RingIndicator {
                anchors.fill: parent
                thickness: 3
                progress: DeskServices.DeskTimerService.progress
                trackColor: root.ink.dim
                fillColor: DeskServices.DeskTheme.indicatorTimer
            }
        }
    }

    Component {
        id: gamesSquare

        WidgetFace {

            ink: root.ink
            readonly property var last: DeskServices.DeskGamesService.entry(DeskServices.DeskGamesService.lastPlayed)

            label: "Games"
            reading: last ? `${DeskServices.DeskGamesService.bestOf(last.id)}` : "—"
            note: last ? `${last.name} · best` : "Nothing played yet"

            RingIndicator {
                anchors.fill: parent
                thickness: 3
                progress: 0
                trackColor: root.ink.dim

                Text {
                    anchors.centerIn: parent
                    text: "󰊗"
                    font.family: DeskServices.DeskTheme.fontMono
                    font.pixelSize: 18
                    color: root.ink.text
                }
            }
        }
    }

    Component {
        id: petSquare

        WidgetFace {

            ink: root.ink
            label: DeskServices.DeskPetService.name !== "" ? DeskServices.DeskPetService.name : "Pet"
            reading: DeskServices.DeskPetService.hatched ? `Lv ${DeskServices.DeskPetService.level}` : "Egg"
            note: DeskServices.DeskPetService.mood

            RingIndicator {
                anchors.fill: parent
                thickness: 3
                progress: DeskServices.DeskPetService.progress
                trackColor: root.ink.dim
                fillColor: root.ink.text

                PetFace {
                    anchors.centerIn: parent
                    size: 26
                    lively: true
                }
            }
        }
    }

    // ── OTHER FACES ────────────────────────────────────────────────────────

    // The album art as the mark, at mark size; the 4×4 face has room for the
    // full art.
    Component {
        id: mediaSquare

        WidgetFace {

            ink: root.ink
            // Without a player it says so rather than going blank.
            label: DeskServices.DeskMediaService.artist !== "" ? DeskServices.DeskMediaService.artist : "Media"
            reading: DeskServices.DeskMediaService.title !== "" ? DeskServices.DeskMediaService.title
                : (DeskServices.DeskMediaService.available ? DeskServices.DeskMediaService.identity : "Nothing playing")
            note: !DeskServices.DeskMediaService.available ? "no player"
                : (DeskServices.DeskMediaService.playing ? "playing" : "paused")

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
        }
    }

    Component {
        id: clockSquare

        WidgetFace {

            ink: root.ink
            id: clockFace

            readonly property string format: DeskServices.DeskSettings.clockShowsSeconds
                ? DeskServices.DeskSettings.clockFormat.replace("mm", "mm:ss")
                : DeskServices.DeskSettings.clockFormat

            label: Qt.formatDateTime(clock.date, "ddd")
            reading: Qt.formatDateTime(clock.date, clockFace.format)
            note: Qt.formatDateTime(clock.date, "d MMMM")

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

    // The date; the month is the 4×4 face. The square is today, so pressing it
    // with tasks shows today's list, as a pressed day does on the larger faces.
    // The square returns via the arrow or when the pointer leaves.
    Component {
        id: calendarSquare

        Item {
            id: leaf

            property bool open: false

            HoverHandler {
                onHoveredChanged: {
                    if (!hovered)
                        leaf.open = false
                }
            }

            WidgetFace {

                ink: root.ink
                id: calendarFace

                anchors.fill: parent
                opacity: leaf.open ? 0 : 1
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }

                readonly property date today: calendarClock.date

                label: Qt.formatDateTime(calendarClock.date, "MMMM")
                reading: `${calendarFace.today.getDate()}`
                // The weekday, and how much of today is left when there are
                // tasks.
                note: {
                    const weekday = Qt.formatDateTime(calendarClock.date, "dddd")
                    const left = DeskServices.DeskTasksService.pendingOn(DeskServices.DeskTasksService.todayKey)
                    return left > 0 ? `${weekday} · ${left} to do` : weekday
                }

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

                HoverHandler {
                    enabled: DeskServices.DeskTasksService.countOn(DeskServices.DeskTasksService.todayKey) > 0
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    enabled: DeskServices.DeskTasksService.countOn(DeskServices.DeskTasksService.todayKey) > 0
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: leaf.open = true
                }
            }

            DayTasks {
                anchors.fill: parent
                anchors.margins: 16
                day: leaf.open ? DeskServices.DeskTasksService.todayKey : ""
                opacity: leaf.open ? 1 : 0
                visible: opacity > 0
                ink: ({
                    text: root.ink.text, muted: root.ink.muted, accent: root.ink.accent,
                    accentText: root.ink.accentText, raised: root.ink.raised,
                    red: DeskServices.DeskTheme.red, rule: root.ink.dim
                })
                onBack: leaf.open = false

                Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }
            }
        }
    }

    // Notes use one face for all four families.
    Component {
        id: notesSquare

        NoteFace { ink: root.ink; row: root.row; family: "2x2" }
    }

    // A picture of your own, one face for all four families; see `PhotoFace`.
    Component {
        id: photoSquare

        PhotoFace { ink: root.ink; row: root.row; family: "2x2" }
    }

    // The contribution wall, one face for all four families.
    Component {
        id: githubSquare

        GithubFace { ink: root.ink; family: "2x2" }
    }

    // Tasks left, and one line: overdue, else due today, else the next one.
    Component {
        id: tasksSquare

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
        }
    }
}
