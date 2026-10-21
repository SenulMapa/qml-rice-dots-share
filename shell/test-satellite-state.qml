// Unit tests for components/SatelliteState.qml -- the open/close/toggle
// machine backing the Wi-Fi/Bluetooth/Audio/tray satellites now that they're
// owned by island/IslandExpanded.qml instead of the deprecated ControlCenter
// page (see HANDOVER.md). Pure logic, no window and no real services.
import QtQuick
import "components"

Item {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    SatelliteState { id: state }

    Component.onCompleted: runTests()

    function runTests() {
        // 1. Wi-Fi opens independently and stays open.
        state.toggle("wifi")
        ok("wifi_opens", state.wifiOpen && state.isOpen("wifi"))

        // 2. Opening bluetooth does NOT close wifi -- left/right independence.
        state.toggle("bluetooth")
        ok("bluetooth_opens_wifi_stays", state.wifiOpen && state.isOpen("bluetooth"),
            "wifiOpen=" + state.wifiOpen + " right=" + state.rightSection)

        // 3. Opening audio closes bluetooth -- right satellite is single-slot.
        state.toggle("audio")
        ok("audio_replaces_bluetooth",
            state.isOpen("audio") && !state.isOpen("bluetooth") && state.wifiOpen)

        // 4. Toggling the SAME section again closes just that satellite.
        state.toggle("audio")
        ok("toggle_same_closes_it", !state.isOpen("audio") && state.rightSection === "")
        ok("wifi_unaffected_by_right_close", state.wifiOpen)

        // 5. Toggling wifi again closes it too.
        state.toggle("wifi")
        ok("wifi_toggle_closes", !state.wifiOpen && !state.anyOpen)

        // 6. Tray sections carry an id and toggle by that id specifically.
        state.toggle("tray:item-a")
        ok("tray_opens_with_id", state.isOpen("tray:item-a") && state.rightSection === "tray")
        state.toggle("tray:item-b")
        ok("different_tray_item_replaces", state.isOpen("tray:item-b")
            && !state.isOpen("tray:item-a"))
        state.toggle("tray:item-b")
        ok("same_tray_item_closes", !state.isOpen("tray:item-b") && state.rightSection === "")

        // 7. closeAll() closes both slots regardless of what's open.
        state.open("wifi")
        state.open("bluetooth")
        state.closeAll()
        ok("close_all_clears_both", !state.anyOpen && !state.wifiOpen
            && state.rightSection === "")

        // 8. The phone satellite shares the single right slot with
        // bluetooth/audio/energy: opening one closes the other, wifi is unaffected.
        state.open("wifi")
        state.toggle("phone")
        ok("phone_opens", state.isOpen("phone") && state.rightSection === "phone" && state.wifiOpen)
        state.toggle("bluetooth")
        ok("phone_opens_closes_bluetooth", state.isOpen("bluetooth") && !state.isOpen("phone"))
        state.toggle("phone")
        ok("phone_replaces_bluetooth", state.isOpen("phone") && !state.isOpen("bluetooth"))
        state.toggle("phone")
        ok("phone_toggle_closes", !state.isOpen("phone") && state.rightSection === "" && state.wifiOpen)
        state.open("phone")
        state.closeAll()
        ok("close_all_clears_phone", !state.anyOpen)

        console.log("=== SATELLITE STATE TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
