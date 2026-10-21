// Visual-check-only preview for lock/LockSurface.qml. A plain FloatingWindow
// -- NEVER a real WlSessionLock -- sized like one 1920x1080 screen, driven
// by lock/FakePamAuthenticator.qml so no real PAM/hyprlock/loginctl is ever
// touched. Drive it via its own IPC target rather than synthetic input:
//
//   qs -p ./preview-lock.qml &
//   qs ipc call lockpreview submit preview   # succeeds, plays the unlock seq
//   qs ipc call lockpreview submit wrong     # fails, plays the shake
//   qs ipc call lockpreview reset            # back to a fresh locked state
//
// Same shape as services/PolkitPreviewService.qml's `polkit preview` /
// `polkit previewFailure` IPC target.
import QtQuick
import Quickshell
import Quickshell.Io
import "lock"

FloatingWindow {
    id: window
    title: "lock preview"
    implicitWidth: 1920
    implicitHeight: 1080

    Rectangle {
        anchors.fill: parent
        color: "#202027" // flat stand-in desktop background, not the lock fill
    }

    FakePamAuthenticator {
        id: fakePam
    }
    LockContext {
        id: previewContext
        authenticator: fakePam
    }

    LockSurface {
        anchors.fill: parent
        context: previewContext
    }

    IpcHandler {
        target: "lockpreview"

        function submit(password: string): void {
            previewContext.submit(password)
        }

        // Force back to a fresh `locked` view for re-capturing, even from
        // `unlocked` -- context.reset() deliberately won't undo a real
        // unlock, but this is a preview-only convenience, not a security
        // boundary, so it may set state directly.
        function reset(): void {
            previewContext.currentText = ""
            previewContext.state = previewContext.locked
        }
    }
}
