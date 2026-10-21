// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import "../core"
import "../services"

/**
 * PomodoroWidget -- countdown + play/pause + reset, ported from end4-ii's
 * sidebarRight/pomodoro/{PomodoroWidget,PomodoroTimer}.qml against the new
 * services/PomodoroService.qml. ii's Stopwatch tab (the widget's second
 * SwipeView page) is skipped -- see the port report; this is pomodoro-only.
 */
Item {
    id: root

    readonly property int minutes: Math.floor(PomodoroService.secondsLeft / 60)
    readonly property int seconds: PomodoroService.secondsLeft % 60
    readonly property string label: PomodoroService.onBreak
        ? (PomodoroService.cycle + 1 === PomodoroService.cyclesBeforeLongBreak
            ? "Long break" : "Break")
        : "Focus"

    Column {
        anchors.centerIn: parent
        spacing: Theme.space1

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.minutes.toString().padStart(2, "0") + ":"
                + root.seconds.toString().padStart(2, "0")
            font.family: Config.appearance.fontFamily
            font.pixelSize: Math.round(Math.min(root.width, root.height) * 0.26)
            font.weight: Font.Bold
            color: PomodoroService.onBreak ? Theme.success : Theme.surfaceText
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label + " · cycle " + (PomodoroService.cycle + 1)
                + "/" + PomodoroService.cyclesBeforeLongBreak
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textSmall
            color: Theme.surfaceVariantText
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Theme.space3
            topPadding: Theme.space2

            Text {
                text: PomodoroService.running ? "⏸" : "▶"
                font.pixelSize: Theme.textTitle
                color: Theme.primary
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Theme.space2
                    onClicked: PomodoroService.toggle()
                }
            }
            Text {
                text: "↺"
                font.pixelSize: Theme.textTitle
                color: Theme.surfaceVariantText
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Theme.space2
                    onClicked: PomodoroService.reset()
                }
            }
        }
    }
}
