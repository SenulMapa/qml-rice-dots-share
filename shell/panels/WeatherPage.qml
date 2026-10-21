import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

Item {
    id: root

    readonly property var metrics: [
        { label: "Humidity", value: WeatherService.humidity + "%",
            detail: "Relative humidity", icon: "󰖎", accent: AdaptiveColor.activeFill },
        { label: "Wind", value: WeatherService.windLabel,
            detail: "At 10 metres", icon: "󰖝", accent: Theme.tertiary },
        { label: "Precipitation", value: WeatherService.precipitationChance + "%",
            detail: WeatherService.precipitation.toFixed(1) + " mm now",
            icon: "󰖗", accent: AdaptiveColor.activeFill },
        { label: "UV index", value: WeatherService.uvIndex.toString(),
            detail: WeatherService.uvIndex >= 6 ? "Use sun protection"
                : WeatherService.uvIndex >= 3 ? "Moderate exposure" : "Low exposure",
            icon: "󰖙", accent: Theme.warning },
        { label: "Visibility", value: WeatherService.visibilityLabel,
            detail: "Current horizontal range", icon: "󰈈", accent: Theme.secondary },
        { label: "Pressure", value: WeatherService.pressureLabel,
            detail: "Surface pressure", icon: "󰓅", accent: Theme.tertiary },
        { label: "Sunrise", value: WeatherService.sunrise,
            detail: "Local time", icon: "󰖛", accent: Theme.warning },
        { label: "Sunset", value: WeatherService.sunset,
            detail: "Local time", icon: "󰖚", accent: Theme.tertiary }
    ]

    Flickable {
        id: weatherScroll
        anchors.fill: parent
        visible: WeatherService.available
        contentWidth: width
        contentHeight: weatherContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: weatherContent
            width: weatherScroll.width - Theme.space2
            spacing: Theme.space2

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 150

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.space4
                    spacing: Theme.space3

                    // The temperature IS the page's focal point -- one big
                    // numeral, everything else reads as caption around it.
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: WeatherService.temperatureLabel
                        color: AdaptiveColor.glassText
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 92
                        font.weight: Font.DemiBold
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 150
                        spacing: 2
                        Text {
                            text: WeatherService.icon
                            color: Theme.tertiary
                            font.family: Config.appearance.monoFontFamily
                            font.pixelSize: 26
                        }
                        Text {
                            text: WeatherService.condition
                            color: AdaptiveColor.glassText
                            font.family: Config.appearance.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: WeatherService.feelsLikeLabel + "  ·  "
                                + WeatherService.highLowLabel
                            color: AdaptiveColor.glassTextDim
                            font.family: Config.appearance.fontFamily
                            font.pixelSize: 9
                        }
                    }

                    Item { Layout.fillWidth: true }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignRight | Qt.AlignTop
                        spacing: 1
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: Config.weather.locationName
                            color: AdaptiveColor.glassText
                            font.family: Config.appearance.displayFontFamily
                            font.pixelSize: Theme.textTitle
                            font.weight: Font.Normal
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: "Updated " + Qt.formatTime(WeatherService.lastUpdated, "HH:mm")
                            color: AdaptiveColor.glassTextDim
                            font.family: Config.appearance.monoFontFamily
                            font.pixelSize: 8
                        }
                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: "󰑐  Refresh"
                            color: refreshHover.hovered ? AdaptiveColor.activeFill
                                : AdaptiveColor.glassTextDim
                            font.family: Config.appearance.fontFamily
                            font.pixelSize: 9
                            HoverHandler { id: refreshHover }
                            TapHandler { onTapped: WeatherService.refresh() }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 104

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.space3
                    spacing: Theme.space2

                    Text {
                        text: "HOURLY FORECAST"
                        color: AdaptiveColor.glassTextDim
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 0.9
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: Math.min(parent.width,
                            Config.insights.hourlyPreviewCount * 54
                                + (Config.insights.hourlyPreviewCount - 1)
                                    * Theme.space1)
                        Layout.fillHeight: true
                        spacing: Theme.space1

                        Repeater {
                            model: WeatherService.hourlyForecast.slice(0,
                                Config.insights.hourlyPreviewCount)
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.preferredWidth: 54
                                Layout.fillHeight: true
                                spacing: 1
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.time
                                    color: AdaptiveColor.glassTextDim
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: 8
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.icon
                                    color: AdaptiveColor.activeFill
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: 16
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.temperature + "°"
                                    color: AdaptiveColor.glassText
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: modelData.precipitation > 0
                                    text: modelData.precipitation + "%"
                                    color: AdaptiveColor.activeFill
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: 8
                                }
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 218

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.space3
                    spacing: Theme.space1
                    Text {
                        Layout.preferredHeight: 20
                        text: "7-DAY FORECAST"
                        color: AdaptiveColor.glassTextDim
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 0.9
                    }
                    Repeater {
                        model: WeatherService.forecast.slice(0,
                            Config.insights.dailyPreviewCount)
                        delegate: Item {
                            id: dailyRow
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.space2
                                anchors.rightMargin: Theme.space2
                                spacing: Theme.space2
                                Text {
                                    Layout.preferredWidth: 66
                                    // "Today" is a colour cue, not a filled
                                    // badge -- the row itself stays plain.
                                    text: dailyRow.modelData.day
                                    color: dailyRow.index === 0
                                        ? AdaptiveColor.activeFill : AdaptiveColor.glassText
                                    font.family: Config.appearance.fontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.preferredWidth: 28
                                    horizontalAlignment: Text.AlignHCenter
                                    text: dailyRow.modelData.icon
                                    color: AdaptiveColor.activeFill
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: 15
                                }
                                RowLayout {
                                    Layout.preferredWidth: 62
                                    spacing: Theme.space1
                                    Text {
                                        text: "󰖗"
                                        color: dailyRow.modelData.precipitation > 0
                                            ? AdaptiveColor.activeFill
                                            : AdaptiveColor.glassTextDim
                                        opacity: dailyRow.modelData.precipitation > 0
                                            ? 1 : 0.34
                                        font.family: Config.appearance.monoFontFamily
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        text: dailyRow.modelData.precipitation + "%"
                                        color: AdaptiveColor.glassTextDim
                                        font.family: Config.appearance.monoFontFamily
                                        font.pixelSize: 9
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    Layout.preferredWidth: 32
                                    horizontalAlignment: Text.AlignRight
                                    text: dailyRow.modelData.low + "°"
                                    color: AdaptiveColor.glassTextDim
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: 10
                                }
                                Rectangle {
                                    Layout.preferredWidth: 132
                                    Layout.preferredHeight: 6
                                    radius: 3
                                    color: Qt.alpha(AdaptiveColor.glassTextDim, 0.14)
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: parent.width * 0.16
                                        width: parent.width * 0.68
                                        height: parent.height
                                        radius: 3
                                        color: Theme.tertiary
                                    }
                                }
                                Text {
                                    Layout.preferredWidth: 32
                                    text: dailyRow.modelData.high + "°"
                                    color: AdaptiveColor.glassText
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: 10
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.space2
                rowSpacing: Theme.space2

                Repeater {
                    model: root.metrics
                    delegate: WeatherMetric {
                        required property var modelData
                        Layout.fillWidth: true
                        label: modelData.label
                        value: modelData.value
                        detail: modelData.detail
                        icon: modelData.icon
                        accent: modelData.accent
                    }
                }
            }
        }

        Rectangle {
            visible: weatherScroll.contentHeight > weatherScroll.height
            anchors.right: parent.right
            width: 2
            height: Math.max(24, parent.height * weatherScroll.visibleArea.heightRatio)
            y: parent.height * weatherScroll.visibleArea.yPosition
            radius: 1
            color: Qt.alpha(AdaptiveColor.activeFill, 0.48)
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        visible: !WeatherService.available
        spacing: Theme.space3

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: WeatherService.loading ? "󰡌" : "󰖐"
            color: Theme.tertiary
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: 36
            RotationAnimation on rotation {
                running: WeatherService.loading
                    && !Config.appearance.reducedMotion
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: WeatherService.statusLabel
            color: AdaptiveColor.glassText
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textBody
            font.weight: Font.DemiBold
        }
        Text {
            visible: !WeatherService.loading
            Layout.alignment: Qt.AlignHCenter
            text: WeatherService.configured
                ? "Retry forecast" : "Configure a location in Dashboard settings"
            color: AdaptiveColor.activeFill
            font.family: Config.appearance.fontFamily
            font.pixelSize: 10
            TapHandler {
                enabled: WeatherService.configured
                onTapped: WeatherService.refresh()
            }
        }
    }
}
