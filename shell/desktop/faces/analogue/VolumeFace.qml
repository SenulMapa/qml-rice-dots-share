// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   V   O   L   U   M   E       F   A   C   E                              │
// │   the volume as a knob · turned to the level, barred when muted          │
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

    line: DeskServices.DeskAudioService.muted ? "Muted" : `${DeskServices.DeskAudioService.volume}%`
    reading: DeskServices.DeskAudioService.muted ? "Muted" : `${DeskServices.DeskAudioService.volume}%`
    note: DeskServices.DeskAudioService.muted ? `${DeskServices.DeskAudioService.volume}% · muted` : "output"
    tint: DeskServices.DeskAudioService.muted ? face.ink.muted : face.ink.text
    filled: true

    Knob {
        anchors.centerIn: parent
        ink: face.ink
        size: Math.min(parent.width, parent.height)
        fraction: DeskServices.DeskAudioService.volume / 100
        muted: DeskServices.DeskAudioService.muted
    }

    extra: [
        UsageBar {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            progress: DeskServices.DeskAudioService.muted ? 0 : DeskServices.DeskAudioService.volume / 100
            fillColor: face.ink.accent
            trackColor: face.ink.raised
        }
    ]
}
