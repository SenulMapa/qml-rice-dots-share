// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   N   E   T   W   O   R   K       F   A   C   E                          │
// │   the signal as arcs · a plug on a cable                                 │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../services" as DeskServices

// TODO: components not yet ported

Instrument {
    id: face

    line: DeskServices.DeskNetworkService.connectionName
    reading: DeskServices.DeskNetworkService.connectionName
    note: DeskServices.DeskNetworkService.stateLine

    Arcs {
        anchors.centerIn: parent
        ink: face.ink
        size: Math.min(parent.width, parent.height)
        strength: DeskServices.DeskNetworkService.strength
        connected: DeskServices.DeskNetworkService.wifiConnected
        wired: DeskServices.DeskNetworkService.wiredConnected
    }
}
