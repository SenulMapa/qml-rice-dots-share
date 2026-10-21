import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

Rectangle {
    id: root

    property string label: "Metric"
    property string value: "Unavailable"
    property string detail: ""
    property string icon: "󰍛"
    property real level: 0
    property color accent: AdaptiveColor.activeFill
    property int valueFontSize: 20

    radius: Theme.radiusLarge
    clip: true
    color: "transparent"
    border.width: 0

    ColumnLayout {
        anchors.fill: parent
        // Tighter than Theme.space3/space1 -- at 3 GridLayout rows in
        // panels/SystemPage.qml's fixed 440px page, a card's own available
        // height (~71px) is a few px short of this content's minimum (icon
        // row + LevelTrack + detail line) at the old margins/spacing, and
        // `clip: true` above was cutting the detail line's descenders/the
        // next line up rather than eliding it. Pre-existing, not
        // introduced by the RingGauge below (measured against the old
        // plain-icon row too -- it was already this tight).
        anchors.margins: Theme.space2
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            RingGauge {
                Layout.preferredWidth: Theme.u(0.52)
                Layout.preferredHeight: Theme.u(0.52)
                value: root.level
                accent: root.accent
                thickness: Theme.u(0.06)

                Text {
                    anchors.centerIn: parent
                    text: root.icon
                    color: root.accent
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: Theme.iconSmall
                }
            }
            Text {
                Layout.fillWidth: true
                text: root.label.toUpperCase()
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 8
                font.letterSpacing: 1
            }
            Text {
                text: root.value
                color: AdaptiveColor.glassText
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: root.valueFontSize
                font.weight: Font.DemiBold
            }
        }

        Item { Layout.fillHeight: true }

        LevelTrack {
            Layout.fillWidth: true
            Layout.preferredHeight: 7
            value: root.level
            accent: root.accent
        }
        Text {
            Layout.fillWidth: true
            text: root.detail
            color: AdaptiveColor.glassTextDim
            elide: Text.ElideRight
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.dashCaption
        }
    }
}
