// Unit tests for the arm-to-confirm state machine shared by
// panels/SessionPage.qml's tiles and panels/ClipboardPage.qml's "Clear all".
// Pure logic, no window and no real services -- see components/ArmState.qml.
// The clock is injected (`now`) so this drives a full 3000ms window without
// ever actually sleeping for one.
import QtQuick
import "components"

Item {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    property real fakeNow: 0
    property var firedKeys: []

    ArmState {
        id: state
        window: 3000
        now: function () { return root.fakeNow }
    }

    Component.onCompleted: {
        state.fired.connect(key => root.firedKeys.push(key))
        runTests()
    }

    function runTests() {
        // 1. First press arms, does not fire.
        fakeNow = 0
        let fired = state.press("shutdown", true)
        ok("first_press_arms_not_fires", fired === false && state.isArmed("shutdown"),
            "fired=" + fired + " armed=" + state.armedKey)

        // 2. Second press on the SAME key within the window fires.
        fakeNow = 500
        fired = state.press("shutdown", true)
        ok("second_press_fires", fired === true && !state.hasArmed,
            "fired=" + fired + " armed=" + state.armedKey)
        ok("fired_signal_carried_key", firedKeys.length === 1 && firedKeys[0] === "shutdown",
            JSON.stringify(firedKeys))

        // 3. Arming again, then letting the window elapse, disarms via the
        //    caller-driven checkExpiry() tick -- no QML Timer inside ArmState.
        fakeNow = 1000
        state.press("reboot", true)
        ok("armed_before_timeout", state.isArmed("reboot"))
        fakeNow = 1000 + 3001
        state.checkExpiry()
        ok("timeout_disarms", !state.hasArmed, "armed=" + state.armedKey)

        // 4. requiresConfirmation:false fires immediately, no arming step at
        //    all -- Lock/Suspend.
        firedKeys = []
        fired = state.press("lock", false)
        ok("safe_fires_immediately", fired === true && !state.hasArmed,
            "fired=" + fired + " armed=" + state.armedKey)
        ok("safe_fired_signal", firedKeys.length === 1 && firedKeys[0] === "lock",
            JSON.stringify(firedKeys))

        // 5. Arming one key, then another, disarms the first for free --
        //    there is nothing to "clear" on it, it just stops being armed.
        fakeNow = 5000
        state.press("logout", true)
        ok("first_key_armed", state.isArmed("logout"))
        fakeNow = 5100
        fired = state.press("hibernate", true)
        ok("arming_another_disarms_first",
            fired === false && state.isArmed("hibernate") && !state.isArmed("logout"),
            "armed=" + state.armedKey)

        // 6. Explicit disarm() -- Escape's path in SessionPage/ClipboardPage.
        state.disarm()
        ok("explicit_disarm", !state.hasArmed)

        // 7. arm() (the preview-IPC path) never fires, only arms.
        firedKeys = []
        state.arm("shutdown")
        ok("preview_arm_only_arms", state.isArmed("shutdown") && firedKeys.length === 0)

        console.log("=== ARMSTATE TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
