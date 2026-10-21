pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * PolkitPreviewService -- a visual-check-only stand-in for PolkitService,
 * gated by QMLRICE_POLKIT_PREVIEW=1. panels/PolkitPage.qml renders IDENTICAL
 * markup against either controller: both expose the exact same property/
 * function surface (active, message, actionId, identities, selectedIdentity,
 * prompt, echoResponse, errorText, errorIsError, busy, selectIdentity(),
 * submit(), cancel()). This file never imports or references
 * Quickshell.Services.Polkit -- it cannot touch PolkitAgent/AuthFlow even by
 * accident.
 *
 * Without QMLRICE_POLKIT_PREVIEW=1 the `polkit preview` IPC target below does
 * not exist at all (LazyLoader.active gates whether the IpcHandler is ever
 * instantiated, not just whether it does anything) -- `qs ipc call polkit
 * preview` fails with "no such target" rather than a scripted no-op.
 */
QtObject {
    id: root

    property bool previewing: false
    readonly property bool active: previewing

    readonly property string message: "Authentication is required to run the program as the super user"
    readonly property string actionId: "org.freedesktop.policykit.exec"
    readonly property var identities: [
        { displayName: "Adam (administrator)" },
        { displayName: "root" }
    ]
    property var selectedIdentity: identities[0]

    readonly property string prompt: "Password"
    readonly property bool echoResponse: false

    property string errorText: ""
    property bool errorIsError: false
    property bool busy: false

    function selectIdentity(identity): void {
        selectedIdentity = identity
    }

    function start(): void {
        errorText = ""
        errorIsError = false
        busy = false
        selectedIdentity = identities[0]
        previewing = true
    }

    // Preview submit/cancel only ever close the page, EXCEPT a submit of the
    // literal string "wrong", which shows the failure state first so it can
    // be screenshotted -- see the task's preview capture step.
    function submit(text: string): void {
        if (text === "wrong") {
            errorText = "Authentication failed"
            errorIsError = true
            busy = false
            return
        }
        errorText = ""
        errorIsError = false
        busy = false
        previewing = false
    }

    function cancel(): void {
        errorText = ""
        errorIsError = false
        busy = false
        previewing = false
    }

    property LazyLoader previewIpcLoader: LazyLoader {
        active: Quickshell.env("QMLRICE_POLKIT_PREVIEW") === "1"

        IpcHandler {
            target: "polkit"

            function preview(): string {
                root.start()
                return "POLKIT_PREVIEW_SUCCESS"
            }

            // Testability hook for the verification capture step (the task's
            // "/tmp/pk-error.png" shot): drives submit("wrong") directly
            // through the same code path the Authenticate button uses,
            // rather than requiring synthetic keyboard input into the field.
            function previewFailure(): string {
                root.start()
                root.submit("wrong")
                return "POLKIT_PREVIEW_FAILURE_SUCCESS"
            }
        }
    }
}
