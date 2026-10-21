// Verifies island/IslandController.qml's workspace-switch-overlay timing:
// a switch flips workspaceSwitchActive on immediately, 1.5s of no further
// switches reverts it, and a rapid second switch inside that window restarts
// the 1.5s timer instead of letting the first one fire early.
//
// Ports the exact state machine by hand (lastWorkspaceId/previousWorkspaceId/
// workspaceSwitchActive + a 1.5s Timer restarted on every switch) rather than
// loading the real IslandController, which hard-imports the live
// HyprlandService singleton and would tie this suite's timing to whatever
// Hyprland session happens to be running -- same reasoning as
// test-workspace-arc.qml. Real elapsed-time Timers, same technique as
// test-reveal.qml/test-motion.qml, with generous margins either side of the
// 1500ms edge so this isn't flaky under scheduling jitter.
import QtQuick

Item {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    // ---- model of IslandController's workspace-switch overlay -----------
    property int lastWorkspaceId: 1
    property int previousWorkspaceId: 1
    property bool workspaceSwitchActive: false

    function switchTo(id) {
        if (id === root.lastWorkspaceId) return
        root.previousWorkspaceId = root.lastWorkspaceId
        root.lastWorkspaceId = id
        root.workspaceSwitchActive = true
        revertTimer.restart()
    }

    Timer { id: revertTimer; interval: 1500; onTriggered: root.workspaceSwitchActive = false }

    SequentialAnimation {
        id: sequence
        running: true

        ScriptAction { script: {
            root.switchTo(2)
            root.ok("active_immediately_on_switch", root.workspaceSwitchActive)
            root.ok("previous_id_recorded", root.previousWorkspaceId === 1,
                "previous " + root.previousWorkspaceId)
        }}

        // Still active well before the 1.5s window elapses.
        PauseAnimation { duration: 900 }
        ScriptAction { script: {
            root.ok("still_active_before_deadline", root.workspaceSwitchActive)
            // A second switch inside the window must RESTART the 1.5s
            // countdown, not let the first one's clock keep running.
            root.switchTo(3)
        }}

        // 900ms after the restart (1800ms since the very first switch, which
        // WOULD have reverted under the ORIGINAL timer -- proves the restart
        // actually took effect).
        PauseAnimation { duration: 900 }
        ScriptAction { script: {
            root.ok("restart_on_second_switch_kept_it_active",
                root.workspaceSwitchActive,
                "900ms after restart, 1800ms after first switch")
        }}

        // Now let it run out for real: 900ms + 700ms margin > 1500ms since
        // the second switch, with no further switches in between.
        PauseAnimation { duration: 700 }
        ScriptAction { script: {
            root.ok("reverts_after_1500ms_of_quiet", !root.workspaceSwitchActive)
        }}

        ScriptAction { script: {
            console.log("=== WORKSPACE REVERT TIMING TEST ===")
            for (const line of root.log) console.log(line)
            const failed = root.log.filter(l => l.indexOf("FAIL") === 0).length
            console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
            Qt.exit(failed === 0 ? 0 : 1)
        }}
    }
}
