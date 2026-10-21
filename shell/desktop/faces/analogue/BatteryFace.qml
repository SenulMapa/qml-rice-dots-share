// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   B   A   T   T   E   R   Y       F   A   C   E                          │
// │   the charge as a cell that fills · red when it is running low           │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../services" as DeskServices

// TODO: components not yet ported

// A battery cell filled to the charge, with a bolt while charging. The fill
// takes the fixed battery red when the charge is low.
Instrument {
    id: face

    line: DeskServices.DeskBatteryService.available ? `${DeskServices.DeskBatteryService.percent}% · ${DeskServices.DeskBatteryService.estimate}` : "No battery"
    reading: DeskServices.DeskBatteryService.available ? `${DeskServices.DeskBatteryService.percent}%` : "—"
    note: DeskServices.DeskBatteryService.available
        ? `${DeskServices.DeskBatteryService.stateWord} · ${DeskServices.DeskBatteryService.estimate}` : "no battery"

    BatteryCell {
        anchors.centerIn: parent
        ink: face.ink
        size: Math.min(parent.width, parent.height / 0.48)
        fraction: DeskServices.DeskBatteryService.percent / 100
        charging: DeskServices.DeskBatteryService.charging || DeskServices.DeskBatteryService.full
        fill: DeskServices.DeskBatteryService.low ? DeskServices.DeskBatteryService.tint : face.ink.text
    }
}
