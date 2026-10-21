pragma ComponentBehavior: Bound
import QtQuick

/**
 * LockContext -- the lock screen's state machine, shared across every
 * screen's LockSurface (one password typed on any monitor unlocks all of
 * them). Deliberately holds NO Quickshell.Wayland / Quickshell.Services.Pam
 * imports itself: PAM is reached only through the injected `authenticator`,
 * so a headless test (test-lock.qml) can drive the exact same state machine
 * against a fake without ever touching real PAM or a real session lock.
 *
 * States: locked -> authenticating -> (failed -> locked) | (unlocking ->
 * unlocked). `unlocked` is only ever reached via finishUnlockAnimation(),
 * called by the caller once its own unlock animation sequence has actually
 * finished playing -- PAM success alone is not enough to end the session,
 * on purpose (see the phase's design: the pill must already be sitting at
 * the resting island's geometry before the real island appears).
 *
 * Security: `currentText` is the password buffer. It is handed to
 * `authenticator.start()` and to nothing else -- never logged, never
 * persisted -- and is cleared on both failure and success (see
 * `_onAuthResult`), never left sitting around after a PAM round trip ends.
 */
QtObject {
    id: root

    readonly property string locked: "locked"
    readonly property string authenticating: "authenticating"
    readonly property string failed: "failed"
    readonly property string unlocking: "unlocking"
    readonly property string unlocked: "unlocked"

    property string state: root.locked
    property string currentText: ""

    // Injectable PAM boundary. Must expose:
    //   - start(password): begin one auth attempt
    //   - abort(): cancel an in-flight attempt
    //   - respond(text): answer a PAM prompt (real adapter only)
    //   - signal authResult(success: bool): fires exactly once per attempt
    // lock/PamAuthenticator.qml is the real adapter (Quickshell.Services.Pam,
    // config "hyprlock"); lock/FakePamAuthenticator.qml is the test/preview
    // double. Required so nothing can accidentally construct a LockContext
    // backed by nothing.
    required property QtObject authenticator

    signal wrongPassword()
    signal unlockStarted()
    // Raised when the caller (lock/LockScreen.qml) detects WlSessionLock
    // could not lock the session securely, so the wiring phase can fall
    // back to hyprlock. LockContext itself never touches WlSessionLock --
    // it only re-broadcasts this on the caller's behalf, via
    // reportLockFailure(), so tests can assert on it without a real
    // Wayland session lock existing.
    signal failedToLock()

    function submit(password) {
        if (root.state !== root.locked && root.state !== root.failed) return
        root.currentText = password
        root.state = root.authenticating
        root.authenticator.start(password)
    }

    function _onAuthResult(success) {
        if (root.state !== root.authenticating) return
        if (success) {
            root.currentText = ""
            root.state = root.unlocking
            root.unlockStarted()
        } else {
            root.currentText = ""
            root.state = root.failed
            root.wrongPassword()
        }
    }

    // Called by the caller once its shake animation for `failed` has
    // finished playing -- returns to `locked` so the pill accepts input
    // again. Not automatic: the state machine itself has no timers.
    function acknowledgeFailure() {
        if (root.state === root.failed) root.state = root.locked
    }

    // Called by the caller ONLY once the full unlock animation sequence
    // (letters diffuse out, steppers break, pill arrives at the island's
    // geometry) has actually finished. This is the one moment the real
    // session may unlock.
    function finishUnlockAnimation() {
        if (root.state !== root.unlocking) return
        root.state = root.unlocked
    }

    function reportLockFailure() {
        root.failedToLock()
    }

    function reset() {
        root.currentText = ""
        // Re-arm to `locked` from ANY state except `unlocking` itself --
        // interrupting a running unlock animation would be wrong, but
        // `unlocked` must NOT be preserved here. The caller (lock/
        // LockScreen.qml) calls reset() both right after the real session
        // unlocks (state is `unlocked` at that point) and again right
        // before re-locking -- if `unlocked` survived that, state would
        // never leave `unlocked` on the next lock, leaving background,
        // quoteText and the pill (all bound to `state !== unlocked`) stuck
        // invisible forever after the first unlock -- the second-lock
        // "blank screen, no input" bug.
        if (root.state !== root.unlocking)
            root.state = root.locked
    }

    Component.onCompleted: root.authenticator.authResult.connect(root._onAuthResult)
}
