// Headless state-machine test for lock/LockContext.qml, driven against
// lock/FakePamAuthenticator.qml (password "preview" succeeds, anything else
// fails). No WlSessionLock, no hyprlock, no loginctl -- this never touches
// a real session lock, real PAM, or opens a window.
//
// FakePamAuthenticator resolves one real event-loop tick later via its own
// Timer (see that file), same async shape as the real PAM adapter, so this
// is checked with real (short) Timers and generous margins -- the same
// technique test-reveal.qml and test-motion-live.qml already use -- rather
// than a synchronous fake clock.
//
// Also covers services/LockService.qml's fallback DECISION in isolation:
// two plain fake objects below stand in for lock/LockScreen.qml's public
// surface (lock()/unlock(), `locked`, `secure`, `context.failedToLock`) --
// no real WlSessionLock ever exists here -- and LockService's
// `fallbackLauncher` is swapped for a flag instead of the real
// hyprlock-launching command, so "did the fallback fire, and when" is
// asserted without this test ever running hyprlock itself.
import QtQuick
import Quickshell
import "lock"
import "services"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    FakePamAuthenticator {
        id: fakePam
    }
    LockContext {
        id: ctx
        authenticator: fakePam
    }

    // ---- lock/LockSurface.qml: item 1 (shared buffer fed from ANY
    // surface, Enter/Escape/Backspace) and item 2 (pill visible on every
    // surface, no "focused" guess) -- two surfaces sharing one context,
    // exactly like lock/LockScreen.qml wires one per monitor.
    FakePamAuthenticator {
        id: fakePamSurface
    }
    LockContext {
        id: surfaceCtx
        authenticator: fakePamSurface
    }
    LockSurface {
        id: surfaceA
        context: surfaceCtx
        width: 800; height: 600
    }
    LockSurface {
        id: surfaceB
        context: surfaceCtx
        width: 800; height: 600
    }

    function fakeKey(text, key) {
        return { key: key === undefined ? -1 : key, text: text === undefined ? "" : text, accepted: false }
    }

    Component.onCompleted: {
        // Pill must be visible on BOTH surfaces at once while locked -- not
        // gated on which one the compositor happens to focus.
        root.ok("pill_visible_on_surface_a", surfaceA.pillVisible === true)
        root.ok("pill_visible_on_surface_b", surfaceB.pillVisible === true)

        // Typing on surface A, then B, then A again must all land in the
        // SAME shared buffer.
        surfaceA._handleKeyEvent(root.fakeKey("p"))
        surfaceB._handleKeyEvent(root.fakeKey("r"))
        surfaceA._handleKeyEvent(root.fakeKey("e"))
        root.ok("shared_buffer_fed_from_any_surface",
            surfaceCtx.currentText === "pre", "currentText=" + surfaceCtx.currentText)

        // Backspace deletes from the shared buffer regardless of which
        // surface's key handler fires it.
        surfaceB._handleKeyEvent(root.fakeKey("", Qt.Key_Backspace))
        root.ok("backspace_deletes", surfaceCtx.currentText === "pr",
            "currentText=" + surfaceCtx.currentText)

        // Escape clears the shared buffer.
        surfaceA._handleKeyEvent(root.fakeKey("", Qt.Key_Escape))
        root.ok("escape_clears", surfaceCtx.currentText === "",
            "currentText=" + surfaceCtx.currentText)

        // Type the real preview password across both surfaces, then submit
        // via Enter from the OTHER surface -- proving the buffer really is
        // shared, not per-surface.
        for (const ch of "preview")
            surfaceA._handleKeyEvent(root.fakeKey(ch))
        root.ok("password_typed_via_surface",
            surfaceCtx.currentText === "preview", "currentText=" + surfaceCtx.currentText)

        surfaceB._handleKeyEvent(root.fakeKey("", Qt.Key_Return))
        root.ok("enter_submits", surfaceCtx.state === surfaceCtx.authenticating,
            "state=" + surfaceCtx.state)

        // 1. Wrong password -> authenticating -> failed (the "shake" state).
        ctx.submit("not-the-password")
    }

    Timer {
        interval: 50; running: true; repeat: false
        onTriggered: {
            root.ok("enter_submit_succeeds_reaches_unlocking",
                surfaceCtx.state === surfaceCtx.unlocking, "state=" + surfaceCtx.state)
        }
    }

    Timer {
        interval: 80; running: true; repeat: false
        onTriggered: {
            root.ok("wrong_password_reaches_failed", ctx.state === ctx.failed,
                "state=" + ctx.state)
            root.ok("failure_clears_password", ctx.currentText === "",
                "currentText=" + JSON.stringify(ctx.currentText))

            // Simulate LockSurface's shake animation finishing.
            ctx.acknowledgeFailure()
            root.ok("acknowledge_failure_returns_to_locked",
                ctx.state === ctx.locked, "state=" + ctx.state)

            // 2. Correct password -> authenticating -> unlocking.
            ctx.submit("preview")
        }
    }

    Timer {
        interval: 160; running: true; repeat: false
        onTriggered: {
            root.ok("success_reaches_unlocking", ctx.state === ctx.unlocking,
                "state=" + ctx.state)
            root.ok("success_clears_password", ctx.currentText === "",
                "currentText=" + JSON.stringify(ctx.currentText))
            root.ok("not_yet_unlocked_before_animation_complete",
                ctx.state !== ctx.unlocked, "state=" + ctx.state)

            // Only the animation-complete call may move it to `unlocked`.
            ctx.finishUnlockAnimation()
            root.ok("unlocked_only_after_finishUnlockAnimation",
                ctx.state === ctx.unlocked, "state=" + ctx.state)
            root.ok("still_no_leftover_password",
                ctx.currentText === "", "currentText=" + JSON.stringify(ctx.currentText))

            root.runSecondLockCycleTest()
        }
    }

    // ---- second-lock-cycle regression: lock/LockContext.qml's reset()
    // must actually re-arm state to `locked` even when called from
    // `unlocked` -- this is what lock/LockScreen.qml's lock()/unlock() do
    // on every real cycle (see those functions' bodies). Uses a dedicated
    // context+surface pair driven through one full unlock, then simulates
    // LockScreen.unlock()'s and lock()'s reset() calls directly (no real
    // WlSessionLock/Wayland surface needed -- reset() and the surface's
    // `visible` bindings are pure QtObject/Item state).
    FakePamAuthenticator {
        id: fakePamCycle
    }
    LockContext {
        id: cycleCtx
        authenticator: fakePamCycle
    }
    LockSurface {
        id: cycleSurface
        context: cycleCtx
        width: 800; height: 600
    }

    function runSecondLockCycleTest(): void {
        root.ok("cycle_starts_locked", cycleCtx.state === cycleCtx.locked,
            "state=" + cycleCtx.state)
        root.ok("cycle_pill_visible_before_first_unlock", cycleSurface.pillVisible === true)

        cycleCtx.submit("preview")
        cycleTimer1.start()
    }

    Timer {
        id: cycleTimer1
        interval: 60; running: false; repeat: false
        onTriggered: {
            root.ok("cycle_reaches_unlocking", cycleCtx.state === cycleCtx.unlocking,
                "state=" + cycleCtx.state)

            // Mirrors LockSurface's real completion path: both animation
            // parts finish, so the caller is told the animation is done.
            cycleCtx.finishUnlockAnimation()
            root.ok("cycle_reaches_unlocked", cycleCtx.state === cycleCtx.unlocked,
                "state=" + cycleCtx.state)
            root.ok("cycle_pill_hidden_once_unlocked", cycleSurface.pillVisible === false)

            // Mirrors lock/LockScreen.qml's unlock(): sessionLock.locked =
            // false; lockContext.reset() -- called once the real session
            // has already unlocked.
            cycleCtx.reset()

            // Mirrors lock/LockScreen.qml's lock() on the SECOND lock of
            // the session: lockContext.reset(); sessionLock.locked = true.
            cycleCtx.reset()

            root.ok("second_lock_reset_returns_to_locked",
                cycleCtx.state === cycleCtx.locked, "state=" + cycleCtx.state)
            root.ok("second_lock_pill_visible_again",
                cycleSurface.pillVisible === true, "pillVisible=" + cycleSurface.pillVisible)

            root.runLockServiceTests()
        }
    }

    // ---- services/LockService.qml fallback wiring -----------------------

    property bool fallbackAFired: false
    property QtObject fakeLockA: QtObject {
        id: fakeLockAObj
        property bool locked: false
        property bool secure: false
        property QtObject context: QtObject { signal failedToLock() }
        function lock(): void { fakeLockAObj.locked = true }
        function unlock(): void { fakeLockAObj.locked = false }
    }

    property bool fallbackBFired: false
    property QtObject fakeLockB: QtObject {
        id: fakeLockBObj
        property bool locked: false
        property bool secure: false
        property QtObject context: QtObject { signal failedToLock() }
        function lock(): void { fakeLockBObj.locked = true }
        function unlock(): void { fakeLockBObj.locked = false }
    }

    function runLockServiceTests(): void {
        // Test A: the fake never becomes secure -> fallback must fire on
        // LockService's 2s not-secure timeout.
        LockService.registerLockScreen(fakeLockA)
        LockService.fallbackLauncher = function() { root.fallbackAFired = true }
        LockService.engage()
        root.ok("engage_calls_lock_on_fake", fakeLockA.locked === true,
            "locked=" + fakeLockA.locked)
        secureTimeoutCheck.start()
    }

    Timer {
        id: secureTimeoutCheck
        interval: 2300; running: false; repeat: false
        onTriggered: {
            root.ok("secure_timeout_triggers_fallback",
                root.fallbackAFired === true, "fallbackAFired=" + root.fallbackAFired)
            root.ok("secure_timeout_fallback_unlocks_fake",
                fakeLockA.locked === false, "locked=" + fakeLockA.locked)
            root.ok("secure_timeout_fallback_clears_pending",
                LockService.pending === false, "pending=" + LockService.pending)

            root.runFailedToLockTest()
        }
    }

    function runFailedToLockTest(): void {
        // Test B: same fallback, but fired via context.failedToLock well
        // before the 2s timeout would have elapsed -- must not wait for it.
        LockService.registerLockScreen(fakeLockB)
        LockService.fallbackLauncher = function() { root.fallbackBFired = true }
        LockService.engage()
        failedToLockDelay.start()
    }

    Timer {
        id: failedToLockDelay
        interval: 100; running: false; repeat: false
        onTriggered: {
            fakeLockB.context.failedToLock()
            failedToLockCheck.start()
        }
    }

    Timer {
        id: failedToLockCheck
        interval: 100; running: false; repeat: false
        onTriggered: {
            root.ok("failed_to_lock_triggers_fallback_immediately",
                root.fallbackBFired === true, "fallbackBFired=" + root.fallbackBFired)
            root.ok("failed_to_lock_fallback_unlocks_fake",
                fakeLockB.locked === false, "locked=" + fakeLockB.locked)
            root.ok("failed_to_lock_fallback_clears_pending",
                LockService.pending === false, "pending=" + LockService.pending)

            root.finish()
        }
    }

    function finish(): void {
        const passed = root.log.filter(l => l.startsWith("PASS")).length
        for (const l of root.log) console.log(l)
        console.log("=== " + passed + "/" + root.log.length + " passed ===")
        Qt.quit()
    }
}
