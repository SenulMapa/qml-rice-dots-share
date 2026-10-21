// Verifies the pure decision rules behind island/WorkspacePillRow.qml's
// per-slot presentation (number vs. app icon) and
// island/IslandController.qml's workspaceIndicatorMax range, using synthetic
// workspace data instead of the live HyprlandService singleton -- see
// test-workspace-arc.qml's header for why these suites avoid depending on
// whatever real Hyprland session happens to be running.
import QtQuick

Item {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    // ---- mirrors WorkspacePillRow.qml's slot.showsIcon rule -------------
    function showsIcon(occupied, iconName) {
        return occupied && iconName.length > 0
    }

    // ---- mirrors IslandController.qml's workspaceIndicatorMax rule ------
    function indicatorMax(activeId, occupiedIds) {
        let highest = activeId
        for (const id of occupiedIds) {
            if (id > highest) highest = id
        }
        return Math.max(5, highest)
    }

    Component.onCompleted: root.run()

    function run() {
        // 1. Empty workspace -> always a number, regardless of a stale/wrong
        //    icon name somehow being present (occupied gates it, not the
        //    icon string alone).
        ok("empty_workspace_shows_number", !root.showsIcon(false, "some-icon"))

        // 2. Occupied workspace with a resolvable icon -> icon.
        ok("occupied_with_icon_shows_icon", root.showsIcon(true, "firefox"))

        // 3. Occupied workspace whose client's class had NO desktop-entry
        //    match (heuristicLookup returned nothing, icon "") -> falls back
        //    to the number rather than an empty/broken image.
        ok("occupied_without_icon_falls_back_to_number",
            !root.showsIcon(true, ""))

        // 4. Range floor: an all-empty desktop still shows 5 slots, not 1.
        ok("floor_at_five", root.indicatorMax(1, []) === 5,
            "got " + root.indicatorMax(1, []))

        // 5. Range grows to the highest OCCUPIED id even if the active
        //    workspace itself is lower-numbered.
        ok("grows_to_highest_occupied", root.indicatorMax(2, [1, 2, 7]) === 7,
            "got " + root.indicatorMax(2, [1, 2, 7]))

        // 6. Range grows to the active id even if nothing is occupied there
        //    yet (an empty workspace can still be the active one).
        ok("grows_to_active_id", root.indicatorMax(9, [1, 2]) === 9,
            "got " + root.indicatorMax(9, [1, 2]))

        console.log("=== WORKSPACE INDICATOR MODEL TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
