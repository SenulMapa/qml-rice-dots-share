import QtQuick

/**
 * FakePamAuthenticator -- the test/preview double for lock/LockContext.qml's
 * `authenticator` interface. Deliberately has no `import
 * Quickshell.Services.Pam` anywhere in this file, so nothing that uses it
 * (test-lock.qml, preview-lock.qml) can ever start a real PAM conversation
 * even by accident.
 *
 * Same call surface as lock/PamAuthenticator.qml: start(password), abort(),
 * respond() (no-op here), and authResult(bool). Password "preview" (see
 * `successPassword`) succeeds; anything else fails. Result arrives one
 * event-loop tick later via a real Timer -- not synchronous -- so callers
 * exercise the exact same async shape the real adapter has.
 */
Item {
    id: root
    visible: false

    property bool active: false
    property string successPassword: "preview"
    signal authResult(bool success)

    function start(password) {
        root.active = true
        resultTimer.password = password
        resultTimer.restart()
    }
    function abort() {
        root.active = false
        resultTimer.stop()
    }
    function respond(text) {
        // No real PAM conversation exists to answer.
    }

    Timer {
        id: resultTimer
        property string password: ""
        interval: 20
        repeat: false
        onTriggered: {
            root.active = false
            root.authResult(resultTimer.password === root.successPassword)
        }
    }
}
