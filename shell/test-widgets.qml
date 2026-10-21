// Offline tests for services/WidgetStore.qml's pure logic: default layout,
// snapping math, state-root resolution, and a layout serialize/deserialize
// round trip. Mutators (addWidget/removeWidget/...) are exercised with
// `loaded` forced false so WidgetStore.save() no-ops -- this machine's real
// XDG_STATE_HOME is a real, possibly-populated path, and this test must
// never overwrite the user's actual widgets.json as a side effect of
// running ./run-tests.sh.
import QtQuick
import Quickshell
import "services"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    Timer {
        interval: 50
        running: true
        onTriggered: root.runTests()
    }

    function runTests() {
        const S = WidgetStore

        // 1. Default layout: two widgets, primary-only, fraction-bounded,
        //    left-edge (clear of the top-centre island).
        const def = S.defaultLayout()
        root.ok("default_layout_count", def.length === 2, "got " + def.length)
        root.ok("default_layout_types",
            def.some(w => w.type === "shapeClock")
                && def.some(w => w.type === "dateWeather"))
        root.ok("default_layout_fractions_bounded",
            def.every(w => w.x >= 0 && w.x <= 1 && w.y >= 0 && w.y <= 1))
        root.ok("default_layout_avoids_top_centre",
            def.every(w => w.x < 0.5), "expected left-side placement")

        // 2. Size variants / pixel size.
        const size2x2 = S.widgetPixelSize("2x2")
        root.ok("pixel_size_2x2", size2x2.width === 2 * S.cellSize
            && size2x2.height === 2 * S.cellSize, JSON.stringify(size2x2))
        const sizeUnknown = S.widgetPixelSize("not-a-real-size")
        root.ok("pixel_size_falls_back", sizeUnknown.width === size2x2.width,
            "unknown size key should fall back to 2x2")

        // 3. Snapping math: rounds to the grid and clamps inside margins.
        const snapped = S.snapPositionPx(101, 203, 1920, 1080, 176, 176, 8)
        root.ok("snap_rounds_to_grid",
            snapped.x % S.gridSize === 0 && snapped.y % S.gridSize === 0,
            JSON.stringify(snapped))
        const clampedNeg = S.snapPositionPx(-500, -500, 1920, 1080, 176, 176, 8)
        root.ok("snap_clamps_negative", clampedNeg.x === 8 && clampedNeg.y === 8,
            JSON.stringify(clampedNeg))
        const clampedFar = S.snapPositionPx(999999, 999999, 1920, 1080, 176, 176, 8)
        root.ok("snap_clamps_past_edge",
            clampedFar.x === 1920 - 176 - 8 && clampedFar.y === 1080 - 176 - 8,
            JSON.stringify(clampedFar))

        // 4. State-root resolution -- both branches, deterministically.
        root.ok("state_root_uses_explicit_xdg",
            S.resolveStateRoot("/custom/state", "/srv/whoever") === "/custom/state")
        root.ok("state_root_falls_back_to_home_local_state",
            S.resolveStateRoot("", "/srv/someone") === "/srv/someone/.local/state")
        root.ok("state_path_suffix",
            S.statePath.endsWith("/qml-rice/widgets.json"), S.statePath)

        // 5. Serialize/deserialize round trip -- pure JSON, no disk I/O.
        const sample = {
            "DP-1": [
                { id: "a", type: "shapeClock", x: 0.1, y: 0.1, size: "3x3", options: {} }
            ]
        }
        const savedLayouts = S.layouts
        S.layouts = sample
        const roundTripped = S.deserialize(S.serialize())
        root.ok("round_trip_preserves_screens",
            Object.keys(roundTripped).join(",") === "DP-1")
        root.ok("round_trip_preserves_widget",
            roundTripped["DP-1"][0].id === "a"
                && roundTripped["DP-1"][0].type === "shapeClock"
                && roundTripped["DP-1"][0].x === 0.1)
        root.ok("deserialize_rejects_garbage",
            Object.keys(S.deserialize("not json")).length === 0)
        root.ok("deserialize_rejects_wrong_shape",
            Object.keys(S.deserialize('{"screens": "nope"}')).length === 0)
        S.layouts = savedLayouts

        // 6. Mutators -- forced `loaded = false` so save() is a no-op and
        //    this never touches the real widgets.json on disk.
        const wasLoaded = S.loaded
        S.loaded = false
        S.layouts = {}

        S.setLayoutForScreen("TEST-SCREEN", [])
        root.ok("seed_only_seeds_primary", (() => {
            S.ensureScreenSeeded("TEST-SCREEN", false)
            S.ensureScreenSeeded("TEST-PRIMARY", true)
            return S.layoutFor("TEST-SCREEN").length === 0
                && S.layoutFor("TEST-PRIMARY").length === 2
        })())
        root.ok("seed_is_idempotent", (() => {
            S.removeWidget("TEST-PRIMARY", "default-shape-clock")
            S.ensureScreenSeeded("TEST-PRIMARY", true)
            return S.layoutFor("TEST-PRIMARY").length === 1
        })(), "removing a default then re-seeding must not restore it")

        const addedId = S.addWidget("TEST-SCREEN", "media")
        root.ok("add_widget_returns_id", addedId.length > 0)
        root.ok("add_widget_appends",
            S.layoutFor("TEST-SCREEN").some(w => w.id === addedId))
        root.ok("add_widget_rejects_unknown_type",
            S.addWidget("TEST-SCREEN", "not-a-widget") === "")

        // Regression: addWidget must stagger spawn points -- previously
        // every add landed on the same fixed 0.06/0.06 fraction, so a
        // second widget was invisibly stacked exactly on top of the first.
        const secondId = S.addWidget("TEST-SCREEN", "media")
        const firstEntry = S.layoutFor("TEST-SCREEN").find(w => w.id === addedId)
        const secondEntry = S.layoutFor("TEST-SCREEN").find(w => w.id === secondId)
        root.ok("add_widget_staggers_position",
            firstEntry.x !== secondEntry.x || firstEntry.y !== secondEntry.y,
            JSON.stringify([firstEntry, secondEntry]))
        S.removeWidget("TEST-SCREEN", secondId)

        S.moveWidgetFraction("TEST-SCREEN", addedId, 0.33, 0.44)
        const moved = S.layoutFor("TEST-SCREEN").find(w => w.id === addedId)
        root.ok("move_widget_updates_fraction",
            moved.x === 0.33 && moved.y === 0.44, JSON.stringify(moved))

        S.resizeWidget("TEST-SCREEN", addedId, "4x4")
        root.ok("resize_widget_updates_size",
            S.layoutFor("TEST-SCREEN").find(w => w.id === addedId).size === "4x4")

        S.setWidgetOption("TEST-SCREEN", addedId, "showArtwork", false)
        root.ok("set_widget_option",
            S.layoutFor("TEST-SCREEN").find(w => w.id === addedId)
                .options.showArtwork === false)

        S.removeWidget("TEST-SCREEN", addedId)
        root.ok("remove_widget",
            !S.layoutFor("TEST-SCREEN").some(w => w.id === addedId))

        S.editMode = false
        S.toggleEditMode()
        root.ok("toggle_edit_mode", S.editMode === true)
        S.setEditMode(false)
        root.ok("set_edit_mode", S.editMode === false)

        S.layouts = {}
        S.loaded = wasLoaded

        console.log("=== WIDGETS TEST ===")
        for (const line of root.log) console.log(line)
        const failed = root.log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
