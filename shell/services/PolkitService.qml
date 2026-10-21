pragma Singleton
import QtQuick
import Quickshell.Services.Polkit

/**
 * PolkitService -- the shell's polkit authentication agent. Without this,
 * every pkexec/GUI authentication prompt on this session silently fails once
 * no other shell is registered to answer them.
 *
 * Wraps a single PolkitAgent/AuthFlow pair and exposes only what
 * panels/PolkitPage.qml needs: `registered`/`active` for status, `flow` for
 * the rare case a caller needs the raw AuthFlow (tests, `identities`
 * plumbing), and a handful of cleaned, page-ready properties
 * (`message`/`actionId`/`prompt`/`echoResponse`/`errorText`/`errorIsError`/
 * `busy`) plus `submit(text)`/`cancel()`/`selectIdentity(identity)`.
 *
 * ---- The single-agent constraint ----
 * Only ONE polkit authentication agent can be registered per session.
 * Registration is attempted exactly ONCE, synchronously from
 * PolkitAgent::componentComplete() -> PolkitAgentImpl::tryTakeoverOrCreate()
 * (see quickshell's src/services/polkit/{qml,agentimpl}.cpp) -- there is no
 * retry, and no API on PolkitAgent to ask it to try again. While another
 * agent (end4-pC, on this machine) already holds the session's one slot,
 * `registered` stays false forever for this process; Quickshell's own C++
 * additionally logs ONE unavoidable `qCWarning` ("failed to register
 * listener: ...", category quickshell.service.polkit.listener) when that
 * happens -- this file cannot suppress or retry that, only avoid adding
 * warnings/loops of its own. See HANDOVER.md's "Polkit" section for what
 * re-registration after end4-pC exits actually requires (a process restart,
 * not a live retry).
 */
QtObject {
    id: root

    property PolkitAgent agent: PolkitAgent {}

    readonly property bool registered: agent.isRegistered
    readonly property bool active: agent.isActive
    readonly property var flow: agent.flow

    readonly property string message: flow ? flow.message : ""
    readonly property string actionId: flow ? flow.actionId : ""
    readonly property var identities: flow ? flow.identities : []
    readonly property var selectedIdentity: flow ? flow.selectedIdentity : null
    readonly property bool echoResponse: flow ? flow.responseVisible : false

    // Cleaned for display: trimmed, a trailing ":" (every polkit prompt ships
    // one, e.g. "Password:") dropped, "Password" as the default when there
    // is nothing to show yet.
    readonly property string prompt: {
        let raw = (flow && flow.inputPrompt) ? flow.inputPrompt.trim() : ""
        if (raw.endsWith(":"))
            raw = raw.slice(0, -1).trim()
        return raw.length > 0 ? raw : "Password"
    }

    property string errorText: ""
    property bool errorIsError: false
    property bool busy: false

    signal authenticationRequestStarted()

    function selectIdentity(identity): void {
        if (flow)
            flow.selectedIdentity = identity
    }

    // Sets busy and hands `text` straight to the native call -- it is never
    // logged and never retained in a property of ours.
    function submit(text: string): void {
        if (!flow || busy)
            return
        busy = true
        flow.submit(text)
    }

    function cancel(): void {
        if (!flow)
            return
        flow.cancelAuthenticationRequest()
    }

    function clearState(): void {
        errorText = ""
        errorIsError = false
        busy = false
    }

    // Exactly one informational log line about registration state, ever, for
    // this PolkitAgent instance -- not a warning, and not a retry loop.
    // `isRegistered`'s change notification only fires on an actual VALUE
    // transition, so the common "another agent already holds the slot" case
    // (default false -> registerComplete(false), i.e. false -> false) never
    // emits one; a single-shot fallback timer covers that case, guarded so
    // whichever path runs first is the only one that logs.
    property bool loggedRegistrationState: false
    function logRegistrationOnce(): void {
        if (loggedRegistrationState)
            return
        loggedRegistrationState = true
        console.log(agent.isRegistered
            ? "Polkit: registered as this session's authentication agent."
            : "Polkit: another authentication agent already holds this session's "
                + "single registration slot (expected while end4-pC is running); "
                + "not retrying -- restart the shell after that agent exits to "
                + "pick up registration.")
    }

    property Timer registrationFallbackTimer: Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: root.logRegistrationOnce()
    }

    property Connections agentConnections: Connections {
        target: root.agent
        function onIsRegisteredChanged(): void { root.logRegistrationOnce() }
        function onAuthenticationRequestStarted(): void {
            root.clearState()
            root.authenticationRequestStarted()
        }
    }

    // Re-targets automatically whenever agent.flow changes (flowChanged).
    // authenticationFailed is the reliable one to build UI feedback on: a
    // wrong password does not complete the flow (AuthFlow::completed() in
    // flow.cpp only sets isCompleted on success or cancellation), so `flow`
    // stays the SAME object across a failed attempt and this connection is
    // never silently dropped mid-failure. Success/cancellation set
    // PolkitAgent.flow back to null in the same call that emits those two
    // signals, which can race a target-tracking Connections like this one --
    // panels/PolkitPage.qml (via island/Island.qml) closes on `active` going
    // false instead of on those signals, so that race costs nothing.
    property Connections flowConnections: Connections {
        target: root.flow
        enabled: root.flow !== null
        function onSupplementaryMessageChanged(): void {
            root.errorText = root.flow.supplementaryMessage
            root.errorIsError = root.flow.supplementaryIsError
        }
        function onAuthenticationFailed(): void {
            root.busy = false
            if (root.errorText.length === 0)
                root.errorText = "Authentication failed"
            root.errorIsError = true
        }
        function onAuthenticationSucceeded(): void { root.clearState() }
        function onAuthenticationRequestCancelled(): void { root.clearState() }
    }
}
