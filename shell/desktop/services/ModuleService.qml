// Desktop-scoped subset of impasto's services/ModuleService.qml.
//
// The full upstream ModuleService is the BAR's catalogue (chip glyph/figure,
// island detail sizing, activation routing) -- explicitly out of scope here
// (see HANDOVER.md: "don't port impasto's ... bar"). Desktop only needs two
// things from it: a name/size per module id (Wides.qml's fallback face, and
// Inspector's header, both read `entry(id).name`/`.width`/`.height`), and
// the panelRequested plumbing widgets use to ask for a panel that does not
// exist in this shell (settings/palette/the notes/board panel) -- those
// stay a no-op signal here exactly as they would on a machine where nothing
// happens to be listening upstream either.

pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property var catalogue: [
        { id: "media",      name: "Media",      desk: true,  width: 380, height: 150 },
        { id: "timer",      name: "Timer",      desk: true,  width: 348, height: 116 },
        { id: "claude",     name: "Claude",     desk: true,  width: 356, height: 150 },
        { id: "battery",    name: "Battery",    desk: true,  width: 320, height: 132 },
        { id: "volume",     name: "Volume",     desk: true,  width: 340, height: 116 },
        { id: "brightness", name: "Brightness", desk: true,  width: 340, height: 100 },
        { id: "network",    name: "Network",    desk: true,  width: 356, height: 132 },
        { id: "bluetooth",  name: "Bluetooth",  desk: true,  width: 356, height: 132 },
        { id: "weather",    name: "Weather",    desk: true,  width: 380, height: 150 },
        { id: "github",     name: "GitHub",     desk: true,  width: 380, height: 158 },
        { id: "stats",      name: "System",     desk: true,  width: 380, height: 148 },
        { id: "updates",    name: "Updates",    desk: true,  width: 356, height: 132 },
        { id: "pet",        name: "Pet",        desk: true,  width: 380, height: 172 },
        { id: "games",      name: "Games",      desk: true,  width: 380, height: 150 },
        { id: "calendar",   name: "Calendar",   desk: true,  width: 340, height: 330 },
        { id: "notes",      name: "Notes",      desk: true,  width: 356, height: 150 },
        { id: "tasks",      name: "Tasks",      desk: true,  width: 356, height: 150 },
        { id: "photo",      name: "Photo",      desk: true,  width: 356, height: 150 },
        { id: "clock",      name: "Clock",      desk: true,  width: 240, height: 32 }
    ]

    function has(id: string): bool {
        return root.catalogue.some(m => m.id === id)
    }

    function entry(id: string): var {
        return root.catalogue.find(m => m.id === id) ?? root.catalogue[0]
    }

    // Widgets ask here for a panel this port does not have (settings,
    // palette, the notes/board panel opened "direct" from a widget). Kept
    // as a no-op signal, same as upstream on a screen where nothing
    // happens to be listening.
    signal panelRequested(string panel)

    function requestPanel(panel: string): void {
        root.panelRequested(panel)
    }
}
