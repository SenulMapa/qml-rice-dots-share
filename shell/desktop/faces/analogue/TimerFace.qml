// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   T   I   M   E   R       F   A   C   E                                  │
// │   the countdown as an hourglass · what is left is above the neck         │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../services" as DeskServices
import "../../components"

// TODO: components not yet ported

// The timer as an hourglass: the sand above is the time left, and the thread
// runs while it counts and stops when paused. The 4×2 adds the time, the label
// and the same two controls as the Modern face.
Instrument {
    id: face

    readonly property bool on: DeskServices.DeskTimerService.running

    line: face.on
        ? `${DeskServices.DeskTimerService.display}${DeskServices.DeskTimerService.label !== "" ? " · " + DeskServices.DeskTimerService.label : ""}`
        : "Nothing running"
    reading: face.on ? DeskServices.DeskTimerService.display : "—"
    note: face.on ? (DeskServices.DeskTimerService.label !== "" ? DeskServices.DeskTimerService.label : "counting down") : "nothing running"
    tint: face.on ? face.ink.text : face.ink.muted
    filled: true

    Hourglass {
        anchors.centerIn: parent
        ink: face.ink
        size: Math.min(parent.height, parent.width / 0.72)
        fraction: face.on && DeskServices.DeskTimerService.duration > 0 ? DeskServices.DeskTimerService.remaining / DeskServices.DeskTimerService.duration : 0
        running: face.on && !DeskServices.DeskTimerService.paused
    }

    extra: [
        Row {
            anchors.left: parent.left
            anchors.top: parent.top
            spacing: 10

            PillButton {
                text: DeskServices.DeskTimerService.running
                    ? (DeskServices.DeskTimerService.paused ? "Resume" : "Hold") : "5 min"
                implicitHeight: 30
                onClicked: {
                    if (!DeskServices.DeskTimerService.running)
                        DeskServices.DeskTimerService.start(5 * 60 * 1000, "")
                    else
                        DeskServices.DeskTimerService.toggle()
                }
            }

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                iconColor: face.ink.text
                icon: "󰅖"
                iconSize: 13
                enabled: DeskServices.DeskTimerService.running
                opacity: DeskServices.DeskTimerService.running ? 1 : 0.35
                onClicked: DeskServices.DeskTimerService.cancel()
            }
        }
    ]
}
