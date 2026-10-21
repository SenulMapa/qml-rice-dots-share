// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import QtQuick.Shapes
import "../core"
import "../services"

/**
 * BatteryRingWidget -- a static Material ring (PathAngleArc) reading
 * BatteryService.percentage. Only ever loaded when BatteryService.available
 * (see services/WidgetStore.qml's requiresBattery gate + WidgetHost.qml),
 * so a desktop machine never pays for this widget existing in the registry.
 * The arc angle is a plain binding, not an animation -- it only repaints
 * when the percentage itself changes (UPower push updates, not a timer).
 */
Item {
    id: root

    readonly property real sweep: 360 * Math.max(0, Math.min(1, BatteryService.percentage))

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: Math.round(Math.min(root.width, root.height) * 0.09)
            strokeColor: Theme.surfaceContainerHigh
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width / 2 - 8
                radiusY: root.height / 2 - 8
                startAngle: -90
                sweepAngle: 359.999
            }
        }
        ShapePath {
            strokeWidth: Math.round(Math.min(root.width, root.height) * 0.09)
            strokeColor: BatteryService.charging ? Theme.success : Theme.primary
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.width / 2 - 8
                radiusY: root.height / 2 - 8
                startAngle: -90
                sweepAngle: root.sweep
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: BatteryService.percentageInt + "%"
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textTitle
            font.weight: Font.Bold
            color: Theme.surfaceText
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: BatteryService.sourceLabel
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textSmall
            color: Theme.surfaceVariantText
        }
    }
}
