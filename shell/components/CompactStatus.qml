import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

Item {
    id: root

    property string icon: ""
    property string value: ""
    property color accent: AdaptiveColor.activeFill
    property real textScale: 1
    property real iconScale: 1
    property real iconVerticalOffset: 0
    property bool showValue: value.length > 0

    implicitWidth: 72
    implicitHeight: 32

    RowLayout {
        anchors.centerIn: parent
        spacing: Theme.space1

        Text {
            text: root.icon
            color: root.accent
            font.family: Config.appearance.monoFontFamily
            // Theme.iconSmall already carries DisplayScale.primary and so
            // does root.iconScale now (bound from Config.island.hoverIconScale
            // by every caller -- see IslandHoverItem.qml's audio/network/
            // bluetooth/keepAwake/battery components) -- divide back out to
            // avoid double-scaling.
            font.pixelSize: Math.round(Theme.iconSmall
                * (root.iconScale / DisplayScale.primary))
            transform: Translate { y: root.iconVerticalOffset }
        }

        Text {
            visible: root.showValue
            text: root.value
            color: AdaptiveColor.glassTextDim
            font.family: Config.appearance.monoFontFamily
            // Same double-scale note as the icon Text above.
            font.pixelSize: Math.round(Theme.textSmall
                * (root.textScale / DisplayScale.primary))
            font.weight: Font.DemiBold
        }
    }
}
