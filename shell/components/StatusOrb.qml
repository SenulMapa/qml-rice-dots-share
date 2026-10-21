pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

/**
 * StatusOrb -- Wi-Fi + Bluetooth + Battery in one 42px glyph (greeter/lock design,
 * Figma "Levels"). Pure data-in: bind it to services/ConnectivityStatus or
 * feed fake values from a preview.
 *
 *   ring   -- battery charge on machines with a battery (red at <=15%, blue-ish while
 *             charging), otherwise Bluetooth signal of the strongest connected device;
 *             a 270deg arc open at the bottom. Hidden when Bluetooth is off on desktop,
 *             dim track only when on with nothing paired.
 *   centre -- Wi-Fi: dot + three arcs, each arc lights up as the signal
 *             crosses 1/4, 2/4, 3/4. Wired-only shows a "lan" glyph instead;
 *             nothing at all shows a dim crossed-out dot.
 *   dots   -- connected Bluetooth devices, up to 4, sitting in the ring's gap.
 */
Item {
    id: root
    implicitWidth: 42
    implicitHeight: 42

    property real wifiStrength: -1     // 0..1, -1 = not on Wi-Fi
    property bool ethernet: false
    property bool btEnabled: false
    property real btSignal: 0          // 0..1
    property int btDevices: 0          // clamped to 0..4

    property real batteryLevel: -1     // 0..1, -1 = no battery (desktop): ring stays Bluetooth
    property bool charging: false
    property color lowColor: "#ff5a52"
    property color chargingColor: "#7fd7ff"
    readonly property bool batteryMode: batteryLevel >= 0

    property color ringColor: "#3ee05a"
    property color dotColor: "#2f8fd8"

    readonly property real _s: width / 42
    property real _bt: Math.max(0, Math.min(1, btSignal))
    Behavior on _bt { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    property real _bat: Math.max(0, Math.min(1, batteryLevel))
    Behavior on _bat { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

    // ---- Battery/Bluetooth ring ----
    Shape {
        anchors.fill: parent
        visible: root.batteryMode || root.btEnabled
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: Qt.rgba(1, 1, 1, 0.14)
            strokeWidth: 3 * root._s
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root.width / 2 - 2 * root._s; radiusY: radiusX
                startAngle: 135; sweepAngle: 270
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.batteryMode ? (root.charging ? root.chargingColor : (root._bat <= 0.15 ? root.lowColor : root.ringColor)) : (root._bt > 0.001 ? root.ringColor : "transparent")
            strokeWidth: 3 * root._s
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: root.width / 2 - 2 * root._s; radiusY: radiusX
                startAngle: 135; sweepAngle: 270 * (root.batteryMode ? root._bat : root._bt)
            }
        }
    }

    // ---- Wi-Fi glyph: dot + 3 arcs fanning up from a point below centre ----
    Shape {
        id: wifi
        anchors.fill: parent
        visible: root.wifiStrength >= 0
        preferredRendererType: Shape.CurveRenderer

        readonly property real cx: root.width / 2
        readonly property real cy: root.height * 0.62

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.wifiStrength > 0.24 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.25)
            strokeWidth: 2.2 * root._s
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: wifi.cx; centerY: wifi.cy
                radiusX: 4.2 * root._s; radiusY: radiusX
                startAngle: 225; sweepAngle: 90
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.wifiStrength > 0.49 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.25)
            strokeWidth: 2.2 * root._s
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: wifi.cx; centerY: wifi.cy
                radiusX: 7.8 * root._s; radiusY: radiusX
                startAngle: 225; sweepAngle: 90
            }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: root.wifiStrength > 0.74 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.25)
            strokeWidth: 2.2 * root._s
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: wifi.cx; centerY: wifi.cy
                radiusX: 11.4 * root._s; radiusY: radiusX
                startAngle: 225; sweepAngle: 90
            }
        }
    }

    Rectangle {
        visible: root.wifiStrength >= 0 || (!root.ethernet)
        width: 3.2 * root._s; height: width; radius: width / 2
        x: wifi.cx - width / 2; y: wifi.cy - height / 2
        color: root.wifiStrength >= 0 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.3)
    }

    // ---- Wired-only ----
    Text {
        anchors.centerIn: parent
        visible: root.wifiStrength < 0 && root.ethernet
        text: "lan"
        font.family: "Material Symbols Rounded"
        font.pixelSize: 17 * root._s
        color: "#ffffff"
    }

    // ---- Connected Bluetooth devices, in the ring's bottom gap ----
    Repeater {
        model: 4
        delegate: Rectangle {
            required property int index
            // Spread across the 90deg gap (45..135deg, y-down), on the ring.
            readonly property real a: (60 + index * 20) * Math.PI / 180
            readonly property real r: root.width / 2 + 1.5 * root._s
            width: 4.5 * root._s; height: width; radius: width / 2
            x: root.width / 2 + Math.cos(a) * r - width / 2
            y: root.height / 2 + Math.sin(a) * r - height / 2
            visible: root.btEnabled
            color: (3 - index) < Math.min(4, root.btDevices) ? root.dotColor : Qt.rgba(1, 1, 1, 0.12)
        }
    }
}
