// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import "../core"

/**
 * ShapeClockWidget -- the Pixel "at a glance" clock: big bold time inside a
 * Material cookie shape. Updates on a MINUTE boundary only (never
 * per-second) via a single-shot alignment timer followed by a 60s repeat --
 * costs nothing at idle beyond one wakeup/minute.
 */
Item {
    id: root

    property date now: new Date()

    readonly property int hour24: now.getHours()
    readonly property int hour12: {
        const h = hour24 % 12
        return h === 0 ? 12 : h
    }
    readonly property string minuteLabel: now.getMinutes().toString().padStart(2, "0")
    readonly property string hourLabel: (Config.appearance.use24HourClock
        ? hour24 : hour12).toString().padStart(
            Config.appearance.use24HourClock ? 2 : 1, "0")
    readonly property string meridiem: Config.appearance.use24HourClock
        ? "" : (hour24 >= 12 ? "PM" : "AM")

    CookieShape {
        id: cookie
        anchors.fill: parent
        sides: 9
        amplitude: 0.10
        fillColor: Theme.primaryContainer
    }

    Column {
        anchors.centerIn: parent
        spacing: -Theme.space1

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.hourLabel + ":" + root.minuteLabel
            font.family: Config.appearance.clockFontFamily
            font.pixelSize: Math.round(Math.min(cookie.width, cookie.height) * 0.24)
            font.weight: Config.appearance.clockFontWeight
            color: Theme.primaryContainerText
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.meridiem.length > 0
            text: root.meridiem
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textSmall
            font.letterSpacing: Theme.trackMicro * Theme.textSmall
            color: Theme.primaryContainerText
            opacity: 0.8
        }
    }

    // Fires once at the next wall-clock minute boundary, then every 60s on
    // the beat -- see WidgetHost.qml's PerformanceService gate for why this
    // is the only timer running per clock instance.
    Timer {
        id: aligner
        running: true
        repeat: false
        interval: Math.max(250, 60000 - (Date.now() % 60000))
        onTriggered: {
            root.now = new Date()
            minuteTimer.start()
        }
    }
    Timer {
        id: minuteTimer
        interval: 60000
        repeat: true
        running: false
        onTriggered: root.now = new Date()
    }
}
