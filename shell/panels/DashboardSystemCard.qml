import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

DashboardCard {
    id: root

    signal pageRequested()
    readonly property color systemAccent: SystemService.cpuPercent >= 90
        || SystemService.memoryPercent >= 90 ? Theme.error : Theme.tertiary

    accent: systemAccent
    onActivated: root.pageRequested()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space3
        spacing: Theme.space2

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "󰍛"
                color: root.systemAccent
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 18
            }
            Text {
                Layout.fillWidth: true
                text: "SYSTEM"
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 9
                font.letterSpacing: 1
            }
            Text {
                text: "Details  ›"
                color: root.systemAccent
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.dashCaption
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.space2

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "CPU"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 10
                }
                Text {
                    text: SystemService.cpuPercent + "%"
                    color: AdaptiveColor.glassText
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
            }
            LevelTrack {
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                value: SystemService.cpuUsage
                accent: SystemService.cpuPercent >= 90 ? Theme.error : AdaptiveColor.activeFill
            }
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "MEMORY"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 10
                }
                Text {
                    text: SystemService.memoryPercent + "%"
                    color: AdaptiveColor.glassText
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
            }
            LevelTrack {
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                value: SystemService.memoryUsage
                accent: SystemService.memoryPercent >= 90 ? Theme.error : Theme.tertiary
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.space3
                rowSpacing: Theme.space1

                MetricValue {
                    Layout.fillWidth: true
                    label: "STORAGE"
                    value: SystemService.storageAvailable
                        ? SystemService.diskPercent + "%" : "—"
                    accent: SystemService.diskPercent >= 90
                        ? Theme.error : Theme.secondary
                }
                MetricValue {
                    Layout.fillWidth: true
                    label: "CPU TEMP"
                    value: SystemService.temperatureAvailable
                        ? SystemService.temperatureInt + "°C" : "—"
                    accent: SystemService.temperatureInt >= 90
                        ? Theme.error : Theme.warning
                }
                MetricValue {
                    Layout.fillWidth: true
                    label: "GPU LOAD"
                    value: SystemService.gpuUsageAvailable
                        ? SystemService.gpuPercent + "%" : "—"
                    accent: SystemService.gpuPercent >= 90
                        ? Theme.error : Theme.secondary
                }
                MetricValue {
                    Layout.fillWidth: true
                    label: "GPU TEMP"
                    value: SystemService.gpuTemperatureAvailable
                        ? SystemService.gpuTemperatureInt + "°C" : "—"
                    accent: SystemService.gpuTemperatureInt >= 90
                        ? Theme.error : Theme.tertiary
                }
            }
            Item { Layout.fillHeight: true }
            Text {
                Layout.fillWidth: true
                text: "UPTIME  " + SystemService.uptimeLabel
                color: AdaptiveColor.glassTextDim
                elide: Text.ElideRight
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 9
            }
        }
    }

    component MetricValue: RowLayout {
        id: metric
        property string label: ""
        property string value: "—"
        property color accent: AdaptiveColor.activeFill
        spacing: Theme.space1

        Text {
            Layout.fillWidth: true
            text: metric.label
            color: AdaptiveColor.glassTextDim
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: 9
            font.letterSpacing: 0.5
        }
        Text {
            text: metric.value
            color: metric.accent
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
        }
    }
}
