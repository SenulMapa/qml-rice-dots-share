import QtQuick
import "../components"
import "../core"
import "../services"

/**
 * TimerIndicator -- the running or paused pomodoro / `timer start` countdown
 * on the resting pill: a small progress ring + mm:ss. Visible while
 * services/PomodoroService.qml is running or paused; contributes exactly 0
 * width otherwise, the same contract island/RecordingIndicator.qml documents.
 *
 * Tapping it pauses or resumes the timer. The surface TapHandler in
 * island/Island.qml is told via `pointerOver` not to open the island on
 * that same tap.
 *
 * WIDTH CONTRACT: this component's footprint (ring + gap + "00:00" text) is
 * duplicated as a literal in island/IslandController.qml's targetWidth
 * formula, so the pill widens BEFORE the indicator appears. If the sizes
 * below change, update that copy too.
 */
Item {
    id: root

    readonly property bool active: PomodoroService.running || PomodoroService.paused
    readonly property bool pointerOver: hover.hovered
    // Ink: a 12px ring, 8px gap and 46px mono time, the same footprint as
    // RecordingIndicator's dot.
    readonly property real ringSize: Config.appearance.ink ? 12 : Theme.u(0.2)
    readonly property real gap: Config.appearance.ink ? 8 : Theme.u(0.1)
    readonly property real textWidth: Config.appearance.ink ? 46 : Theme.u(0.72)

    visible: active
    implicitWidth: active ? root.ringSize + root.gap + root.textWidth : 0
    // DisplayScale.primary: bare literal, as in RecordingIndicator.
    implicitHeight: Math.round(20 * DisplayScale.primary)

    // Share of the current phase that has elapsed, 0 at the start of a phase.
    readonly property real fraction: PomodoroService.phaseDuration > 0
        ? Math.min(1, PomodoroService.elapsedSeconds / PomodoroService.phaseDuration)
        : 0

    HoverHandler { id: hover }
    TapHandler {
        onTapped: PomodoroService.running ? PomodoroService.pause() : PomodoroService.toggle()
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gap

        RingGauge {
            anchors.verticalCenter: parent.verticalCenter
            width: root.ringSize
            height: root.ringSize
            // The ring drains as time passes: it shows what is left.
            value: 1 - root.fraction
            accent: PomodoroService.onBreak ? Theme.success
                : (Config.appearance.ink ? Theme.fillOn : AdaptiveColor.activeFill)
            trackColor: Config.appearance.ink ? Theme.inkRaised2 : Theme.surfaceContainerHigh
            thickness: Config.appearance.ink ? 2 : Theme.u(0.03)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: PomodoroService.formatClock(PomodoroService.secondsLeft)
            color: Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText
            font.family: Config.appearance.ink ? Theme.fontData : Config.appearance.monoFontFamily
            font.pixelSize: Config.appearance.ink ? 13 : Math.round(10 * Config.island.restTextScale)
            font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
            font.features: ({ "tnum": 1 })
        }
    }
}
