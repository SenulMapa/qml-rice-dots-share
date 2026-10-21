import QtQuick
import "../core"
import "../components"
import "MacFormat.js" as Fmt

/**
 * MacWidgetBattery -- the iPhone battery row (spec 3.3). Shown only when
 * Config.phone.enabled (the Notification Center column sets that). Reads
 * PhoneService (or a stand-in with its members): the device name and the
 * battery level from status, the connection from `connected`. The state line
 * says Connected, Not connected, Charging or On battery; the last two only when
 * BlueFerry reports a charging state, which it does not today.
 */
Item {
    id: root

    required property var phone

    readonly property var line: Fmt.phoneBatteryLine(root.phone.status, root.phone.connected === true)
    readonly property bool online: root.phone.connected === true

    width: MacTokens.s(MacTokens.ncColumnWidth)
    height: MacTokens.s(MacTokens.ncCompactHeight)
    visible: Config.phone.enabled

    readonly property real pad: MacTokens.s(MacTokens.bannerPad)

    TahoeSurface {
        anchors.fill: parent
        kind: "nc"
        radius: MacTokens.s(MacTokens.ncWidgetRadius)
        tintAlpha: MacTokens.frostTintAlpha
        fill: MacTokens.ncWidgetFrost
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: root.pad
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: percent.left
        anchors.rightMargin: root.pad
        spacing: MacTokens.s(MacTokens.bannerTextGap)

        Text {
            width: parent.width
            text: root.line.name
            color: MacTokens.labelPrimary
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: MacTokens.textFamily
            font.pixelSize: MacTokens.s(MacTokens.ncWidgetTitleSize)
            font.weight: Font.DemiBold
        }

        Text {
            width: parent.width
            text: root.line.state
            color: root.online ? MacTokens.labelPrimary : MacTokens.labelSecondary
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: MacTokens.textFamily
            font.pixelSize: MacTokens.s(MacTokens.bannerTimeSize)
            font.weight: Font.Medium
        }
    }

    Text {
        id: percent
        anchors.right: parent.right
        anchors.rightMargin: root.pad
        anchors.verticalCenter: parent.verticalCenter
        text: root.line.percent
        color: root.online ? MacTokens.labelPrimary : MacTokens.labelSecondary
        font.family: MacTokens.displayFamily
        font.pixelSize: MacTokens.s(MacTokens.ncWeatherCitySize)
        font.weight: Font.DemiBold
    }
}
