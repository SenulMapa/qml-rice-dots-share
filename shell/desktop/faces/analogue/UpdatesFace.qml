// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   U   P   D   A   T   E   S       F   A   C   E                          │
// │   the pending updates as a parcel · the count on its label               │
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

    readonly property bool none: DeskServices.DeskUpdatesService.count === 0

    line: DeskServices.DeskUpdatesService.checking ? "Checking"
        : (!DeskServices.DeskUpdatesService.available ? "Cannot check"
            : (face.none ? "Up to date" : `${DeskServices.DeskUpdatesService.count} pending`))
    reading: DeskServices.DeskUpdatesService.available || DeskServices.DeskUpdatesService.checking ? `${DeskServices.DeskUpdatesService.count}` : "—"
    note: DeskServices.DeskUpdatesService.checking ? "checking"
        : !DeskServices.DeskUpdatesService.available ? "cannot check"
        : `${face.none ? "up to date" : "pending"}${DeskServices.DeskUpdatesService.age !== "" ? " · " + DeskServices.DeskUpdatesService.age : ""}`
    tint: face.none ? face.ink.muted : face.ink.text
    filled: true

    Parcel {
        anchors.centerIn: parent
        ink: face.ink
        size: Math.min(parent.width, parent.height)
        count: `${DeskServices.DeskUpdatesService.count}`
    }

    extra: [
        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 1

            Repeater {
                model: (DeskServices.DeskUpdatesService.packages ?? []).slice(0, 2)

                Text {
                    required property var modelData

                    width: parent.width
                    text: typeof modelData === "string" ? modelData : (modelData.name ?? "")
                    elide: Text.ElideRight
                    font.family: DeskServices.DeskTheme.fontMono
                    font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                    color: face.ink.muted
                }
            }
        }
    ]
}
