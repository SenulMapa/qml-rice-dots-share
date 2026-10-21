// Pure-logic test for services/PhoneAttention.qml: the full decide() matrix
// plus the override seams. No input, no compositor.
import QtQuick
import Quickshell
import "services"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    Component.onCompleted: {
        // kind, idle, locked -> expected
        const matrix = [
            ["message", false, false, "show"], ["message", true, false, "quiet"],
            ["message", false, true, "quiet"], ["message", true, true, "quiet"],
            ["call", false, false, "show"], ["call", true, false, "pill"],
            ["call", false, true, "quiet"], ["call", true, true, "quiet"],
            ["pin", false, false, "show"], ["pin", true, false, "quiet"],
            ["pin", false, true, "quiet"], ["pin", true, true, "quiet"],
            ["live", false, false, "show"], ["live", true, false, "show"],
            ["live", false, true, "quiet"], ["live", true, true, "quiet"]
        ]
        for (const m of matrix)
            ok("decide_" + m[0] + "_idle" + (m[1] ? 1 : 0) + "_locked" + (m[2] ? 1 : 0),
                PhoneAttention.decide(m[0], m[1], m[2]) === m[3],
                PhoneAttention.decide(m[0], m[1], m[2]))
        ok("unknown_kind_quiet", PhoneAttention.decide("bogus", false, false) === "quiet")

        PhoneAttention.idleOverride = false
        PhoneAttention.lockedOverride = false
        ok("active_when_input_and_unlocked", PhoneAttention.active === true
            && PhoneAttention.textAllowed === true && PhoneAttention.decideNow("message") === "show")
        PhoneAttention.idleOverride = true
        ok("inactive_when_idle", PhoneAttention.active === false && PhoneAttention.decideNow("call") === "pill")
        PhoneAttention.idleOverride = false
        PhoneAttention.lockedOverride = true
        ok("inactive_when_locked", PhoneAttention.active === false && PhoneAttention.textAllowed === false
            && PhoneAttention.decideNow("call") === "quiet")
        ok("idle_window_120s", PhoneAttention.idleSeconds === 120)

        console.log("=== PHONE ATTENTION TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
