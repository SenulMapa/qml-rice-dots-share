// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   G   A   M   E   S       F   A   C   E                                  │
// │   arcade as a joystick · best score and play                             │
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

    readonly property var last: DeskServices.DeskGamesService.entry(DeskServices.DeskGamesService.lastPlayed)

    line: face.last ? `${face.last.name} · best ${DeskServices.DeskGamesService.bestOf(face.last.id)}` : "Nothing played yet"
    reading: face.last ? `${DeskServices.DeskGamesService.bestOf(face.last.id)}` : "—"
    note: face.last ? `${face.last.name} · best` : "nothing played yet"
    filled: true

    Joystick {
        anchors.centerIn: parent
        ink: face.ink
        size: Math.min(parent.width, parent.height)
    }

    extra: [
        PillButton {
            anchors.left: parent.left
            anchors.top: parent.top
            text: "Play"
            implicitHeight: 28
            onClicked: DeskServices.ModuleService.requestPanel("games")
        }
    ]
}
