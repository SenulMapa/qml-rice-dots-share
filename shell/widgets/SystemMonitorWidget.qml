// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

/**
 * SystemMonitorWidget -- CPU/memory/disk/temp readout, backed by
 * services/SystemMonitorService.qml (see that file's header -- ii has no
 * single equivalent singleton to port from). Flat/no-card style: thin 3px
 * tracks instead of a bordered/filled card -- these aren't a "card
 * background", just a value indicator, same spirit as BatteryRingWidget's
 * ring.
 *
 * Laid out as a Column of evenly-spaced rows sized from Layout.fillHeight
 * (not fixed pixel gaps) -- the previous version put every row inside a
 * ColumnLayout with a fixed spacing, which read fine for 2 rows but left a
 * huge dead gap once only CPU/MEM existed at a widget height sized for
 * more content. Label text also moved up from textSmall to textBody --
 * at the widget's default 2x2 (176x176) footprint, textSmall labels were
 * barely legible.
 */
Item {
    id: root

    readonly property var rows: [
        { label: "CPU", value: SystemMonitorService.cpuPercent, suffix: "%",
            visible: true },
        { label: "MEM", value: SystemMonitorService.memPercent, suffix: "%",
            visible: true },
        { label: "DISK", value: SystemMonitorService.diskPercent, suffix: "%",
            visible: true },
        { label: "TEMP", value: SystemMonitorService.tempCelsius, suffix: "°C",
            visible: SystemMonitorService.tempAvailable, isTemp: true }
    ]
    readonly property var visibleRows: root.rows.filter(r => r.visible)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space3
        spacing: 0

        Repeater {
            model: root.visibleRows

            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.space1

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: parent.parent.modelData.label
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Theme.textBody
                        color: Theme.surfaceVariantText
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: (parent.parent.modelData.isTemp
                            ? parent.parent.modelData.value.toFixed(0)
                            : Math.round(parent.parent.modelData.value))
                            + parent.parent.modelData.suffix
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Theme.textBody
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 3

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Theme.outlineVariant
                    }
                    Rectangle {
                        // Temperature has no natural 0-100 scale like the
                        // other rows -- 100C is a hot-but-plausible ceiling
                        // for a consumer CPU, so it doubles as this track's
                        // upper bound purely for a sane-looking fill.
                        readonly property var row: parent.parent.modelData
                        width: parent.width * Math.max(0, Math.min(1, row.value / 100))
                        height: parent.height
                        radius: height / 2
                        color: Theme.primary
                    }
                }
            }
        }
    }
}
