pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Greetd

// Item, not QtObject, purely so this can own a child `Connections` element
// -- plain QtObject has no default property to parent QML children under
// (see lock/PamAuthenticator.qml's own header for the identical reasoning:
// it is an invisible Item for exactly this reason). `visible: false` since
// nothing here should ever paint anything.

/**
 * GreetdContext -- PRODUCTION-ONLY greeter state machine. Exposes the exact
 * same public surface lock/AsciiLockSurface.qml already binds to on
 * lock/LockContext.qml (state string + the five state-token properties,
 * read/write `currentText`, submit(password)/acknowledgeFailure()/
 * finishUnlockAnimation(), plus wrongPassword()/unlockStarted()/
 * failedToLock() signals for interface parity) so AsciiLockSurface can be
 * hosted here completely UNMODIFIED -- this file contains zero changes to
 * anything under lock/.
 *
 * Why not just plug into LockContext as another `authenticator`? greetd's
 * real protocol (createSession -> one or more authMessage prompts ->
 * respond -> authFailure | state goes ReadyToLaunch) is a multi-message
 * conversation, not LockContext's injected start(password)/authResult(bool)
 * shape (that boundary exists so PamAuthenticator/FakePamAuthenticator can
 * be swapped under a real session lock). So this file reimplements
 * LockContext's STATE MACHINE directly against Quickshell.Services.Greetd
 * instead of trying to squeeze greetd's protocol through that narrower
 * interface.
 *
 * Fixed single user, no picker: `username` is hardcoded (this laptop has
 * exactly one account). `launchCommand` is the user's session launcher
 * (/usr/bin/start-hyprland via the hyprland.desktop Exec=) -- NOT niri
 * (niri only hosts this greeter UI on the bare VT before any session
 * exists; the real session is Hyprland).
 *
 * Launch discipline (mirrors LockContext exactly): greetd reporting
 * GreetdState.ReadyToLaunch does NOT call Greetd.launch() immediately --
 * it only flips local `state` to `unlocking` and lets AsciiLockSurface's
 * own unlock animation play out. The real Greetd.launch() call (which
 * actually starts the session and, with quit=true, tears this greeter
 * down) happens ONLY from finishUnlockAnimation(), called by the surface
 * once its animation has actually finished -- see lock/LockContext.qml's
 * own header for why this ordering matters.
 *
 * Security:
 *  - No autologin: submit() is the only path into createSession(), and it
 *    requires a `locked`/`failed` state (i.e. a real keypress+Enter from
 *    the surface).
 *  - `currentText` (the password buffer) is never logged -- every
 *    console.warn below logs only greetd's own message/error strings, never
 *    root.currentText -- and is cleared immediately on failure and the
 *    instant greetd reports ReadyToLaunch, exactly like LockContext clears
 *    it on both its own failure and success paths.
 *  - Authentication is decided EXCLUSIVELY by greetd/PAM: this file never
 *    computes a pass/fail verdict itself, only reacts to
 *    authFailure/stateChanged signals greetd emits.
 *  - No test/fake path exists anywhere in this file, and this file never
 *    imports or references FakeGreetdContext.qml -- that lives only in the
 *    separate, dev-only greeter-test.qml, which install.sh never copies to
 *    the installed tree (see install.sh's header comment).
 */
Item {
    id: root
    visible: false

    readonly property string username: "@GREETER_USER@"
    // install.sh fills in the target user's name when installing.
    // Absolute, matching /usr/share/wayland-sessions/hyprland.desktop's Exec
    // (what the old greeter launches) -- not left to greetd's session PATH.
    readonly property var launchCommand: ["/usr/bin/start-hyprland"]

    readonly property string locked: "locked"
    readonly property string authenticating: "authenticating"
    readonly property string failed: "failed"
    readonly property string unlocking: "unlocking"
    readonly property string unlocked: "unlocked"

    property string state: root.locked
    property string currentText: ""

    signal wrongPassword()
    signal unlockStarted()
    // No WlSessionLock exists in the greeter (there is no session yet to
    // fail to lock) -- kept only so this file's signal surface matches
    // LockContext's exactly, in case a future caller expects it.
    signal failedToLock()

    function submit(password) {
        if (root.state !== root.locked && root.state !== root.failed) return
        if (!Greetd.available) {
            console.warn("GreetdContext: Greetd service unavailable")
            return
        }
        root.currentText = password
        root.state = root.authenticating
        Greetd.createSession(root.username)
    }

    // Called by the surface once its `failed` shake animation has finished
    // playing -- returns to `locked` so the pill accepts input again.
    function acknowledgeFailure() {
        if (root.state === root.failed) root.state = root.locked
    }

    // Called by the surface ONLY once its full unlock animation sequence
    // has actually finished. This is the one moment greetd may actually be
    // told to launch the session.
    function finishUnlockAnimation() {
        if (root.state !== root.unlocking) return
        root.state = root.unlocked
        Greetd.launch(root.launchCommand, [], true)
    }

    Connections {
        target: Greetd

        function onAuthMessage(message, error, responseRequired, echoResponse) {
            // pam_unix's password prompt is the only responseRequired
            // message this single-factor flow expects; anything else
            // (info/error banners) gets an empty response so the
            // conversation can proceed without ever needing a second UI.
            if (responseRequired)
                Greetd.respond(root.currentText)
            else
                Greetd.respond("")
        }

        function onAuthFailure(message) {
            console.warn("GreetdContext: auth failure:", message)
            root.currentText = ""
            root.state = root.failed
            root.wrongPassword()
        }

        function onError(error) {
            console.warn("GreetdContext: greetd error:", error)
            root.currentText = ""
            root.state = root.failed
            root.wrongPassword()
        }

        function onStateChanged() {
            if (Greetd.state === GreetdState.ReadyToLaunch) {
                root.currentText = ""
                root.state = root.unlocking
                root.unlockStarted()
            }
        }
    }
}
