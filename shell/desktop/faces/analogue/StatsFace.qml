// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   S   T   A   T   S       F   A   C   E                                  │
// │   the load as needle gauges · the last minutes as traces under them      │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../services" as DeskServices
import "../../components"

// TODO: components not yet ported

// System load as gauges: the processor on a 2×2; the processor and memory side
// by side with the load and uptime on a 4×2; at 4×4 the two gauges above three
// traces of recent history.
Item {
    id: root

    property string family: "2x2"
    property var ink: DeskServices.DeskDesktopService.inkFor(null)

    Loader {
        anchors.fill: parent
        sourceComponent: root.family === "2x2" ? square : wide
    }

    Component {
        id: square

        Instrument {
            family: root.family
            ink: root.ink
            line: `ram ${Math.round(DeskServices.DeskStatsService.memoryFraction * 100)}%`

            Gauge {
                anchors.centerIn: parent
                ink: root.ink
                size: Math.min(parent.width, parent.height)
                fraction: DeskServices.DeskStatsService.cpu / 100
                label: "cpu"
                value: `${DeskServices.DeskStatsService.cpu.toFixed(0)}%`
            }
        }
    }

    Component {
        id: wide

        Item {
            id: panel

            readonly property bool large: root.family === "4x4"
            readonly property real upper: panel.large ? panel.height / 2 : panel.height
            readonly property real gauge: 128

            Gauge {
                x: 22
                y: (panel.upper - panel.gauge) / 2
                ink: root.ink
                size: panel.gauge
                fraction: DeskServices.DeskStatsService.cpu / 100
                label: "cpu"
                value: `${DeskServices.DeskStatsService.cpu.toFixed(0)}%`
            }

            Gauge {
                x: 22 + panel.gauge + 8
                y: (panel.upper - panel.gauge) / 2
                ink: root.ink
                size: panel.gauge
                fraction: DeskServices.DeskStatsService.memoryFraction
                label: "memory"
                value: DeskServices.DeskStatsService.bytes(DeskServices.DeskStatsService.memoryUsed)
            }

            Column {
                x: 22 + 2 * panel.gauge + 28
                y: panel.upper / 2 - height / 2
                width: panel.width - x - 22
                spacing: 10

                Repeater {
                    model: [
                        { figure: DeskServices.DeskStatsService.load[0].toFixed(2), word: "load" },
                        { figure: DeskServices.DeskStatsService.duration(DeskServices.DeskStatsService.uptime), word: "up" }
                    ]

                    Column {
                        required property var modelData

                        width: parent.width
                        spacing: 1

                        Text {
                            width: parent.width
                            text: parent.modelData.figure
                            elide: Text.ElideRight
                            font.family: DeskServices.DeskTheme.fontFamily
                            font.pixelSize: DeskServices.DeskTheme.fontSizeLarge
                            font.weight: Font.DemiBold
                            color: root.ink.text
                        }

                        Text {
                            text: parent.modelData.word
                            font.family: DeskServices.DeskTheme.fontFamily
                            font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                            font.letterSpacing: 1
                            color: root.ink.muted
                        }
                    }
                }
            }

            Column {
                visible: panel.large
                x: 22
                y: panel.upper
                width: panel.width - 44
                height: panel.upper - 22
                spacing: 10

                Repeater {
                    model: [
                        { title: "Processor", reading: `${DeskServices.DeskStatsService.cpu.toFixed(0)}%`,
                          series: DeskServices.DeskStatsService.cpuHistory },
                        { title: "Memory", reading: DeskServices.DeskStatsService.bytes(DeskServices.DeskStatsService.memoryUsed),
                          series: DeskServices.DeskStatsService.memoryHistory },
                        { title: "Network", reading: DeskServices.DeskStatsService.rate(DeskServices.DeskStatsService.networkDown),
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
        }
    }
}
