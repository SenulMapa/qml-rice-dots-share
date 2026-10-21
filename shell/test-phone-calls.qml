// Incoming-call handling: ringing card vs pill (PhoneAttention gate), the
// optimistic answer/decline with rollback on failure, the answer-time timer,
// and caller-name lookup from recent messages. phonectl is never spawned:
// PhoneService.runOverride captures each verb and its callback instead.
import QtQuick
import Quickshell
import "core"
import "island"
import "services"

ShellRoot {
    id: root
    property var log: []
    property string lastVerb: ""
    property var pendingCb: null
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    function feed(obj) { PhoneService.handleLine(JSON.stringify(Object.assign({ v: 1 }, obj))) }
    function fakeRun(args, cb) { root.lastVerb = args[0]; root.pendingCb = cb }
    function settle(result) { const cb = root.pendingCb; root.pendingCb = null; cb(result) }

    IslandController { id: ctrl }

    Component.onCompleted: {
        PhoneService.runOverride = root.fakeRun
        feed({ type: "status", connected: true, device: { name: "iPhone" } })

        // --- ringing card, by attention state -----------------------------
        PhoneAttention.lockedOverride = false
        PhoneAttention.idleOverride = true
        feed({ type: "call", id: "c1", state: "incoming", number: "+44 1" })
        ok("incoming_idle_shows_card", ctrl.visualState === "call", ctrl.visualState)
        ok("incoming_idle_never_pill", ctrl.visualState !== "callActive")

        feed({ type: "call", id: "c1", state: "ended" })
        ctrl.clearTransient()
        PhoneAttention.idleOverride = false
        PhoneAttention.lockedOverride = true
        feed({ type: "call", id: "c2", state: "incoming", number: "+44 2" })
        ok("incoming_locked_is_quiet", ctrl.visualState !== "call" && ctrl.visualState !== "callActive",
            ctrl.visualState)
        feed({ type: "call", id: "c2", state: "ended" })

        // --- answer: optimistic, timer from the answer ---------------------
        PhoneAttention.lockedOverride = false
        PhoneAttention.idleOverride = false
        feed({ type: "call", id: "c3", state: "incoming", number: "+44 3", startedAt: 1000 })
        ok("answer_precondition_card", ctrl.visualState === "call")
        const before = Date.now()
        PhoneService.answer()
        ok("answer_sends_verb", root.lastVerb === "answer", root.lastVerb)
        ok("answer_switches_to_pill_at_once", PhoneService.call.state === "active"
            && ctrl.visualState === "callActive", ctrl.visualState)
        ok("answer_timer_starts_at_answer", PhoneService.call.startedAt >= before
            && PhoneService.call.startedAt <= Date.now(), String(PhoneService.call.startedAt))
        // phonectl's watch still reports the ring before the answer lands.
        feed({ type: "call", id: "c3", state: "incoming", number: "+44 3", startedAt: 1000 })
        ok("stale_ring_does_not_bring_card_back", ctrl.visualState === "callActive", ctrl.visualState)
        // The active report carries the ring time; the local answer time wins.
        const answeredAt = PhoneService.call.startedAt
        feed({ type: "call", id: "c3", state: "active", number: "+44 3", startedAt: 1000 })
        ok("active_report_keeps_answer_time", PhoneService.call.startedAt === answeredAt,
            String(PhoneService.call.startedAt))
        settle({ v: 1, ok: true })
        ok("answer_success_keeps_pill", ctrl.visualState === "callActive" && PhoneService.callError === "")
        feed({ type: "call", id: "c3", state: "ended" })
        ctrl.clearTransient()
        ok("answer_ended_releases", PhoneService.call === null && ctrl.transientState === "")

        // --- answer fails: roll back to the card, show why ----------------
        feed({ type: "call", id: "c4", state: "incoming", number: "+44 4" })
        PhoneService.answer()
        ok("answer_fail_optimistic_first", ctrl.visualState === "callActive")
        settle({ v: 1, ok: false, error: "iPhone not connected" })
        ok("answer_fail_restores_card", PhoneService.call !== null && PhoneService.call.state === "incoming"
            && ctrl.visualState === "call", ctrl.visualState)
        ok("answer_fail_shows_error", PhoneService.callError === "iPhone not connected", PhoneService.callError)
        // The restored call is no longer "ours": a later ring report is taken.
        feed({ type: "call", id: "c4", state: "incoming", number: "+44 4" })
        ok("answer_fail_next_ring_accepted", PhoneService.call.state === "incoming")

        // --- decline: dismissed at once; failure restores it ---------------
        PhoneService.decline()
        ok("decline_sends_verb", root.lastVerb === "decline", root.lastVerb)
        ok("decline_dismisses_at_once", PhoneService.call === null && ctrl.transientState === "",
            ctrl.visualState)
        feed({ type: "call", id: "c4", state: "incoming", number: "+44 4" })
        ok("decline_ignores_stale_ring", PhoneService.call === null)
        settle({ v: 1, ok: true })
        feed({ type: "call", id: "c4", state: "ended" })
        ok("decline_success_stays_gone", PhoneService.call === null && ctrl.visualState !== "call")

        feed({ type: "call", id: "c5", state: "incoming", number: "+44 5" })
        PhoneService.decline()
        settle({ v: 1, ok: false, error: "Busy, try again" })
        ok("decline_fail_restores_card", PhoneService.call !== null && ctrl.visualState === "call",
            ctrl.visualState)
        ok("decline_fail_shows_error", PhoneService.callError === "Busy, try again", PhoneService.callError)

        // A hangup while the decline was pending must not be undone by it.
        PhoneService.decline()
        feed({ type: "call", id: "c5", state: "ended" })
        settle({ v: 1, ok: false, error: "phonectl failed" })
        ok("failed_decline_after_end_stays_gone", PhoneService.call === null)

        // --- caller name from the Messages source -------------------------
        feed({ type: "message", id: "m1", threadId: "t1", from: { name: "Ada", number: "+44 7700 900123" },
            text: "hi", ts: 1, outgoing: false })
        feed({ type: "message", id: "m2", threadId: "t1", from: { name: "Me", number: "07700900123" },
            text: "yo", ts: 2, outgoing: true })
        ok("contact_name_by_national_form", PhoneService.contactName("07700 900123") === "Ada",
            PhoneService.contactName("07700 900123"))
        ok("contact_name_skips_outgoing", PhoneService.contactName("+447700900123") === "Ada")
        ok("contact_name_short_number_none", PhoneService.contactName("123") === "")
        ok("contact_name_unknown_none", PhoneService.contactName("+1 555 0100") === "")
        feed({ type: "call", id: "c6", state: "incoming", number: "+44 7700 900123", name: null })
        ok("call_gets_contact_name", PhoneService.call.name === "Ada", String(PhoneService.call.name))
        feed({ type: "call", id: "c6", state: "ended" })
        feed({ type: "call", id: "c7", state: "incoming", number: "+1 555 0100", name: "Given" })
        ok("phonectl_name_wins", PhoneService.call.name === "Given")
        feed({ type: "call", id: "c7", state: "ended" })

        console.log("=== PHONE CALLS TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
