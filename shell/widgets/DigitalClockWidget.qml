// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import "../core"

/**
 * DigitalClockWidget -- plain big-digit time + date, ported from end4-ii's
 * background/widgets/clock/DigitalClock.qml. Dropped relative to ii's
 * version: the vertical/split-line layout option (its "isVertical" mode),
 * the quote line (CookieQuote is a separate skip, see the port report),
 * and any card/pill background -- this port's flat/no-card rule, unlike
 * ShapeClockWidget's cookie shape, which is the OTHER (already-shipped)
 * clock type and stays untouched.
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
    readonly property string dateLabel: Qt.formatDate(root.now, "dddd, d MMM")

    Column {
        anchors.centerIn: parent
        spacing: -Theme.space1

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.space2

            Text {
                text: root.hourLabel + ":" + root.minuteLabel
                font.family: Config.appearance.clockFontFamily
                font.pixelSize: Math.round(Math.min(root.width, root.height) * 0.32)
                font.weight: Config.appearance.clockFontWeight
                color: Theme.surfaceText
            }
            Text {
                visible: root.meridiem.length > 0
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.space2
                text: root.meridiem
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textBody
                color: Theme.surfaceVariantText
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateLabel
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textSmall
            color: Theme.surfaceVariantText
        }
    }

    Timer {
        running: true
        repeat: false
        interval: Math.max(250, 60000 - (Date.now() % 60000))
        onTriggered: { root.now = new Date(); minuteTimer.start() }
    }
    Timer {
        id: minuteTimer
        interval: 60000
        repeat: true
        running: false
        onTriggered: root.now = new Date()
    }
}
