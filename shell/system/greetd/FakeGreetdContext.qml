pragma ComponentBehavior: Bound
import QtQuick

// Item, not QtObject, so this can own a child `Timer` element (plain
// QtObject has no default property for QML children -- see
// lock/FakePamAuthenticator.qml's own header for the identical reasoning).
/**
 * FakeGreetdContext -- DEV/TEST-ONLY double for GreetdContext.qml's public
 * surface. Deliberately has NO `import Quickshell.Services.Greetd`
 * anywhere in this file (mirrors lock/FakePamAuthenticator.qml's own
 * header commitment) so nothing that uses it can ever create a real
 * greetd session or call Greetd.launch, even by accident -- there is no
 * Greetd singleton reachable from this file at all.
 *
 * Used ONLY by the separate, dev-only greeter-test.qml sitting next to
 * this file. install.sh never copies either file into the installed
 * tree (see install.sh's header comment) -- this is the "stronger option"
 * for keeping test mode out of production: it is not merely env-gated,
 * it is physically absent from what actually runs as the `greeter` user.
 *
 * Password "test" succeeds; anything else fails. Result arrives one
 * event-loop tick later via a real Timer, matching FakePamAuthenticator's
 * own async shape. finishUnlockAnimation() does NOT launch anything --
 * greeter-test.qml is responsible for quitting the app on `unlocked`.
 */
Item {
    id: root
    visible: false

    readonly property string successPassword: "test"

    readonly property string locked: "locked"
    readonly property string authenticating: "authenticating"
    readonly property string failed: "failed"
    readonly property string unlocking: "unlocking"
    readonly property string unlocked: "unlocked"

    property string state: root.locked
    property string currentText: ""

    signal wrongPassword()
    signal unlockStarted()
    signal failedToLock()

    function submit(password) {
        if (root.state !== root.locked && root.state !== root.failed) return
        root.currentText = password
        root.state = root.authenticating
        resultTimer.password = password
        resultTimer.restart()
    }

    function acknowledgeFailure() {
        if (root.state === root.failed) root.state = root.locked
    }

    function finishUnlockAnimation() {
        if (root.state !== root.unlocking) return
        root.state = root.unlocked
    }

    Timer {
        id: resultTimer
        property string password: ""
        interval: 20
        repeat: false
        onTriggered: {
            if (resultTimer.password === root.successPassword) {
                root.currentText = ""
                root.state = root.unlocking
                root.unlockStarted()
            } else {
                root.currentText = ""
                root.state = root.failed
                root.wrongPassword()
            }
        }
    }
}
