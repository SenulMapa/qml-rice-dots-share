// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   D   I   A   L                                                          │
// │   analogue clock dial                                                    │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../services" as DeskServices


// A clock face: twelve marks (every third one long), two hands, and an accent
// seconds hand when seconds are enabled. The large size adds minute marks, four
// numerals and a date window at three o'clock.
//
// Each hand is a dial-sized item rotated about its centre, with the hand drawn
// up from the middle, so the pivot is always the dial's centre.
Item {
    id: root

    property var ink: DeskServices.DeskDesktopService.inkFor(null)
    property real size: 150
    property bool numerals: false
    property bool minuteTicks: false
    property bool dateWindow: false

    // Seconds cost sixty times the repaints, so the hand only exists when
    // enabled.
    // Ink (DeskTheme.inkMode) draws the ink dial: 60 ticks, a serif 12 at the
    // top, and a live seconds hand, whatever the seconds setting says.
    readonly property bool inked: DeskServices.DeskTheme.inkMode
    readonly property bool seconds: DeskServices.DeskSettings.clockShowsSeconds || root.inked
    readonly property date now: clock.date
    readonly property real r: root.size / 2

    width: root.size
    height: root.size

    SystemClock {
        id: clock
        precision: root.seconds ? SystemClock.Seconds : SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.inked
        radius: width / 2
        color: "transparent"
        border.color: root.ink.dim
        border.width: 1
    }

    Repeater {
        model: root.minuteTicks || root.inked ? 60 : 12

        Item {
            id: tick

            required property int index

            readonly property bool hour: root.minuteTicks || root.inked
                ? tick.index % 5 === 0 : true
            readonly property bool quarter: root.minuteTicks
                ? tick.index % 15 === 0 : tick.index % 3 === 0

            anchors.fill: parent
            rotation: tick.index * (root.minuteTicks || root.inked ? 6 : 30)

            // Ink: ticks sit on the rim, hours at 0.9 white and 2px, minutes
            // at 0.26 white and 1px, both 60 around.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.inked ? root.r * 0.239 : root.r * 0.08
                width: root.inked ? (tick.hour ? 2 : 1)
                    : (tick.quarter ? 3 : (tick.hour ? 2 : 1))
                height: root.inked ? (tick.hour ? root.r * 0.09 : root.r * 0.026)
                    : (tick.quarter ? root.r * 0.16 : (tick.hour ? root.r * 0.09 : root.r * 0.045))
                radius: width / 2
                color: root.inked ? (tick.hour ? Qt.rgba(1, 1, 1, 0.9) : Qt.rgba(1, 1, 1, 0.26))
                    : (tick.quarter ? root.ink.text : root.ink.muted)
            }
        }
    }

    // Ink: the only numeral on the dial is a serif 12 at the top.
    Text {
        visible: root.inked
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.r - root.r * 0.542 - height / 2
        text: "12"
        font.family: DeskServices.DeskTheme.fontNumeral
        font.pixelSize: Math.max(10, root.r * 0.142)
        color: Qt.rgba(1, 1, 1, 0.9)
    }

    Repeater {
        model: root.numerals && !root.inked ? [[12, 0], [3, 90], [6, 180], [9, 270]] : []

        Text {
            required property var modelData

            readonly property real angle: (modelData[1] - 90) * Math.PI / 180

            x: root.r + root.r * 0.72 * Math.cos(angle) - width / 2
            y: root.r + root.r * 0.72 * Math.sin(angle) - height / 2
            text: `${modelData[0]}`
            font.family: DeskServices.DeskTheme.fontFamily
            font.pixelSize: DeskServices.DeskTheme.fontSizeLarge
            font.weight: Font.DemiBold
            color: root.ink.text
        }
    }

    // The date, in a window at three o'clock.
    Paper {
        visible: root.dateWindow && !root.inked
        ink: root.ink
        radius: 3
        x: root.r + root.r * 0.5 - width / 2
        y: root.r - height / 2
        width: 26
        height: 22

        Text {
            anchors.centerIn: parent
            text: `${root.now.getDate()}`
            font.family: DeskServices.DeskTheme.fontFamily
            font.pixelSize: DeskServices.DeskTheme.fontSizeMedium
            font.weight: Font.DemiBold
            color: DeskServices.DeskTheme.paperInk
        }
    }

    Item {
        anchors.fill: parent
        rotation: (root.now.getHours() % 12) * 30 + root.now.getMinutes() * 0.5

        // Ink: 4px, rounded, from a 0.065r tail to 0.4r.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.inked ? root.r - root.r * 0.4 : parent.height / 2 - height
            width: root.inked ? 4 : Math.max(4, root.r * 0.07)
            height: root.inked ? root.r * 0.465 : root.r * 0.52
            radius: width / 2
            color: root.ink.text
        }
    }

    Item {
        anchors.fill: parent
        rotation: root.now.getMinutes() * 6 + root.now.getSeconds() * 0.1

        // Ink: 2.5px, rounded, from a 0.077r tail to 0.619r.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.inked ? root.r - root.r * 0.619 : parent.height / 2 - height
            width: root.inked ? 2.5 : Math.max(3, root.r * 0.045)
            height: root.inked ? root.r * 0.696 : root.r * 0.74
            radius: width / 2
            color: root.ink.text
        }
    }

    Item {
        visible: root.seconds
        anchors.fill: parent
        rotation: root.now.getSeconds() * 6

        // Ink: 1px semantic red, from a 0.09r tail to 0.671r.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.inked ? root.r - root.r * 0.671 : parent.height / 2 - root.r * 0.82
            width: root.inked ? 1 : 1.5
            height: root.inked ? root.r * 0.761 : root.r * 0.82 + root.r * 0.18
            color: root.inked ? DeskServices.DeskTheme.red : root.ink.accent
        }
    }

    // Ink: a 6px centre dot. Off ink, the sized dot and the accent pin.
    Rectangle {
        anchors.centerIn: parent
        width: root.inked ? 6 : Math.max(6, root.r * 0.1)
        height: width
        radius: width / 2
        color: root.ink.text
    }

    Rectangle {
        anchors.centerIn: parent
        visible: root.seconds && !root.inked
        width: Math.max(2, root.r * 0.04)
        height: width
        radius: width / 2
        color: root.ink.accent
    }
}
