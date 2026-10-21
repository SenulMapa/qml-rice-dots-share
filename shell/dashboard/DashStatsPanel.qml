// Simplified port of impasto's bar/island/StatsPanel.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// CPU, memory, network and thermal, real data throughout via
// desktop/services/DeskStatsService.qml (already shipped by the desktop
// port -- scripts/desktop/stats.py). Reuses the same Sparkline/UsageBar
// components the desktop CPU/memory faces already use.

import QtQuick
import QtQuick.Layouts
import "../desktop/services" as Desk
import "../desktop/components" as DeskComponents
import "components" as DashComponents

ColumnLayout {
    id: root

    signal closed()

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        DashComponents.Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 110
            padding: 10

            ColumnLayout {
                anchors.fill: parent
                spacing: 4

                Text {
                    text: "CPU · " + Math.round(Desk.DeskStatsService.cpu) + "%"
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Desk.DeskTheme.text
                }

                Text {
                    Layout.fillWidth: true
                    text: Desk.DeskStatsService.cpuModel
                    elide: Text.ElideRight
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeLabel
                    color: Desk.DeskTheme.textMuted
                }

                DeskComponents.Sparkline {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    values: Desk.DeskStatsService.cpuHistory
                    maximum: 100
                }
            }
        }

        DashComponents.Card {
            Layout.fillWidth: true
            Layout.preferredHeight: 110
            padding: 10

            ColumnLayout {
                anchors.fill: parent
                spacing: 4

                Text {
                    text: "Memory · " + Math.round(Desk.DeskStatsService.memoryFraction * 100) + "%"
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Desk.DeskTheme.text
                }

                Text {
                    text: Desk.DeskStatsService.bytes(Desk.DeskStatsService.memoryUsed)
                        + " / " + Desk.DeskStatsService.bytes(Desk.DeskStatsService.memoryTotal)
                    font.family: Desk.DeskTheme.fontMono
                    font.pixelSize: Desk.DeskTheme.fontSizeLabel
                    color: Desk.DeskTheme.textMuted
                }

                DeskComponents.UsageBar {
                    Layout.fillWidth: true
                    progress: Desk.DeskStatsService.memoryFraction
                }

                Item { Layout.fillHeight: true }
            }
        }
    }

    DashComponents.Card {
        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: 10

        ColumnLayout {
            anchors.fill: parent
            spacing: 6

            Text {
                text: "Network"
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Desk.DeskTheme.text
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Text {
                    text: "󰇚 " + Desk.DeskStatsService.rate(Desk.DeskStatsService.networkDown)
                    font.family: Desk.DeskTheme.fontMono
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.text
                }
                Text {
                    text: "󰕒 " + Desk.DeskStatsService.rate(Desk.DeskStatsService.networkUp)
                    font.family: Desk.DeskTheme.fontMono
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.text
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: Desk.DeskStatsService.temperature !== null
                    text: Desk.DeskStatsService.thermalWord
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.textMuted
                }
                Text {
                    text: "Up " + Desk.DeskStatsService.duration(Desk.DeskStatsService.uptime)
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.textMuted
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                DeskComponents.Sparkline {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    values: Desk.DeskStatsService.downHistory
                    stroke: Desk.DeskTheme.blue
                }
                DeskComponents.Sparkline {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    values: Desk.DeskStatsService.upHistory
                    stroke: Desk.DeskTheme.green
                }
            }
        }
    }
}
