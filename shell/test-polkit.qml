// Component test for PolkitPage, driven against a mock controller exposing
// the same property/function surface as services/PolkitService.qml and
// services/PolkitPreviewService.qml (see panels/PolkitPage.qml's header
// comment). No PolkitAgent/AuthFlow is touched here.
//
// "Escape calls cancel" is exercised by calling doCancel() directly -- the
// exact one-line body Keys.onEscapePressed delegates to in
// panels/PolkitPage.qml -- rather than a synthetic OS key event, so this
// test never opens a window that could receive real input.
//
// "completion closes" is scoped to what PolkitPage itself owns: it does not
// decide when to hide (island/Island.qml does, by watching
// controller.active), but it must tear down its own state -- clear the
// field -- whenever its host hides it, for any reason including completion.
import QtQuick
import Quickshell
import "panels"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    QtObject {
        id: mock
        property bool active: true
        property string message: "Authentication is required to run the program as the super user"
        property string actionId: "org.freedesktop.policykit.exec"
        property var identities: [{ displayName: "root" }]
        property var selectedIdentity: identities[0]
        property string prompt: "Password"
        property bool echoResponse: false
        property string errorText: ""
        property bool errorIsError: false
        property bool busy: false

        property int submitCount: 0
        property int cancelCount: 0
        property string lastSubmitted: "unset"

        function selectIdentity(identity): void { selectedIdentity = identity }

        function submit(text): void {
            submitCount++
            lastSubmitted = text
            busy = true
        }

        function cancel(): void {
            cancelCount++
        }

        // Mirrors exactly what services/PolkitService.qml does on a real
        // authenticationFailed signal.
        function simulateFailed(supplementary): void {
            busy = false
            errorText = (supplementary && supplementary.length > 0)
                ? supplementary : "Authentication failed"
            errorIsError = true
        }
    }

    PanelWindow {
        id: win
        anchors { top: true; left: true }
        implicitWidth: 480
        implicitHeight: 420
        exclusiveZone: 0
        color: "transparent"

        PolkitPage {
            id: page
            anchors.fill: parent
            controller: mock
        }
    }

    SequentialAnimation {
        running: true

        PauseAnimation { duration: 150 }
        ScriptAction { script: {
            root.ok("action_id_present", mock.actionId === "org.freedesktop.policykit.exec"
                && mock.actionId.length > 0)
            root.ok("password_echo_by_default", page.fieldEchoMode === TextInput.Password,
                "mode=" + page.fieldEchoMode)
        } }

        ScriptAction { script: { mock.echoResponse = true } }
        PauseAnimation { duration: 30 }
        ScriptAction { script: {
            root.ok("echo_follows_response_visible", page.fieldEchoMode === TextInput.Normal,
                "mode=" + page.fieldEchoMode)
            mock.echoResponse = false
        } }

        PauseAnimation { duration: 30 }
        ScriptAction { script: {
            page.fieldText = "hunter2"
            page.trySubmit()
        } }
        PauseAnimation { duration: 30 }
        ScriptAction { script: {
            root.ok("submit_clears_field", page.fieldText.length === 0,
                "text=" + JSON.stringify(page.fieldText))
            root.ok("submit_sets_busy", mock.busy === true)
            root.ok("submit_forwards_text_untouched", mock.lastSubmitted === "hunter2")
            mock.simulateFailed("")
        } }

        PauseAnimation { duration: 30 }
        ScriptAction { script: {
            root.ok("failure_shows_error", mock.errorText === "Authentication failed"
                && mock.errorIsError === true, mock.errorText)
            root.ok("failure_reenables_input", page.fieldEnabled === true)
        } }

        ScriptAction { script: {
            page.fieldText = "typed-before-escape"
            page.doCancel()
        } }
        PauseAnimation { duration: 30 }
        ScriptAction { script: {
            root.ok("escape_calls_cancel", mock.cancelCount === 1, "count=" + mock.cancelCount)
            root.ok("escape_clears_field", page.fieldText.length === 0)
        } }

        ScriptAction { script: {
            page.fieldText = "leftover"
            page.visible = false
        } }
        PauseAnimation { duration: 30 }
        ScriptAction { script: {
            root.ok("completion_closes", page.fieldText.length === 0,
                "text=" + JSON.stringify(page.fieldText))
        } }

        ScriptAction { script: {
            console.log("=== POLKIT TEST ===")
            for (const line of root.log) console.log(line)
            const failed = root.log.filter(l => l.indexOf("FAIL") === 0).length
            console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
            Qt.exit(failed === 0 ? 0 : 1)
        } }
    }
}
