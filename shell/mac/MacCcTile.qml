import QtQuick
import "../core"
import "../components"

/**
 * MacCcTile -- a Control Center pill (spec 3.4): a 138 x 63 glass capsule with
 * a round icon disc at the left and a title (and optional subtitle) on the
 * right. Used for Wi-Fi, Bluetooth, LocalSend and Focus. Every value comes
 * from MacTokens.
 *
 * `activated()` fires on tap. `inert: true` draws the tile but takes no input
 * (LocalSend, which has no service behind it).
 */
TahoeSurface {
    id: root

    property string title: ""
    property string subtitle: ""
    property string icon: ""
    property bool active: false
    property bool available: true
    property bool inert: false

    signal activated()

    kind: "controlcenter"
    fill: MacTokens.ccModuleFill
    width: MacTokens.s(MacTokens.ccTileWidth)
    height: MacTokens.s(MacTokens.ccTileHeight)
    radius: MacTokens.s(MacTokens.ccTileRadius)
    opacity: root.available ? 1 : MacTokens.ccDisabledAlpha

    // Active fill: the accent, over the glass.
    Squircle {
        anchors.fill: parent
        radius: root.radius
        color: MacTokens.ccActiveFill
        opacity: root.active ? MacTokens.ccActiveAlpha : 0
        Behavior on opacity { NumberAnimation { duration: MacTokens.ccMotionMs / 2 } }
    }

    Rectangle {
        id: disc
        width: MacTokens.s(MacTokens.ccDiscDiameter)
        height: width
        radius: width / 2
        x: MacTokens.s(MacTokens.ccDiscInset)
        anchors.verticalCenter: parent.verticalCenter
        color: root.active ? MacTokens.ccDiscFill : MacTokens.ccDiscIdleFill

        Icon {
            anchors.centerIn: parent
            name: root.icon
            size: MacTokens.s(MacTokens.ccIconSize)
            color: root.active ? MacTokens.ccActiveGlyph : MacTokens.ccIconIdle
        }
    }

    Column {
        x: MacTokens.s(MacTokens.ccTileTextLeft)
        width: root.width - x - MacTokens.s(MacTokens.ccDiscInset)
        anchors.verticalCenter: parent.verticalCenter
        spacing: MacTokens.s(MacTokens.ccSubtitleGap)

        Text {
            width: parent.width
            text: root.title
            color: root.active ? MacTokens.ccActiveText : MacTokens.ccTitleColor
            elide: Text.ElideRight
            font.family: MacTokens.textFamily
            font.pixelSize: MacTokens.s(MacTokens.ccTitleSize)
            font.weight: Font.DemiBold
        }

        Text {
            width: parent.width
            visible: root.subtitle !== ""
            text: root.subtitle
            color: root.active ? Qt.alpha(MacTokens.ccActiveText, MacTokens.ccActiveSubtitleAlpha)
                : Qt.alpha(MacTokens.ccTitleColor, MacTokens.ccSubtitleAlpha)
            elide: Text.ElideRight
            font.family: MacTokens.textFamily
            font.pixelSize: MacTokens.s(MacTokens.ccSubtitleSize)
        }
    }

    TapHandler {
        enabled: root.available && !root.inert
        onTapped: root.activated()
    }
}
