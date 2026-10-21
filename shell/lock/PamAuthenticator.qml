import QtQuick
import Quickshell.Services.Pam

/**
 * PamAuthenticator -- the real PAM boundary for lock/LockContext.qml.
 * config "hyprlock" (/etc/pam.d/hyprlock exists). Mirrors the working
 * pattern in ~/.config/quickshell/end4-pC/modules/common/panels/lock/
 * LockContext.qml's PamContext block, just split out behind the
 * start(password)/abort()/respond()/authResult(bool) interface
 * lock/LockContext.qml expects.
 *
 * The password is held in `_pending` only for the span of one PAM
 * conversation -- set at start(), handed to PamContext.respond() when
 * asked, and cleared the instant the conversation completes either way.
 * Never logged, never exposed as a property read from outside this file.
 */
Item {
    id: root
    visible: false

    readonly property bool active: pam.active
    signal authResult(bool success)

    property string _pending: ""

    function start(password) {
        root._pending = password
        pam.start()
    }
    function abort() {
        if (pam.active) pam.abort()
        root._pending = ""
    }
    function respond(text) {
        pam.respond(text)
    }

    PamContext {
        id: pam
        config: "hyprlock"

        // pam_unix asks for a response for the password prompt; this is the
        // only place the password ever leaves `_pending`.
        onPamMessage: {
            if (this.responseRequired) this.respond(root._pending)
        }

        onCompleted: result => {
            root._pending = ""
            root.authResult(result === PamResult.Success)
        }
    }
}
