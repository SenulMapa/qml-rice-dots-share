import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

/**
 * IslandOSD -- the volume/brightness/microphone/power-profile pill. A bare
 * glyph, a track, and a right-aligned percentage; no boxed icon, no title,
 * no "ACTIVE" label, no device-name line. Power profile (a non-level kind --
 * there is no meaningful 0-1 "level" to show as a track) keeps working with
 * icon + a short label instead of the track/percentage pair.
 */
Item {
    id: root

    property string kind: "volume"
    property real level: 0
    property bool muted: false
    property string deviceName: ""

    readonly property bool microphone: kind === "microphone"
    readonly property bool brightness: kind === "brightness"
    readonly property bool powerProfile: kind === "powerProfile"
    readonly property bool isLevel: !powerProfile
    readonly property color accent: muted ? Theme.error : AdaptiveColor.activeFill
    readonly property string icon: powerProfile
        ? (level < 0.4 ? "󰌪" : level > 0.85 ? "󰓅" : "󰾅")
        : brightness ? "󰃠" : microphone
        ? (muted ? "󰍭" : "󰍬")
        : (muted || level <= 0 ? "󰝟" : level < 0.5 ? "󰖀" : "󰕾")
    // Ink draws Lucide icons (Icon) instead of the Nerd-font glyphs above.
    readonly property string iconName: powerProfile
        ? (level > 0.85 ? "zap" : "gauge")
        : brightness ? "sun"
        : microphone ? (muted ? "mic-off" : "mic")
        : (muted || level <= 0 ? "volume-x" : level < 0.5 ? "volume-1" : "volume-2")
    readonly property int percentValue:
        Math.round((root.muted && !root.brightness ? 0 : root.level) * 100)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Config.appearance.ink ? 20 : Theme.u(0.34)
        anchors.rightMargin: Config.appearance.ink ? 22 : Theme.u(0.34)
        spacing: Config.appearance.ink ? 14 : Theme.u(0.24)

        Icon {
            visible: Config.appearance.ink
            Layout.alignment: Qt.AlignVCenter
            name: root.iconName
            size: 18
            color: Theme.t1
        }

        Text {
            visible: !Config.appearance.ink
            text: root.icon
            color: AdaptiveColor.glassText
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: Config.appearance.ink ? 18 : Theme.u(0.4)
        }

        // Ink: a 6px capsule track, Theme.fillOn over ink-raised-2.
        Rectangle {
            visible: root.isLevel && Config.appearance.ink
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            radius: 3
            color: Theme.inkRaised2
            clip: true
            Rectangle {
                height: parent.height
                width: parent.width * Math.max(0, Math.min(1, root.muted && !root.brightness ? 0 : root.level))
                radius: 3
                color: Theme.fillOn
                Behavior on width { NumberAnimation { duration: Theme.microMs; easing.type: Easing.OutCubic } }
            }
        }

        LevelTrack {
            visible: root.isLevel && !Config.appearance.ink
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.u(0.14)
            value: root.muted && !root.brightness ? 0 : root.level
            accent: root.accent
            trackColor: Theme.surfaceContainerHigh
        }

        Text {
            id: percentLabel
            visible: root.isLevel
            Layout.preferredWidth: Config.appearance.ink
                ? Math.max(58, implicitWidth) : Math.max(implicitWidth, metrics.implicitWidth)
            horizontalAlignment: Text.AlignRight
            text: root.percentValue + "%"
            // Ink: the serif numeral (showcase .osd-face .serif, 28px).
            color: Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassTextDim
            font.family: Config.appearance.ink ? Theme.fontSerif : Config.appearance.monoFontFamily
            font.pixelSize: Config.appearance.ink ? 28 : Theme.textSmall
        }
        // Width reference only -- keeps the percentage column from jiggling
        // as the digit count changes (a minimum of 3 characters: "100%").
        Text {
            id: metrics
            visible: false
            text: "100%"
            font: percentLabel.font
        }

        Text {
            visible: !root.isLevel
            Layout.fillWidth: true
            text: root.deviceName
            elide: Text.ElideRight
            color: AdaptiveColor.glassTextDim
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textSmall
        }
    }
}
