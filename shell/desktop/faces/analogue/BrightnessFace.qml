// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   B   R   I   G   H   T   N   E   S   S       F   A   C   E              │
// │   the backlight as a fader · pushed up to the level                      │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../services" as DeskServices
import "../../components"

// TODO: components not yet ported

Instrument {
    id: face

    line: DeskServices.DeskBrightnessService.available ? `${DeskServices.DeskBrightnessService.percent}%` : "No backlight"
    reading: DeskServices.DeskBrightnessService.available ? `${DeskServices.DeskBrightnessService.percent}%` : "—"
    note: DeskServices.DeskBrightnessService.available ? "backlight" : "no backlight"
    filled: true

    Fader {
        anchors.centerIn: parent
        ink: face.ink
        size: Math.min(parent.height, parent.width * 2)
        fraction: DeskServices.DeskBrightnessService.percent / 100
    }

    extra: [
        UsageBar {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            progress: DeskServices.DeskBrightnessService.percent / 100
            fillColor: face.ink.accent
            trackColor: face.ink.raised
        }
    ]
}
