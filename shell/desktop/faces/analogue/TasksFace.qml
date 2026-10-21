// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   T   A   S   K   S       F   A   C   E                                  │
// │   tasks on a clipboard · the next few                                    │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell

import "../../services" as DeskServices
import "../../components"

// TODO: components not yet ported

// The tasks on a clipboard: the next three on a 2×2, the same three beside the
// count on a 4×2, and nine lines at 4×4.
Item {
    id: root

    property string family: "2x2"
    property var ink: DeskServices.DeskDesktopService.inkFor(null)

    readonly property string count: {
        if (DeskServices.DeskTasksService.pending === 0)
            return DeskServices.DeskTasksService.count === 0 ? "Nothing yet" : "All done"
        const late = DeskServices.DeskTasksService.overdue.length
        return `${DeskServices.DeskTasksService.pending} to do${late > 0 ? ` · ${late} late` : ""}`
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.family === "4x4" ? large : room
    }

    Component {
        id: room

        Instrument {
            family: root.family
            ink: root.ink
            line: root.count
            reading: `${DeskServices.DeskTasksService.pending}`
            note: DeskServices.DeskTasksService.pending === 0
                ? (DeskServices.DeskTasksService.count === 0 ? "nothing yet" : "all done")
                : DeskServices.DeskTasksService.summary
            tint: DeskServices.DeskTasksService.overdue.length > 0 ? DeskServices.DeskTheme.red : root.ink.text
            filled: true

            Clipboard {
                anchors.fill: parent
                anchors.topMargin: 8
                ink: root.ink
                tasks: DeskServices.DeskTasksService.queue.slice(0, 3)
            }

            extra: [
                PillButton {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: "Open"
                    implicitHeight: 28
                    onClicked: DeskServices.ModuleService.requestPanel("board")
                }
            ]
        }
    }

    Component {
        id: large

        Item {
            Clipboard {
                anchors.fill: parent
                anchors.margins: 22
                anchors.topMargin: 30
                ink: root.ink
                title: `Tasks · ${root.count.toLowerCase()}`
                tasks: DeskServices.DeskTasksService.queue.slice(0, 9)
            }
        }
    }
}
