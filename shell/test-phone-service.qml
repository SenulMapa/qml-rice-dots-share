// Pure-logic test for services/PhoneService.qml. phone.enabled defaults to
// false, so the watcher never spawns; lines are fed straight to handleLine().
import QtQuick
import Quickshell
import "services"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    function feed(obj) { PhoneService.handleLine(JSON.stringify(Object.assign({ v: 1 }, obj))) }

    Component.onCompleted: {
        ok("inactive_when_disabled", PhoneService.active === false)

        feed({ type: "status", connected: true, device: { name: "iPhone", address: "AA" }, battery: 82, signal: 4, network: "5G" })
        ok("parses_status", PhoneService.connected === true && PhoneService.status.battery === 82
            && PhoneService.status.device.name === "iPhone")

        ok("trusted_defaults_false", PhoneService.trustedNetwork === false)
        feed({ type: "status", connected: true, device: { name: "iPhone", address: "AA" }, trustedNetwork: true })
        ok("parses_trusted_network", PhoneService.trustedNetwork === true)
        feed({ type: "status", connected: true, device: { name: "iPhone", address: "AA" }, trustedNetwork: false })
        ok("parses_untrusted_network", PhoneService.trustedNetwork === false)
        feed({ type: "status", connected: true, device: { name: "iPhone", address: "AA" } })
        ok("missing_trusted_is_false", PhoneService.trustedNetwork === false)
        ok("trust_actions_exist", typeof PhoneService.trustNetwork === "function"
            && typeof PhoneService.untrustNetwork === "function" && typeof PhoneService.airplayPassword === "function")

        feed({ type: "call", id: "c1", state: "incoming", number: "+4412", name: "Ada" })
        ok("call_incoming", PhoneService.call && PhoneService.call.state === "incoming")
        feed({ type: "call", id: "c1", state: "active", number: "+4412", name: "Ada", startedAt: 1000 })
        ok("call_incoming_then_active", PhoneService.call && PhoneService.call.state === "active")
        feed({ type: "call", id: "c1", state: "ended" })
        ok("call_ended_clears", PhoneService.call === null)

        feed({ type: "call", id: "c2", state: "incoming", number: "1" })
        feed({ type: "status", connected: false, device: null })
        ok("test_call_cleared_on_disconnect", PhoneService.call === null && PhoneService.connected === false)

        let got = 0
        PhoneService.messageReceived.connect(m => got++)
        for (let i = 0; i < 60; i++)
            feed({ type: "message", id: "m" + i, threadId: "t", from: { name: "A", number: "1" }, text: "hi " + i, ts: i })
        ok("message_ring_capped_50", PhoneService.recentMessages.length === 50
            && PhoneService.recentMessages[49].id === "m59" && PhoneService.recentMessages[0].id === "m10"
            && got === 60)

        const nasty = "line1\nline2 \"quoted\" \u{1F600} שלום " + "x".repeat(5000)
        feed({ type: "message", id: "h", threadId: "t", from: { name: "A", number: "1" }, text: nasty, ts: 99 })
        const last = PhoneService.recentMessages[PhoneService.recentMessages.length - 1]
        ok("parses_hostile_text", last.text === nasty && last.text.length > 5000)

        const n = PhoneService.recentMessages.length
        PhoneService.handleLine("{not json")
        PhoneService.handleLine(JSON.stringify({ v: 2, type: "message", id: "x" }))
        PhoneService.handleLine(JSON.stringify({ v: 1, type: "wibble", id: "x" }))
        PhoneService.handleLine("")
        PhoneService.handleLine("null")
        ok("ignores_bad_json_and_unknown_type", PhoneService.recentMessages.length === n)

        const b = [0, 1, 2, 3, 4, 5, 9].map(a => PhoneService.nextBackoffMs(a))
        ok("backoff_sequence", JSON.stringify(b) === "[1000,2000,5000,10000,30000,30000,30000]", JSON.stringify(b))

        let near = []
        PhoneService.presenceChanged.connect(v => near.push(v))
        feed({ type: "presence", near: false, rssi: null, since: 1 })
        feed({ type: "presence", near: true, rssi: null, since: 2 })
        ok("presence_signal", JSON.stringify(near) === "[false,true]")

        
        ok("airplay_defaults", PhoneService.airplayState === "idle" && PhoneService.cameraActive === false)
        feed({ type: "airplay", state: "pin", pin: "4821", device: "Ada's iPhone" })
        ok("airplay_pin", PhoneService.airplayState === "pin" && PhoneService.airplayPin === "" && PhoneService.airplayDevice === "Ada's iPhone")
        feed({ type: "airplay", state: "mirroring", pin: "4821", device: "Ada's iPhone" })
        ok("airplay_mirroring_drops_pin", PhoneService.airplayState === "mirroring"
            && PhoneService.airplayPin === "" && PhoneService.airplayDevice === "Ada's iPhone")
        feed({ type: "airplay", state: "bogus" })
        ok("airplay_unknown_state_idle", PhoneService.airplayState === "idle")
        feed({ type: "camera", active: true })
        ok("camera_active", PhoneService.cameraActive === true)
        feed({ type: "airplay", state: "audio", device: "x" })
        feed({ type: "status", connected: false, device: null })
        ok("bt_disconnect_keeps_airplay_camera", PhoneService.connected === false
            && PhoneService.airplayState === "audio" && PhoneService.cameraActive === true)
        feed({ type: "camera", active: false })
        ok("camera_off", PhoneService.cameraActive === false)
        ok("camera_link_action", typeof PhoneService.cameraLink === "function")
        // calibrate-presence is one one-shot phonectl verb with no arguments.
        let calibrateArgs = null
        PhoneService.runOverride = (args, cb) => { calibrateArgs = args.join(" ") }
        PhoneService.calibratePresence(() => {})
        ok("calibrate_presence_verb", calibrateArgs === "calibrate-presence")
        PhoneService.runOverride = null

        // Contacts search: read-only verb, empty query never asks BlueFerry.
        let lastArgs = null
        let contactsReply = null
        PhoneService.runOverride = (args, cb) => { lastArgs = args.join("|"); cb(contactsReply) }
        contactsReply = { v: 1, ok: true, contacts: [{ name: "Maya", number: "+15550001" }] }
        let found = null
        PhoneService.findContacts("ma", r => { found = r })
        ok("contacts_verb_args", lastArgs === "contacts|ma", lastArgs)
        ok("contacts_result_passed_through", found && found.ok === true && found.contacts[0].name === "Maya")
        PhoneService.findContacts("", r => {})
        ok("contacts_empty_query_sent_as_empty", lastArgs === "contacts|", lastArgs)

        // Dial: a refusal lands on callError (the call card shows it briefly).
        contactsReply = { v: 1, ok: false, error: "Calls are not enabled" }
        let dialled = null
        PhoneService.callError = ""
        PhoneService.dial("+15550001", r => { dialled = r })
        ok("dial_verb_args", lastArgs === "dial|+15550001", lastArgs)
        ok("dial_refusal_sets_callError", PhoneService.callError === "Calls are not enabled" && dialled.ok === false,
            PhoneService.callError)
        contactsReply = { v: 1, ok: true }
        PhoneService.callError = ""
        PhoneService.dial("+15550001", r => {})
        ok("dial_success_leaves_callError", PhoneService.callError === "")
        PhoneService.runOverride = null

        // Calls-enabled comes from the status event (BlueFerry calls_enabled).
        feed({ type: "status", connected: true, device: { name: "iPhone", address: "AA" } })
        ok("calls_disabled_without_flag", PhoneService.callsEnabled === false)
        feed({ type: "status", connected: true, device: { name: "iPhone", address: "AA" }, callsEnabled: true })
        ok("calls_enabled_from_status", PhoneService.callsEnabled === true)
        feed({ type: "status", connected: true, device: { name: "iPhone", address: "AA" }, callsEnabled: false })
        ok("calls_disabled_from_status", PhoneService.callsEnabled === false)

        // Compose hand-off: the Spotlight sets a target; the sheet takes it once.
        let composeSignals = 0
        const onTarget = () => { composeSignals++ }
        PhoneService.composeTargetChanged.connect(onTarget)
        PhoneService.openCompose("Maya", "+15550001")
        ok("compose_target_set", PhoneService.composeTarget && PhoneService.composeTarget.name === "Maya"
            && PhoneService.composeTarget.number === "+15550001")
        PhoneService.clearCompose()
        ok("compose_target_cleared", PhoneService.composeTarget === null)
        ok("compose_target_signals", composeSignals === 2, String(composeSignals))
        PhoneService.composeTargetChanged.disconnect(onTarget)

        console.log("=== PHONE SERVICE TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
