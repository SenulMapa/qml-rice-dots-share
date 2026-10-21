import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components"

Squircle {
    id: root

    property string label: ""
    property string value: ""
    property string detail: ""
    property string icon: ""
    property color accent: AdaptiveColor.activeFill

    // Bumped from 74 alongside the dashboard typography pass -- value/detail
    // now render at Theme.dashLabel/dashCaption (fontScale-driven, bigger
    // than the old 13/8px literals), so the fixed height needs the same
    // headroom. Free-flowing GridLayout row (WeatherPage.qml), not a
    // fixed-size dashboard cell, so this is safe to grow.
    implicitHeight: 84
    radius: Theme.radiusMedium
    color: "transparent"
    borderWidth: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space3
        spacing: 1

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: root.icon
                color: root.accent
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 12
            }
            Text {
                Layout.fillWidth: true
                text: root.label.toUpperCase()
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 8
                font.letterSpacing: 0.8
            }
        }
        Text {
            Layout.fillWidth: true
            text: root.value
            color: AdaptiveColor.glassText
            elide: Text.ElideRight
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.dashLabel
            font.weight: Font.DemiBold
            style: Theme.dashHeavy
            styleColor: AdaptiveColor.glassText
        }
        Text {
            Layout.fillWidth: true
            visible: text.length > 0
            text: root.detail
            color: AdaptiveColor.glassTextDim
            elide: Text.ElideRight
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.dashCaption
        }
    }
}
