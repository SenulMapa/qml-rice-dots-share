import QtQuick
import QtQuick.Layouts
import "../core"
import "../components"

/**
 * MacWidgetWeather -- the medium weather widget (spec 3.3: 343 x 163, fill
 * #66829B). Reads WeatherService (or a stand-in with the same members).
 */
Item {
    id: root

    required property var weather
    property string city: Config.weather.locationName

    width: MacTokens.s(MacTokens.ncWeatherWidth)
    height: MacTokens.s(MacTokens.ncWeatherHeight)

    TahoeSurface {
        anchors.fill: parent
        kind: "nc"
        radius: MacTokens.s(MacTokens.ncWidgetRadius)
        tintAlpha: MacTokens.frostTintAlpha
        fill: MacTokens.ncWeatherFrost
    }

    // No forecast yet (offline, or still loading): say so, in the widget.
    Text {
        anchors.centerIn: parent
        visible: !root.weather.available
        text: root.weather.statusLabel
        color: MacTokens.onGlassPrimary
        font.family: MacTokens.textFamily
        font.pixelSize: MacTokens.s(MacTokens.ncWeatherConditionSize)
        font.weight: Font.DemiBold
    }

    readonly property real pad: MacTokens.s(MacTokens.bannerPad)

    Text {
        id: cityText
        x: root.pad
        y: MacTokens.s(MacTokens.ncWeatherTopPad)
        text: root.city
        color: MacTokens.onGlassPrimary
        font.family: MacTokens.textFamily
        font.pixelSize: MacTokens.s(MacTokens.ncWeatherCitySize)
        font.weight: Font.DemiBold
    }

    Text {
        id: tempText
        visible: root.weather.available
        x: root.pad
        y: cityText.y + cityText.height
        text: root.weather.temperatureLabel
        color: MacTokens.onGlassPrimary
        font.family: MacTokens.displayFamily
        font.pixelSize: MacTokens.s(MacTokens.ncWeatherTempSize)
        font.weight: Font.Normal
    }

    Text {
        id: glyph
        visible: root.weather.available
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: root.pad
        anchors.rightMargin: root.pad
        text: root.weather.icon
        color: MacTokens.onGlassPrimary
        font.family: MacTokens.displayFamily
        font.pixelSize: MacTokens.s(MacTokens.ncWeatherIconSize)
    }

    Text {
        anchors.top: glyph.bottom
        anchors.right: parent.right
        anchors.rightMargin: root.pad
        visible: root.weather.available
        text: root.weather.condition
        color: MacTokens.onGlassPrimary
        font.family: MacTokens.textFamily
        font.pixelSize: MacTokens.s(MacTokens.ncWeatherConditionSize)
        font.weight: Font.DemiBold
    }

    RowLayout {
        visible: root.weather.available
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        anchors.bottomMargin: root.pad
        spacing: 0

        Repeater {
            model: (root.weather.hourlyForecast || []).slice(0, 6)

            delegate: ColumnLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: MacTokens.s(MacTokens.bannerTextGap) * 2

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.time
                    color: MacTokens.onGlassSecondary
                    font.family: MacTokens.textFamily
                    font.pixelSize: MacTokens.s(MacTokens.ncHourlyTimeSize)
                    font.weight: Font.DemiBold
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.icon
                    color: MacTokens.onGlassPrimary
                    font.family: MacTokens.displayFamily
                    font.pixelSize: MacTokens.s(MacTokens.ncHourlyIconSize)
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: modelData.temperature + "°"
                    color: MacTokens.onGlassPrimary
                    font.family: MacTokens.textFamily
                    font.pixelSize: MacTokens.s(MacTokens.ncHourlyTempSize)
                    font.weight: Font.DemiBold
                }
            }
        }
    }
}
