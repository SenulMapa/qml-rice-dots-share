import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell.Io
import "../components"
import "../core"
import "../services"

Item {
    id: root

    // Set by the island host: sampling and the process poll run only while
    // this page is the one on screen.
    property bool active: true

    readonly property bool ink: Config.appearance.ink
    readonly property int historyLength: 10

    // Sparkline history, newest last, each value 0..1. Replaced wholesale on
    // every sample so the bindings in the ink layout re-run.
    property var history: ({ cpu: [], gpu: [], ram: [], temp: [] })
    // Top three processes: [{ name, cpu, memory }], from `top`.
    property var topProcesses: []

    readonly property var stats: [
        { key: "cpu", label: "CPU", value: SystemService.cpuPercent + "%", unit: "" },
        { key: "gpu", label: "GPU",
            value: SystemService.gpuUsageAvailable ? SystemService.gpuPercent + "%" : "—",
            unit: "" },
        { key: "ram", label: "RAM",
            value: (SystemService.memoryUsedBytes / 1073741824).toFixed(1), unit: "GB" },
        { key: "temp", label: "Temp",
            value: SystemService.temperatureAvailable ? SystemService.temperatureInt + "°" : "—",
            unit: "" }
    ]

    function pushSample(series, value): var {
        const next = series.slice(-(root.historyLength - 1))
        next.push(value)
        return next
    }

    function takeSample(): void {
        const h = root.history
        root.history = {
            cpu: pushSample(h.cpu, SystemService.cpuUsage),
            gpu: SystemService.gpuUsageAvailable
                ? pushSample(h.gpu, SystemService.gpuUsage) : h.gpu,
            ram: pushSample(h.ram, SystemService.memoryUsage),
            temp: SystemService.temperatureAvailable
                ? pushSample(h.temp, Math.max(0, Math.min(1, SystemService.temperature / 100)))
                : h.temp
        }
    }

    // Points for a polyline across w x h. Newest sample sits at the right
    // edge; a short history is right-aligned so the line always grows in.
    function sparkline(values, w, h): var {
        const points = []
        const count = values.length
        if (count < 2)
            return points
        for (let index = 0; index < count; index++) {
            const x = (root.historyLength - count + index) / (root.historyLength - 1) * w
            const v = Math.max(0, Math.min(1, values[index]))
            points.push(Qt.point(x, (h - 1) - v * (h - 2)))
        }
        return points
    }

    // `top` prints RES as "412m", "1.8g" or a bare KiB count.
    function formatResident(text): string {
        const match = /^([\d.]+)([kmgt]?)$/i.exec(text || "")
        if (!match)
            return "—"
        const value = Number(match[1])
        const unit = match[2].toLowerCase()
        const kib = unit === "t" ? value * 1073741824
            : unit === "g" ? value * 1048576
            : unit === "m" ? value * 1024 : value
        const mib = kib / 1024
        return mib >= 1024 ? (mib / 1024).toFixed(1) + " GB" : Math.round(mib) + " MB"
    }

    // Two iterations: the first block is top's own since-start average, so
    // only the last block (live %CPU over the one-second gap) is read.
    function parseTop(text): var {
        const lines = text.split("\n")
        let start = -1
        for (let index = 0; index < lines.length; index++) {
            if (/^\s*PID\s/.test(lines[index]))
                start = index
        }
        const rows = []
        if (start < 0)
            return rows
        for (let index = start + 1; index < lines.length && rows.length < 3; index++) {
            const fields = lines[index].trim().split(/\s+/)
            if (fields.length < 12)
                continue
            rows.push({
                name: fields.slice(11).join(" "),
                cpu: Number(fields[8]),
                memory: root.formatResident(fields[5])
            })
        }
        return rows
    }

    Timer {
        id: sampler
        interval: Config.system.metricsInterval
        running: root.ink && root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: root.takeSample()
    }

    // No process listing exists in services/, so this is the only poll the
    // ink page adds, and it stops with the page.
    Process {
        id: topQuery
        command: ["top", "-b", "-n", "2", "-d", "1", "-o", "%CPU", "-w", "200"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.topProcesses = root.parseTop(text)
        }
    }

    Timer {
        id: processTimer
        interval: 3000
        running: root.ink && root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!topQuery.running)
                topQuery.running = true
        }
    }

    // Ink compact page (showcase screens/system.html, 560 wide): four serif
    // readouts with sparklines, then the top three processes.
    // 32px showcase padding, less the host's Theme.space4 inset.
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Math.max(0, 32 - Theme.space4)
        visible: root.ink
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 8

            Text {
                text: "󰍛"
                color: Theme.t1
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 18
            }
            Text {
                text: "System"
                color: Theme.t1
                font.family: Theme.fontUi
                font.pixelSize: 20
                font.weight: Font.DemiBold
                font.letterSpacing: -0.3
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.topMargin: 24
            columns: 4
            columnSpacing: 16
            rowSpacing: 0

            Repeater {
                model: root.stats
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: modelData.label
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                    }
                    RowLayout {
                        Layout.topMargin: 8
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            text: modelData.value
                            color: Theme.t1
                            elide: Text.ElideRight
                            font.family: Theme.fontSerif
                            font.pixelSize: 44
                            font.letterSpacing: -0.9
                            lineHeight: 44
                            lineHeightMode: Text.FixedHeight
                        }
                        Text {
                            Layout.alignment: Qt.AlignBaseline
                            visible: modelData.unit.length > 0
                            text: modelData.unit
                            color: Theme.t2
                            font.family: Theme.fontUi
                            font.pixelSize: 14
                        }
                    }
                    Shape {
                        id: spark
                        Layout.fillWidth: true
                        Layout.preferredHeight: 24
                        Layout.topMargin: 12
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: Theme.t2
                            strokeWidth: 1.5
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            PathPolyline {
                                path: root.sparkline(root.history[modelData.key],
                                    spark.width, spark.height)
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.topMargin: 32
            Layout.preferredHeight: 18
            text: "Top processes"
            color: Theme.t1
            font.family: Theme.fontUi
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }

        // Header and rows share one column recipe: name fills, CPU 64, memory 80.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 16
            Layout.preferredHeight: 24
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: "Name"
                color: Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 12
            }
            Text {
                Layout.preferredWidth: 64
                horizontalAlignment: Text.AlignRight
                text: "CPU"
                color: Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 12
            }
            Text {
                Layout.preferredWidth: 80
                horizontalAlignment: Text.AlignRight
                text: "Memory"
                color: Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 12
            }
        }

        Repeater {
            model: root.topProcesses
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: modelData.name
                    color: Theme.t1
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }
                Text {
                    Layout.preferredWidth: 64
                    horizontalAlignment: Text.AlignRight
                    text: modelData.cpu.toFixed(1) + "%"
                    color: Theme.t2
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }
                Text {
                    Layout.preferredWidth: 80
                    horizontalAlignment: Text.AlignRight
                    text: modelData.memory
                    color: Theme.t1
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space3
        visible: !root.ink

        ColumnLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            spacing: 0

            Text {
                text: "System overview"
                color: AdaptiveColor.glassText
                font.family: Config.appearance.displayFontFamily
                font.pixelSize: Theme.textTitle + 6
                font.weight: Font.Normal
            }
            Text {
                text: "Live system health"
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.fontFamily
                font.pixelSize: 9
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            rows: 3
            columnSpacing: Theme.space3
            rowSpacing: Theme.space3

            SystemMetricCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "Processor"
                value: SystemService.cpuPercent + "%"
                valueFontSize: Theme.textSmall
                detail: "Current CPU load"
                icon: "󰘚"
                level: SystemService.cpuUsage
                accent: SystemService.cpuPercent >= 90
                    ? Theme.error : AdaptiveColor.activeFill
            }

            SystemMetricCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "Memory"
                value: SystemService.memoryPercent + "%"
                valueFontSize: Theme.textSmall
                detail: SystemService.memoryLabel
                icon: "󰍛"
                level: SystemService.memoryUsage
                accent: SystemService.memoryPercent >= 90
                    ? Theme.error : Theme.tertiary
            }

            SystemMetricCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "Storage"
                value: SystemService.storageAvailable
                    ? SystemService.diskPercent + "%" : "Unavailable"
                valueFontSize: Theme.textSmall
                detail: SystemService.diskLabel
                icon: "󰋊"
                level: SystemService.diskUsage
                accent: SystemService.diskPercent >= 90
                    ? Theme.error : Theme.secondary
            }

            SystemMetricCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "CPU temperature"
                value: SystemService.temperatureAvailable
                    ? SystemService.temperatureInt + "°C" : "Unavailable"
                valueFontSize: Theme.textSmall
                detail: SystemService.temperatureAvailable
                    ? "Processor package sensor" : "No readable sensor"
                icon: "󰔏"
                level: SystemService.temperatureAvailable
                    ? Math.max(0, Math.min(1,
                        SystemService.temperature / 100)) : 0
                accent: SystemService.temperatureInt >= 90
                    ? Theme.error : Theme.warning
            }

            SystemMetricCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "GPU load"
                value: SystemService.gpuUsageAvailable
                    ? SystemService.gpuPercent + "%" : "Unavailable"
                detail: SystemService.gpuUsageAvailable
                    ? "Current graphics load" : "No readable load sensor"
                icon: "󰢮"
                level: SystemService.gpuUsage
                accent: SystemService.gpuPercent >= 90
                    ? Theme.error : Theme.secondary
                valueFontSize: Theme.textSmall
            }

            SystemMetricCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: "GPU temperature"
                value: SystemService.gpuTemperatureAvailable
                    ? SystemService.gpuTemperatureInt + "°C" : "Unavailable"
                detail: SystemService.gpuTemperatureAvailable
                    ? "Graphics edge sensor" : "No readable temperature sensor"
                icon: "󰔏"
                level: SystemService.gpuTemperatureAvailable
                    ? Math.max(0, Math.min(1,
                        SystemService.gpuTemperature / 100)) : 0
                accent: SystemService.gpuTemperatureInt >= 90
                    ? Theme.error : Theme.tertiary
                valueFontSize: Theme.textSmall
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 98

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space4
                spacing: Theme.space3

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    SystemInfoRow {
                        Layout.fillWidth: true
                        label: "CPU"
                        value: SystemService.cpuModel
                        accent: AdaptiveColor.activeFill
                    }
                    SystemInfoRow {
                        Layout.fillWidth: true
                        label: "GPU"
                        value: SystemService.gpuModel
                        accent: Theme.tertiary
                    }
                    SystemInfoRow {
                        Layout.fillWidth: true
                        label: "OS"
                        value: SystemService.osName
                        accent: Theme.secondary
                    }
                    SystemInfoRow {
                        Layout.fillWidth: true
                        label: "UPTIME"
                        value: SystemService.uptimeLabel
                        accent: Theme.warning
                    }
                }
            }
        }
    }
}
