pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

// iPhone continuity client. Reads `phonectl watch` (JSON lines, contract in
// docs/superpowers/specs/2026-10-13-iphone-continuity-design.md) and exposes
// state + one-shot actions. Spawns nothing unless Config.phone.enabled.
QtObject {
    id: root

    readonly property bool enabled: Config.phone.enabled
    readonly property bool active: enabled && watcher.running
    property bool connected: false
    property var status: null
    property var call: null
    property var recentMessages: []
    property string lastError: ""
    // AirPlay / camera are independent of Bluetooth: a `connected:false`
    // status never clears them.
    property string airplayState: "idle"
    property string airplayPin: ""
    property string airplayDevice: ""
    property bool cameraActive: false
    // AirPlay/camera only run on a trusted network (status.trustedNetwork).
    property bool trustedNetwork: false
    property int attempt: 0
    property bool retryGate: true
    // Answer/decline are optimistic (see _callAction). A failed one puts the
    // call back and leaves its reason here for the card to show briefly.
    property string callError: ""
    // The call this machine just answered or declined. phonectl's watch can
    // still report it as incoming for a moment; that report is ignored.
    property string localCallId: ""
    // Epoch ms of a local answer: the active timer counts from here, not from
    // the start of ringing (startedAt from phonectl is the ring time).
    property real localAnsweredAt: 0
    // Test seam: null = spawn phonectl; otherwise called as (args, cb) instead.
    property var runOverride: null

    signal messageReceived(var msg)
    // callChanged() is the implicit change signal of the `call` property.
    signal presenceChanged(bool near)

    readonly property var backoffMs: [1000, 2000, 5000, 10000, 30000]
    function nextBackoffMs(n: int): int {
        return backoffMs[Math.max(0, Math.min(n, backoffMs.length - 1))]
    }

    // BlueFerry's own message popups (app name "BlueFerry") are replaced by the
    // phoneMessage island toast while the phone integration is live; the
    // notification still lands in history. Pure so it can be tested without
    // instantiating NotificationService (which would claim the D-Bus name).
    // BlueFerry posts ANCS (other iPhone apps) under the same app name but
    // marks only those `transient`, so they still pop up.
    function suppressPopup(appName: string, phoneActive: bool, isTransient: bool): bool {
        return phoneActive && appName === "BlueFerry" && !isTransient
    }

    // BlueFerry titles ANCS popups "📱 <App>" or "📱 <App> · <headline>", wrapping
    // names in Unicode bidi isolates. Split them back so banners show the real
    // app (avatar letter, icon lookup) and just the headline. Pure, for tests.
    function parseAncsTitle(title: string): var {
        const clean = (title || "").replace(/[\u2066-\u2069]/g, "").replace(/^\s*📱\s*/u, "")
        const at = clean.indexOf(" · ")
        const app = (at < 0 ? clean : clean.slice(0, at)).trim()
        const headline = at < 0 ? "" : clean.slice(at + 3).trim()
        return { app: app, title: headline || app }
    }

    // While the session is locked and the phone integration is on, BlueFerry
    // (ANCS) notification text must not render anywhere. The lock screen has no
    // notification list; this covers the popup path (NotificationService).
    function hideNotificationText(appName: string, locked: bool, phoneEnabled: bool): bool {
        return phoneEnabled && locked && appName === "BlueFerry"
    }

    function handleLine(line: string): void {
        let evt
        try {
            evt = JSON.parse(line)
        } catch (error) {
            return
        }
        if (!evt || typeof evt !== "object" || evt.v !== 1)
            return
        switch (evt.type) {
        case "status":
            status = evt
            connected = evt.connected === true
            trustedNetwork = evt.trustedNetwork === true
            lastError = evt.error || ""
            if (!connected && call !== null) {
                call = null
            }
            break
        case "call":
            if (evt.state === "ended") {
                call = null
                localCallId = ""
            } else if (evt.id === localCallId && evt.state === "incoming") {
                // Stale ring report for a call this machine already answered
                // or declined: keep the optimistic state.
            } else {
                call = _withCallName(_withAnswerTime(evt))
            }
            break
        case "message": {
            const next = recentMessages.concat([evt])
            recentMessages = next.length > 50 ? next.slice(next.length - 50) : next
            messageReceived(evt)
            break
        }
        case "presence":
            presenceChanged(evt.near === true)
            break
        case "airplay": {
            const st = ["idle", "pin", "mirroring", "audio"].indexOf(evt.state) >= 0 ? evt.state : "idle"
            // The password is never carried by events (`pin` is always null);
            // it is fetched on request via airplayPassword().
            airplayPin = ""
            airplayDevice = evt.device ? String(evt.device) : ""
            airplayState = st
            break
        }
        case "camera":
            cameraActive = evt.active === true
            break
        default:
            return
        }
        attempt = 0
    }

    function _withAnswerTime(evt) {
        if (evt.id !== localCallId || evt.state !== "active" || localAnsweredAt <= 0)
            return evt
        return Object.assign({}, evt, { startedAt: localAnsweredAt })
    }

    // Only the last nine digits are compared, so "+44 7700 900123" and
    // "07700 900123" find the same contact. Shorter tails are too ambiguous.
    function _numberTail(number): string {
        return String(number || "").replace(/\D/g, "").slice(-9)
    }

    // The Messages page names a number from the sender of its messages
    // (message.from.name), so the same lookup runs over recentMessages.
    // Outgoing messages are skipped: their `from` is this phone's own side.
    function contactName(number: string): string {
        const want = _numberTail(number)
        if (want.length < 7)
            return ""
        for (let i = recentMessages.length - 1; i >= 0; i--) {
            const m = recentMessages[i]
            if (m.outgoing !== true && m.from && m.from.name
                    && _numberTail(m.from.number) === want)
                return String(m.from.name)
        }
        return ""
    }

    function _withCallName(evt) {
        if (evt.name || !evt.number)
            return evt
        const name = contactName(evt.number)
        return name ? Object.assign({}, evt, { name: name }) : evt
    }

    // --- lock-on-leave -----------------------------------------------------
    property PhoneLock lockPolicy: PhoneLock {
        enabled: Config.phone.lockOnLeave
        isLocked: function() {
            return !!(LockService.lockScreen && LockService.lockScreen.locked)
        }
        lock: function() { LockService.engage() }
    }
    onPresenceChanged: near => lockPolicy.onPresence(near)

    // --- watcher -----------------------------------------------------------
    property Process watcher: Process {
        command: [Config.phone.phonectl, "watch"]
        running: root.enabled && root.retryGate
        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }
        onExited: (exitCode, exitStatus) => {
            if (!root.enabled)
                return
            root.retryGate = false
            root.retryTimer.interval = root.nextBackoffMs(root.attempt)
            root.attempt++
            root.retryTimer.restart()
            if (root.connected) {
                root.connected = false
                root.call = null
            }
        }
    }

    property Timer retryTimer: Timer {
        repeat: false
        onTriggered: root.retryGate = true
    }

    // --- one-shot actions ---------------------------------------------------
    function _run(args: var, cb): void {
        if (runOverride) {
            runOverride(args, cb)
            return
        }
        const job = oneShot.createObject(root, { args: args, cb: cb || null })
        job.start()
    }

    property Component oneShot: Component {
        QtObject {
            id: job
            property var args: []
            property var cb: null
            property string out: ""
            property Process proc: Process {
                stdout: StdioCollector {
                    onStreamFinished: job.out = text
                }
                onExited: (exitCode, exitStatus) => {
                    let result
                    try {
                        result = JSON.parse(job.out.trim().split("\n").pop())
                    } catch (error) {
                        result = { v: 1, ok: false, error: "phonectl unavailable" }
                    }
                    if (!result || typeof result !== "object")
                        result = { v: 1, ok: false, error: "phonectl unavailable" }
                    if (result.ok !== true && !result.error)
                        result.error = "phonectl failed"
                    if (job.cb)
                        job.cb(result)
                    job.destroy()
                }
            }
            function start() {
                proc.command = [Config.phone.phonectl].concat(args)
                proc.running = true
            }
        }
    }

    // Answer and decline are optimistic: the card reacts at once and phonectl's
    // verdict only has to confirm it. On failure the call goes back exactly as
    // it was and the reason is shown briefly (callError).
    function _callAction(verb: string, cb): void {
        const before = call
        if (!before || before.state !== "incoming") {
            _run([verb], cb)
            return
        }
        const answering = verb === "answer"
        const optimistic = answering
            ? Object.assign({}, before, { state: "active", startedAt: Date.now() })
            : null
        localCallId = String(before.id || "")
        localAnsweredAt = answering ? optimistic.startedAt : 0
        call = optimistic
        _run([verb], function(result) {
            if (result && result.ok === true) {
                if (cb) cb(result)
                return
            }
            // Put the call back only if nothing newer has replaced our
            // optimistic state (a live answer report, or an ended call).
            const stillOurs = answering ? call === optimistic : localCallId === before.id
            if (stillOurs)
                call = before
            if (localCallId === before.id) {
                localCallId = ""
                localAnsweredAt = 0
            }
            callError = (result && result.error) || "phonectl failed"
            callErrorTimer.restart()
            if (cb) cb(result)
        })
    }

    function answer(cb): void { _callAction("answer", cb) }
    function decline(cb): void { _callAction("decline", cb) }

    property Timer callErrorTimer: Timer {
        interval: 4000
        repeat: false
        onTriggered: root.callError = ""
    }
    function hangup(cb): void { _run(["hangup"], cb) }
    function setMuted(on: bool, cb): void { _run(["mute", on ? "on" : "off"], cb) }
    function reply(threadId: string, text: string, cb): void { _run(["reply", threadId, text], cb) }
    function send(number: string, text: string, cb): void { _run(["send", number, text], cb) }
    // Read-only name search over the BlueFerry contact cache. cb gets
    // {ok, contacts: [{name, number}]} or {ok:false, error}.
    function findContacts(query: string, cb): void { _run(["contacts", String(query || "")], cb) }
    // Starts a call only when BlueFerry has calls enabled (the daemon checks).
    // A refusal is shown on the call card, as answer and decline do.
    function dial(number: string, cb): void {
        _run(["dial", String(number || "")], function(result) {
            if (!(result && result.ok === true)) {
                callError = (result && result.error) || "phonectl failed"
                callErrorTimer.restart()
            }
            if (cb) cb(result)
        })
    }
    // True when BlueFerry reports calls on (status.callsEnabled, from GetStatus).
    readonly property bool callsEnabled: !!status && status.callsEnabled === true
    // The Spotlight "message <name>" / "call <name>" results set this; the
    // Notification Center opens its compose sheet on it and clears it.
    property var composeTarget: null
    function openCompose(name: string, number: string): void {
        composeTarget = { name: String(name || ""), number: String(number || "") }
    }
    function clearCompose(): void { composeTarget = null }
    function threads(cb): void { _run(["threads"], cb) }
    function thread(id: string, cb): void { _run(["thread", id], cb) }
    function setLockOnLeave(on: bool, cb): void {
        SettingsStore.setValue("phone", "lockOnLeave", on)
        _run(["lock-on-leave", on ? "on" : "off"], cb)
    }
    function airplayPassword(cb): void { _run(["airplay-password"], cb) }
    function trustNetwork(cb): void { _run(["trust-network"], cb) }
    function untrustNetwork(cb): void { _run(["untrust-network"], cb) }
    function cameraLink(cb): void { _run(["camera-link"], cb) }
    function setHotspot(on: bool, cb): void { _run(["hotspot", on ? "on" : "off"], cb) }
    // Samples the signal for ~10 s while the user stands where the Mac should lock. The reply is
    // {ok, threshold, samples} or {ok:false, error}; the error text is shown as is.
    function calibratePresence(cb): void { _run(["calibrate-presence"], cb) }
}
