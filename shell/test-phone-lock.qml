// Lock-on-leave policy (services/PhoneLock.qml) against a stub lock target.
// Presence only ever locks; nothing here unlocks. No LockService, no session.
import QtQuick
import Quickshell
import "services"

ShellRoot {
    id: root
    property var log: []
    property int locks: 0
    property int unlocks: 0
    property bool locked: false
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    PhoneLock {
        id: policy
        isLocked: function() { return root.locked }
        lock: function() { root.locks++; root.locked = true }
    }

    Component.onCompleted: {
        policy.enabled = true
        const did = policy.onPresence(false)
        ok("locks_on_leave_when_enabled", did && root.locks === 1 && root.locked)

        root.locked = false; root.locks = 0
        policy.enabled = false
        policy.onPresence(false)
        ok("no_lock_when_disabled", root.locks === 0 && !root.locked)

        policy.enabled = true
        root.locked = true
        policy.onPresence(false)
        ok("no_lock_when_already_locked", root.locks === 0)

        policy.onPresence(true)
        ok("never_unlocks_on_return", root.locked === true && root.unlocks === 0 && root.locks === 0)

        root.locked = false
        policy.onPresence(true)
        ok("near_true_never_locks", root.locks === 0 && !root.locked)

        console.log("=== PHONE LOCK TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
