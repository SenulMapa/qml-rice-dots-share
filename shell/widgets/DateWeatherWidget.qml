// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import "../core"
import "../services"
import "../components"

/**
 * DateWeatherWidget -- Pixel "at a glance": date + weather condition inside
 * a soft pill container. WeatherService already refreshes/caches itself on
 * its own interval (see Config.weather.refreshInterval); this widget only
 * re-reads its properties, plus a minute-aligned date refresh for the day
 * rolling over at midnight.
 */
Item {
    id: root

    property date now: new Date()
    readonly property string dateLabel: Qt.formatDate(root.now, "dddd, d MMM")

    Squircle {
        anchors.fill: parent
        radius: Theme.radiusFor(height)
        color: Theme.surfaceContainerHigh
    }

    Column {
        anchors.fill: parent
        anchors.margins: Theme.space4
        spacing: Theme.space2

        Text {
            width: parent.width
            text: root.dateLabel
            elide: Text.ElideRight
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textBody
            font.weight: Font.DemiBold
            color: Theme.surfaceText
        }

        Row {
            spacing: Theme.space2
            visible: WeatherService.available

            Text {
                text: WeatherService.icon
                font.pixelSize: Theme.textTitle
                color: Theme.primary
            }
            Text {
                text: WeatherService.temperatureLabel
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textTitle
                font.weight: Font.Bold
                color: Theme.surfaceText
            }
        }

        Text {
            visible: !WeatherService.available
            text: WeatherService.statusLabel
            width: parent.width
            elide: Text.ElideRight
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textSmall
            color: Theme.surfaceVariantText
        }

        Text {
            visible: WeatherService.available
            text: WeatherService.condition
            width: parent.width
            elide: Text.ElideRight
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textSmall
            color: Theme.surfaceVariantText
        }
    }

    // Only needs to notice the day changing (midnight rollover); minute
    // alignment is cheap and shared in spirit with ShapeClockWidget.
    Timer {
        running: true
        repeat: false
        interval: Math.max(250, 60000 - (Date.now() % 60000))
        onTriggered: { root.now = new Date(); dayTimer.start() }
    }
    Timer {
        id: dayTimer
        interval: 60000
        repeat: true
        running: false
        onTriggered: root.now = new Date()
    }
}
