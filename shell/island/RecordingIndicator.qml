import QtQuick
import "../core"
import "../services"

/**
 * RecordingIndicator -- breathing red dot + mm:ss. Visible only while
 * services/ScreenRecService.qml is recording; contributes exactly 0 width
 * otherwise (same "absent, not idling at zero" contract island/Eq.qml
 * documents for the level meter) -- nothing paints or ticks while not
 * recording.
 *
 * WIDTH CONTRACT: this component's own footprint (dot + gap + "00:00" mono
 * text) is duplicated as a literal in island/IslandController.qml's
 * targetWidth formula, the SAME pattern that formula already uses for the
 * workspace-switch overlay's own width (see its own comment there). The
 * pill's spring target has to widen to make room BEFORE this indicator
 * appears, not overflow a pill that hasn't grown yet -- a previous pass
 * broke this exact pill with mismatched widths (zero-height clipped zones,
 * art wider than its own slot). If either this file's dotSize/gap/
 * textWidth or IslandController.qml's copy of them changes, update both.
 */
Item {
    id: root

    readonly property bool active: ScreenRecService.recording
    // Ink: an 8px solid red dot (showcase .dot.rec, no breathing) and a 13px
    // mono time, sized to fit the 188px ink rest pill.
    readonly property real dotSize: Config.appearance.ink ? 8 : Theme.u(0.16)
    readonly property real gap: Config.appearance.ink ? 8 : Theme.u(0.1)
    readonly property real textWidth: Config.appearance.ink ? 46 : Theme.u(0.72)

    visible: active
    implicitWidth: active ? root.dotSize + root.gap + root.textWidth : 0
    // DisplayScale.primary: bare literal, unlike dotSize/gap/textWidth above
    // which already route through Theme.u().
    implicitHeight: Math.round(20 * DisplayScale.primary)

    function mmss(totalSeconds: real): string {
        const s = Math.max(0, Math.floor(totalSeconds))
        const m = Math.floor(s / 60)
        const r = s % 60
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gap

        Rectangle {
            id: dot
            anchors.verticalCenter: parent.verticalCenter
            width: root.dotSize
            height: root.dotSize
            radius: width / 2
            color: Config.appearance.ink ? "#ff453a" : Theme.error

            // The one deliberate exception to "nothing ticks at rest" --
            // "at rest" here means NOT recording (running: root.active),
            // exactly like Eq.qml's own fallback profile is scoped to
            // "nothing playing". A slow opacity pulse, restarting fresh
            // each time recording starts rather than chasing a spring --
            // there's no target to interrupt, it's a fixed decorative loop.
            SequentialAnimation on opacity {
                running: root.active && !Config.appearance.ink
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.mmss(ScreenRecService.elapsed)
            color: Config.appearance.ink ? Theme.t1 : Theme.error
            font.family: Config.appearance.ink ? Theme.fontData : Config.appearance.monoFontFamily
            font.pixelSize: Config.appearance.ink ? 13 : Math.round(10 * Config.island.restTextScale)
            font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
            font.features: ({ "tnum": 1 })
        }
    }
}
