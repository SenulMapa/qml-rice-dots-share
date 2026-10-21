// Ported from impasto's bar/island/controls/WeatherCard.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// Current conditions and the next few hours.
//
// Adaptation: Theme -> DeskTheme; WeatherService -> DeskWeatherService (the
// desktop port's Open-Meteo adapter, not impasto's own wttr.in script --
// see that file's header). `ahead` -> `hourly` (same shape, renamed by the
// desktop port). Upstream's region/reading-age line was dropped: the
// shell's WeatherService has no region or last-fetch-age field to bind, and
// this port does not invent one.

import QtQuick
import QtQuick.Layouts
import "../../desktop/services" as Desk
import "../components" as DashComponents

DashComponents.Card {
    id: root

    property int cols: 2
    property int rows: 3

    readonly property bool oneLine: root.rows <= 1
    readonly property bool beside: root.cols >= 4 && root.rows <= 2
    readonly property bool showAhead: !root.oneLine && (root.rows >= 3 || root.beside)

    Component.onCompleted: Desk.DeskWeatherService.subscribe()
    Component.onDestruction: Desk.DeskWeatherService.release()

    RowLayout {
        anchors.fill: parent
        visible: root.oneLine
        spacing: 10

        Text {
            text: Desk.DeskWeatherService.available ? Desk.DeskWeatherService.glyph : "󰅤"
            font.family: Desk.DeskTheme.fontMono
            font.pixelSize: 22
            color: Desk.DeskTheme.accent
        }

        Text {
            text: Desk.DeskWeatherService.available ? `${Desk.DeskWeatherService.temperature}°` : "—"
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: 20
            font.weight: Font.DemiBold
            color: Desk.DeskTheme.text
        }

        Text {
            Layout.fillWidth: true
            text: Desk.DeskWeatherService.available
                ? `${Desk.DeskWeatherService.description}  ·  feels ${Desk.DeskWeatherService.feelsLike}°`
                : "No reading"
            elide: Text.ElideRight
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: Desk.DeskTheme.fontSizeSmall
            color: Desk.DeskTheme.textMuted
        }

        Text {
            visible: Desk.DeskWeatherService.available
            text: `${Desk.DeskWeatherService.high}° / ${Desk.DeskWeatherService.low}°`
            font.family: Desk.DeskTheme.fontMono
            font.pixelSize: Desk.DeskTheme.fontSizeLabel
            color: Desk.DeskTheme.textMuted
        }
    }

    GridLayout {
        anchors.fill: parent
        visible: !root.oneLine
        columns: root.beside ? 2 : 1
        rowSpacing: 10
        columnSpacing: 16

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: 12

            Text {
                text: Desk.DeskWeatherService.available ? Desk.DeskWeatherService.glyph : "󰅤"
                font.family: Desk.DeskTheme.fontMono
                font.pixelSize: 40
                color: Desk.DeskTheme.accent
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: Desk.DeskWeatherService.available
                            ? `${Desk.DeskWeatherService.temperature}°`
                            : "—"
                        font.family: Desk.DeskTheme.fontFamily
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                        color: Desk.DeskTheme.text
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        Layout.alignment: Qt.AlignBottom
                        Layout.bottomMargin: 5
                        visible: Desk.DeskWeatherService.available
                        text: `${Desk.DeskWeatherService.high}° / ${Desk.DeskWeatherService.low}°`
                        font.family: Desk.DeskTheme.fontMono
                        font.pixelSize: Desk.DeskTheme.fontSizeLabel
                        color: Desk.DeskTheme.textMuted
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: Desk.DeskWeatherService.available
                        ? `${Desk.DeskWeatherService.description}  ·  feels ${Desk.DeskWeatherService.feelsLike}°`
                        : "No reading"
                    elide: Text.ElideRight
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeSmall
                    color: Desk.DeskTheme.textMuted
                }

                Text {
                    Layout.fillWidth: true
                    visible: Desk.DeskWeatherService.available
                    text: `󰍎 ${Desk.DeskWeatherService.place}`
                    elide: Text.ElideRight
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeLabel
                    color: Desk.DeskTheme.textMuted
                    opacity: 0.75
                }
            }
        }

        Item {
            Layout.fillHeight: true
            visible: !root.beside
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: root.beside ? Qt.AlignVCenter : Qt.AlignBottom
            spacing: 6
            visible: root.showAhead && Desk.DeskWeatherService.hourly.length > 0

            Repeater {
                model: Desk.DeskWeatherService.hourly

                Item {
                    id: block

                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: stack.implicitHeight

                    Column {
                        id: stack

                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 3

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: {
                                const hour = `${block.modelData.hour}`.padStart(2, "0")
                                return block.modelData.tomorrow ? `${hour}:00⁺` : `${hour}:00`
                            }
                            font.family: Desk.DeskTheme.fontMono
                            font.pixelSize: Desk.DeskTheme.fontSizeLabel
                            color: Desk.DeskTheme.textMuted
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: block.modelData.glyph
                            font.family: Desk.DeskTheme.fontMono
                            font.pixelSize: 16
                            color: Desk.DeskTheme.text
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: `${block.modelData.temperature}°`
                            font.family: Desk.DeskTheme.fontMono
                            font.pixelSize: Desk.DeskTheme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Desk.DeskTheme.text
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: block.modelData.rain >= 20
                            text: `${block.modelData.rain}%`
                            font.family: Desk.DeskTheme.fontMono
                            font.pixelSize: Desk.DeskTheme.fontSizeLabel
                            color: Desk.DeskTheme.blue
                        }
                    }
                }
            }
        }
    }
}
