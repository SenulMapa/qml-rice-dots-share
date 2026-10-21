import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

Squircle {
    id: root

    property string label: ""
    property string value: ""
    property string detail: ""
    property string icon: ""
    property color accent: AdaptiveColor.activeFill
    property bool interactive: false

    signal activated()

    implicitHeight: 64
    radius: Theme.radiusMedium
    // De-bento: transparent at rest, faint hover wash only when interactive.
    color: tileHover.hovered && interactive
        ? Qt.alpha(AdaptiveColor.glassText, 0.05)
        : "transparent"
    borderWidth: 0

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.space3
        spacing: Theme.space2

        Text {
            text: root.icon
            color: root.accent
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: Theme.iconMedium
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: root.label.toUpperCase()
                color: AdaptiveColor.glassTextDim
                elide: Text.ElideRight
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Theme.textSmall
                font.letterSpacing: 1
            }

            Text {
                Layout.fillWidth: true
                text: root.value
                color: AdaptiveColor.glassText
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textBody
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.detail
                color: AdaptiveColor.glassTextDim
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textSmall
            }
        }
    }

    HoverHandler { id: tileHover; enabled: root.interactive }
    TapHandler {
        enabled: root.interactive
        onTapped: root.activated()
    }

    Behavior on color { ColorAnimation { duration: Animations.fast } }
}
