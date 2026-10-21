// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import "../core"

/**
 * AnalogClockWidget -- hour/minute/second hands on a bare dial, ported from
 * end4-ii's background/widgets/clock/{HourHand,MinuteHand,SecondHand,
 * minuteMarks/Dots}.qml. Flattened relative to ii's version: no
 * hollow/classic/bold hand-style config surface (ii exposed several --
 * this keeps one calm look), no per-second RotationAnimation (ii's own
 * comment on SecondHand.qml notes "animating every second is expensive" --
 * this shell already treats that as a hard no, see ShapeClockWidget's
 * minute-aligned timer), and per this port's flat/no-card-background rule,
 * NO dial circle -- just the 12 tick dots and three hands directly on the
 * desktop, exactly like ShapeClockWidget's minute-boundary-only update
 * pattern below.
 */
Item {
    id: root

    property date now: new Date()
    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real dialRadius: Math.min(width, height) / 2

    // 12 tick dots -- ii's Dots.qml, ported directly (a Repeater rotated
    // per-index rather than trig'd per-item).
    Repeater {
        model: 12
        Item {
            required property int index
            anchors.fill: parent
            rotation: 360 / 12 * index
            Rectangle {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: 4
                }
                width: root.dialRadius * 0.06
                height: width
                radius: width / 2
                color: Theme.outlineVariant
            }
        }
    }

    // Hour hand
    Item {
        anchors.fill: parent
        rotation: -90 + (360 / 12) * (root.now.getHours() % 12 + root.now.getMinutes() / 60)
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width / 2
            width: root.dialRadius * 0.55
            height: root.dialRadius * 0.09
            radius: height / 2
            color: Theme.surfaceText
        }
    }

    // Minute hand
    Item {
        anchors.fill: parent
        rotation: -90 + (360 / 60) * root.now.getMinutes()
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width / 2
            width: root.dialRadius * 0.78
            height: root.dialRadius * 0.06
            radius: height / 2
            color: Theme.surfaceText
        }
    }

    // Second hand -- thin, tinted with the accent so it reads as the "live"
    // element without a per-frame animation cost (updates once/second via
    // the Timer below only).
    Item {
        anchors.fill: parent
        rotation: -90 + (360 / 60) * root.now.getSeconds()
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: parent.width / 2
            width: root.dialRadius * 0.82
            height: Math.max(1.5, root.dialRadius * 0.02)
            radius: height / 2
            color: Theme.primary
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: root.dialRadius * 0.1
        height: width
        radius: width / 2
        color: Theme.primary
    }

    Timer {
        running: true
        repeat: true
        interval: 1000
        onTriggered: root.now = new Date()
    }
}
