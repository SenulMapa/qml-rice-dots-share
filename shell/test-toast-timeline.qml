// Drives the REAL island/WorkspaceToastCard.qml (no live Hyprland/D-Bus
// dependency -- it only touches core/Theme.qml and core/Config.qml, so
// unlike the workspace-pill suites this one loads the actual component
// rather than a hand-ported model) through its full 5000ms timeline: fade
// +rise in, hold, fade out, finished(), and a mid-flight restart().
//
// Real elapsed-time sampling via Date.now() (same technique test-reveal.qml
// uses), with generous margins around each phase edge so this isn't flaky
// under scheduling jitter.
import QtQuick
import Quickshell
import "island"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    // ---- Phase 1: natural 5000ms run, no restart -------------------------
    property real t0: 0
    property bool finishedFiredA: false
    property real finishedAtA: 0

    WorkspaceToastCard {
        id: cardA
        workspaceId: 3
        onFinished: {
            root.finishedFiredA = true
            root.finishedAtA = Date.now() - root.t0
        }
    }

    // ---- Phase 2: restart mid-flight -------------------------------------
    // Lazily loaded (active: false until phase 2 begins) -- a card pre-
    // created alongside cardA would already have finished its own natural
    // 5000ms timeline by the time phase 2's assertions run, which start
    // well past that mark.
    property real t1: 0
    property real restartedAt: 0
    property bool finishedFiredB: false
    // Measured from the restart() CALL, not from cardB's creation -- a
    // restart resets the whole 5000ms clock, so "finishes ~5s later" only
    // makes sense relative to when restart() actually ran.
    property real finishedAfterRestartMs: 0

    Loader {
        id: loaderB
        active: false
        sourceComponent: WorkspaceToastCard {
            workspaceId: 7
            onFinished: {
                root.finishedFiredB = true
                root.finishedAfterRestartMs = Date.now() - root.restartedAt
            }
        }
    }
    readonly property var cardB: loaderB.item

    SequentialAnimation {
        id: sequence
        running: true

        ScriptAction { script: root.t0 = Date.now() }

        // Just after creation: still low (fade-in just started).
        PauseAnimation { duration: 60 }
        ScriptAction { script: {
            root.ok("starts_near_hidden", cardA.revealProgress < 0.4,
                "revealProgress " + cardA.revealProgress.toFixed(3))
        }}

        // Mid-entrance-to-hold: fully (or nearly) revealed well before the
        // fade-out phase begins (fade-in ends at 450ms; sample at 1000ms).
        PauseAnimation { duration: 940 }
        ScriptAction { script: {
            root.ok("reaches_full_reveal_during_hold", cardA.revealProgress > 0.95,
                "revealProgress " + cardA.revealProgress.toFixed(3))
            root.ok("opacity_tracks_reveal", Math.abs(cardA.opacity - cardA.revealProgress) < 1e-6)
        }}

        // Still fully held partway through the hold window (fade-in+hold =
        // 4000ms; sample at 3000ms).
        PauseAnimation { duration: 2000 }
        ScriptAction { script: {
            root.ok("still_held_before_fadeout", cardA.revealProgress > 0.95,
                "revealProgress at ~3000ms " + cardA.revealProgress.toFixed(3))
        }}

        // Into the fade-out window (starts at 4000ms; sample at 4700ms --
        // 1700ms after the previous sample at the 3000ms mark).
        PauseAnimation { duration: 1700 }
        ScriptAction { script: {
            root.ok("fading_out_before_total", cardA.revealProgress < 0.9,
                "revealProgress at ~4700ms " + cardA.revealProgress.toFixed(3))
        }}

        // Past the 5000ms total: finished() must have fired, close to 5000ms
        // (tolerant of scheduler jitter), and progress landed at 0.
        PauseAnimation { duration: 800 }
        ScriptAction { script: {
            root.ok("finished_fired", root.finishedFiredA)
            root.ok("finished_near_5000ms",
                Math.abs(root.finishedAtA - 5000) < 400,
                "finished at " + root.finishedAtA.toFixed(0) + "ms")
            root.ok("lands_at_zero", cardA.revealProgress < 0.05,
                "revealProgress " + cardA.revealProgress.toFixed(3))
        }}

        // ---- Phase 2: restart mid-flight ----------------------------------
        ScriptAction { script: { root.t1 = Date.now(); loaderB.active = true } }
        PauseAnimation { duration: 1000 }   // well into the hold window
        ScriptAction { script: {
            root.ok("card_b_held_before_restart", root.cardB.revealProgress > 0.95,
                "revealProgress " + root.cardB.revealProgress.toFixed(3))
            root.restartedAt = Date.now()
            root.cardB.restart()
            // A clean restart snaps progress back to 0 synchronously, then
            // the entrance animation begins again from there.
            root.ok("restart_resets_to_zero_immediately", root.cardB.revealProgress === 0,
                "revealProgress right after restart() " + root.cardB.revealProgress)
        }}

        // 1500ms after the restart call (2500ms after cardB was created --
        // well past the ORIGINAL 5000ms-from-creation mark's fade-out start
        // at 4000ms would NOT yet apply here since the clock was reset).
        PauseAnimation { duration: 1500 }
        ScriptAction { script: {
            root.ok("restarted_timeline_back_in_hold", root.cardB.revealProgress > 0.95,
                "revealProgress " + root.cardB.revealProgress.toFixed(3))
            root.ok("not_finished_yet_after_restart", !root.finishedFiredB)
        }}

        // finished() should now fire ~5000ms after the restart() call, not
        // ~5000ms after the original creation.
        PauseAnimation { duration: 3600 }
        ScriptAction { script: {
            root.ok("restarted_finished_fired", root.finishedFiredB)
            root.ok("restarted_finished_near_5000ms_after_restart",
                Math.abs(root.finishedAfterRestartMs - 5000) < 400,
                "finished at " + root.finishedAfterRestartMs.toFixed(0)
                    + "ms after restart()")
        }}

        ScriptAction { script: {
            console.log("=== TOAST TIMELINE TEST ===")
            for (const line of root.log) console.log(line)
            const failed = root.log.filter(l => l.indexOf("FAIL") === 0).length
            console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
            Qt.exit(failed === 0 ? 0 : 1)
        }}
    }
}
