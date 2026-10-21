// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   C   R   E   A   T   U   R   E       F   A   C   E                      │
// │   the pet, larger, on a line of ground · its level as a bar              │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../services" as DeskServices
import "../../components"

// TODO: components not yet ported

// The pet, larger, standing on a line with its name under it. 4×2 adds its mood
// and a bar of progress to the next level.
Instrument {
    id: face

    readonly property string name: DeskServices.DeskPetService.name !== "" ? DeskServices.DeskPetService.name : "Pet"

    line: DeskServices.DeskPetService.hatched ? `${face.name} · Lv ${DeskServices.DeskPetService.level}` : "An egg"
    reading: face.name
    note: DeskServices.DeskPetService.moodLine
    filled: true

    Item {
        anchors.fill: parent

        PetFace {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -8
            size: Math.min(parent.width, parent.height) * 0.5
            lively: true
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: parent.height * 0.14
            width: parent.width * 0.7
            height: 2
            radius: 1
            color: face.ink.dim
        }
    }

    extra: [
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 4

            UsageBar {
                width: parent.width
                progress: DeskServices.DeskPetService.progress
                fillColor: face.ink.accent
                trackColor: face.ink.raised
            }

            Text {
                text: DeskServices.DeskPetService.hatched ? `Lv ${DeskServices.DeskPetService.level}` : "not hatched yet"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                color: face.ink.muted
            }
        }
    ]
}
