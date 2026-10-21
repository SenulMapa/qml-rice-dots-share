// Component test for components/Reveal.qml (island/IslandExpanded.qml's
// staggered fade-in). Verifies the stagger schedule, that opacity finishes
// before the translate, that exit is fast/synchronised/unstaggered and
// always wins over an in-flight entrance, that reducedMotion collapses
// everything to instant, and that a replay needs an actual token bump --
// not just any property changing.
//
// Timing is checked against real elapsed time via short real Timers (the
// same technique test-motion.qml and test-wavetrack.qml already use) rather
// than a literal fake clock, since components/Reveal.qml's animations are
// plain QML NumberAnimations with no injectable time source. Every
// assertion samples state well clear of its expected transition edge (tens
// of ms of margin either side) so this isn't flaky under CI-ish scheduling
// jitter.
import QtQuick
import Quickshell
import "components"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    function near(value, target, tolerance) {
        return Math.abs(value - target) <= tolerance
    }

    // ---- Pure stagger-schedule formula: no timing involved at all. ----
    Reveal {
        id: order0
        order: 0
        Rectangle { width: 4; height: 4 }
    }
    Reveal {
        id: order1
        order: 1
        Rectangle { width: 4; height: 4 }
    }
    Reveal {
        id: order7
        order: 7
        Rectangle { width: 4; height: 4 }
    }
    Reveal {
        id: order8
        order: 8
        Rectangle { width: 4; height: 4 }
    }
    Reveal {
        id: order20
        order: 20
        Rectangle { width: 4; height: 4 }
    }

    // ---- Entrance timing, order 0 (no stagger). ----
    Reveal {
        id: enter0
        order: 0
        Rectangle { width: 4; height: 4 }
    }

    // ---- Entrance timing, order 2 (70ms stagger). ----
    Reveal {
        id: enter2
        order: 2
        Rectangle { width: 4; height: 4 }
    }

    // ---- Exit: fast, unstaggered, wins over a pending entrance. ----
    Reveal {
        id: exiter
        order: 7
        Rectangle { width: 4; height: 4 }
    }

    // ---- reducedMotion: instant, no timers. ----
    Reveal {
        id: reduced
        order: 5
        reducedMotion: true
        Rectangle { width: 4; height: 4 }
    }

    // ---- Replay: only a token bump replays; another property doesn't. ----
    Reveal {
        id: replay
        order: 0
        Rectangle { width: 4; height: 4 }
    }

    // t=0ms, but deferred one event-loop tick past construction (rather
    // than Component.onCompleted) so this doesn't depend on completion
    // ordering between ShellRoot and its Reveal children.
    Timer {
        interval: 0; running: true; repeat: false
        onTriggered: {
            // Stagger schedule -- pure function of `order`, checkable immediately.
            root.ok("stagger_order0", order0.staggerDelay === 0,
                "" + order0.staggerDelay)
            root.ok("stagger_order1", order1.staggerDelay === 35,
                "" + order1.staggerDelay)
            root.ok("stagger_order7_cap", order7.staggerDelay === 245,
                "" + order7.staggerDelay)
            root.ok("stagger_order8_capped_same_as_7",
                order8.staggerDelay === order7.staggerDelay,
                order8.staggerDelay + " vs " + order7.staggerDelay)
            root.ok("stagger_order20_capped_same_as_7",
                order20.staggerDelay === order7.staggerDelay,
                "" + order20.staggerDelay)

            // reducedMotion: instant, no phased timers at all.
            root.ok("reduced_motion_instant_opacity", reduced.debugOpacity === 1,
                "" + reduced.debugOpacity)
            root.ok("reduced_motion_instant_riseY", reduced.debugRiseY === 0,
                "" + reduced.debugRiseY)
            root.ok("reduced_motion_no_entrance_timer",
                !reduced.debugEntranceDelayRunning && !reduced.debugEntranceRunning,
                "delay=" + reduced.debugEntranceDelayRunning
                    + " anim=" + reduced.debugEntranceRunning)
        }
    }

    // t=15ms: order0 has started its (0ms-delay) entrance; order2's 70ms
    // delay has not fired yet.
    Timer {
        interval: 15; running: true; repeat: false
        onTriggered: {
            root.ok("enter0_started_promptly", enter0.debugOpacity > 0,
                "" + enter0.debugOpacity)
            root.ok("enter2_still_delayed",
                enter2.debugOpacity === 0 && enter2.debugEntranceDelayRunning,
                "opacity=" + enter2.debugOpacity
                    + " delayRunning=" + enter2.debugEntranceDelayRunning)

            // Exit beats a pending entrance: flip it mid-delay (order 7 ->
            // 245ms stagger, well before it would have fired) and confirm
            // the delay is cancelled and the exit fade starts immediately.
            exiter.exiting = true
        }
    }

    // t=45ms: exit was requested at t=15ms; confirm it preempted the
    // 245ms-away entrance and is already fading (not still waiting).
    Timer {
        interval: 45; running: true; repeat: false
        onTriggered: {
            root.ok("exit_cancels_pending_entrance_delay",
                !exiter.debugEntranceDelayRunning,
                "" + exiter.debugEntranceDelayRunning)
            root.ok("exit_running_not_delayed", exiter.debugExitRunning,
                "" + exiter.debugExitRunning)
            root.ok("exit_has_started_fading", exiter.debugOpacity < 1,
                "" + exiter.debugOpacity)
        }
    }

    // t=100ms: enter2's 70ms delay has fired; its opacity/translate anims
    // should now be mid-flight.
    Timer {
        interval: 100; running: true; repeat: false
        onTriggered: {
            root.ok("enter2_animating_after_delay",
                enter2.debugOpacity > 0 && enter2.debugOpacity < 1,
                "" + enter2.debugOpacity)
        }
    }

    // t=160ms: exiter's 120ms exit fade (started ~t=15ms) is long done.
    Timer {
        interval: 160; running: true; repeat: false
        onTriggered: {
            root.ok("exit_completes_in_120ms", exiter.debugOpacity === 0,
                "" + exiter.debugOpacity)
        }
    }

    // t=220ms: order0's opacity anim (200ms, no delay) is done; its
    // translate (280ms) is NOT -- opacity completes before the translate.
    Timer {
        interval: 220; running: true; repeat: false
        onTriggered: {
            root.ok("enter0_opacity_done_by_220ms", enter0.debugOpacity === 1,
                "" + enter0.debugOpacity)
            root.ok("enter0_translate_still_running_at_220ms",
                enter0.debugRiseY > 0, "" + enter0.debugRiseY)

            // Replay probe: let it fully settle, then change something that
            // is NOT the token and confirm nothing replays.
            replay.order = 3
        }
    }

    // t=260ms: both of order0's animations are done.
    Timer {
        interval: 260; running: true; repeat: false
        onTriggered: {
            root.ok("enter0_fully_settled", near(enter0.debugRiseY, 0, 0.5),
                "" + enter0.debugRiseY)
            root.ok("replay_settled_before_probe", replay.debugOpacity === 1,
                "" + replay.debugOpacity)
        }
    }

    // t=300ms: `order` changed at t=220ms with no token bump -- must NOT
    // have replayed the entrance (opacity would have dropped back to 0).
    Timer {
        interval: 300; running: true; repeat: false
        onTriggered: {
            root.ok("no_replay_on_non_token_property_change",
                replay.debugOpacity === 1, "" + replay.debugOpacity)

            // Back to order 0 (it was bumped to 3 above purely to prove a
            // property change alone doesn't replay) so the timing below
            // stays a clean 0ms-stagger case. Now bump the token and
            // confirm a REAL replay does happen.
            replay.order = 0
            replay.token++
        }
    }

    // t=310ms: right after the token bump, the entrance should have reset
    // (opacity back to 0, mid the 0ms-stagger delay/animation restart).
    Timer {
        interval: 310; running: true; repeat: false
        onTriggered: {
            root.ok("token_bump_replays_entrance", replay.debugOpacity < 1,
                "" + replay.debugOpacity)
        }
    }

    // t=550ms: replay's re-triggered entrance (0ms delay + 280ms translate)
    // has had time to fully settle again.
    Timer {
        interval: 550; running: true; repeat: false
        onTriggered: {
            root.ok("token_bump_replay_resettles", replay.debugOpacity === 1,
                "" + replay.debugOpacity)

            // ---- HOST PATTERN REGRESSION: exiting stale when active flips true. ----
            // The host flips active=true and bumps token in onActiveChanged; if
            // onActiveChanged runs before exiting binding re-evaluates, onTokenChanged
            // reads exiting===true and skips playEnter(), leaving the Reveal stuck
            // at opacity 0. This case reproduces that exact timing.
            hostPattern.active = true
        }
    }

    // A host Item with `active: false` property, and a Reveal with `exiting: !host.active`.
    Item {
        id: hostPattern
        property bool active: false
        property int token: 0
        onActiveChanged: if (active) token++
    }
    Reveal {
        id: hostRevealer
        order: 0
        token: hostPattern.token
        exiting: !hostPattern.active
        Rectangle { width: 4; height: 4 }
    }

    // t=1050ms: after active=true and the token bump, the Reveal should have
    // played entrance and be visible (opacity ~= 1), not stuck at 0.
    Timer {
        interval: 1050; running: true; repeat: false
        onTriggered: {
            root.ok("host_pattern_active_bump_reveals",
                root.near(hostRevealer.debugOpacity, 1, 0.1),
                "" + hostRevealer.debugOpacity)

            console.log("=== REVEAL TEST ===")
            for (const line of root.log)
                console.log(line)
            const failed = root.log.filter(l => l.startsWith("FAIL")).length
            console.log("=== " + (root.log.length - failed) + "/"
                + root.log.length + " passed ===")
            Qt.quit()
        }
    }
}
