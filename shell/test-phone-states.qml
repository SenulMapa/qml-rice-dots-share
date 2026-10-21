// Island phone states: priorities, call card lifecycle, reply failure,
// BlueFerry popup suppression. Drives a real IslandController (a plain
// QtObject, no window) from PhoneService.handleLine(); the toast gets a stub
// service. Never touches NotificationService (it would claim the D-Bus name).
import QtQuick
import Quickshell
import "core"
import "components"
import "island"
import "services"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    function feed(obj) { PhoneService.handleLine(JSON.stringify(Object.assign({ v: 1 }, obj))) }

    IslandController { id: ctrl }

    QtObject {
        id: stubService
        function reply(threadId, text, cb) { cb({ v: 1, ok: false, error: "iPhone not connected" }) }
    }
    QtObject {
        id: stubOkService
        function reply(threadId, text, cb) { cb({ v: 1, ok: true }) }
    }
    property string lastReplyThread: ""
    QtObject {
        id: recService
        function reply(threadId, text, cb) { root.lastReplyThread = threadId; cb({ v: 1, ok: true }) }
    }
    QtObject {
        id: stubController
        property string visualState: "phoneMessage"
        readonly property string phoneMessage: "phoneMessage"
        property int cleared: 0
        function clearTransient() { cleared++ }
    }
    PhoneMessageToast {
        id: toast
        width: 520; height: 132
        service: stubService
        controller: stubController
        entry: ({ threadId: "t1", from: { name: "Ada", number: "1" }, text: "lunch at one?" })
    }

    IslandController { id: fresh }
    PhoneAirplayPin { id: pwView; width: 420; height: 104 }
    property int pwCalls: 0
    property var trustCalls: []
    QtObject {
        id: trustService
        property var status: ({ trustedNetwork: false })
        property bool connected: true
        function trustNetwork() { root.trustCalls.push("trust") }
        function untrustNetwork() { root.trustCalls.push("untrust") }
    }
    QtObject {
        id: pwService
        property string airplayDevice: "Ada's iPhone"
        property string airplayState: "pin"
        property string airplayPin: ""
        function airplayPassword(cb) { root.pwCalls++; cb({ v: 1, ok: true, password: "fixture-airplay-pw-not-real" }) }
    }
    PhoneSatelliteContent { id: pwSat; width: 300; height: 400; service: pwService; revealMs: 40 }
    PhoneLivePill { id: livePill; width: 210; height: 44; kind: "mirroring" }

    Component.onCompleted: {
        // Disabled by default: nothing is requested, nothing shows.
        ok("disabled_nothing_shows", Config.phone.enabled === false && PhoneService.enabled === false
            && PhoneService.active === false && fresh.visualState === "dormant"
            && fresh.transientState === "" && fresh.phoneState === false
            && PhoneService.airplayState === "idle" && PhoneService.cameraActive === false)

        ok("priority_call_48", ctrl.statePriority(ctrl.call) === 48)
        ok("priority_call_above_notification", ctrl.statePriority(ctrl.call) > ctrl.statePriority(ctrl.notification))
        ok("priority_phoneMessage_45", ctrl.statePriority(ctrl.phoneMessage) === 45)
        ok("priority_callActive_between_media_and_osd",
            ctrl.statePriority(ctrl.callActive) === 35
            && ctrl.statePriority(ctrl.callActive) > ctrl.statePriority(ctrl.media)
            && ctrl.statePriority(ctrl.callActive) < ctrl.statePriority(ctrl.volume))

        feed({ type: "status", connected: true, device: { name: "iPhone" } })
        feed({ type: "call", id: "c1", state: "incoming", number: "+44", name: "Ada" })
        ok("call_requested_on_incoming", ctrl.visualState === "call" && ctrl.transientPriority === 48,
            ctrl.visualState)
        ctrl.showVolume(0.5, false, "x")
        ok("osd_cannot_preempt_call", ctrl.visualState === "call")
        feed({ type: "call", id: "c1", state: "active", number: "+44", name: "Ada", startedAt: 1 })
        ok("active_call_uses_callActive", ctrl.visualState === "callActive", ctrl.visualState)
        ctrl.showVolume(0.5, false, "x")
        ok("osd_preempts_active_call", ctrl.visualState === "volume")
        feed({ type: "call", id: "c1", state: "ended" })
        ctrl.clearTransient()
        ok("call_released_on_end", ctrl.visualState === "dormant" && ctrl.transientState === "", ctrl.visualState)

        feed({ type: "call", id: "c2", state: "incoming", number: "+1" })
        ok("call_reopens", ctrl.visualState === "call")
        feed({ type: "status", connected: false, device: null })
        ok("call_card_leaves_on_disconnect", ctrl.visualState !== "call" && ctrl.transientPriority === 0,
            ctrl.visualState)

        feed({ type: "message", id: "m1", threadId: "t1", from: { name: "Ada", number: "1" }, text: "hi", ts: 1, outgoing: false })
        ok("message_toast_requested", ctrl.visualState === "phoneMessage" && ctrl.phoneMessageEntry.id === "m1")
        ctrl.clearTransient()
        feed({ type: "message", id: "m2", threadId: "t1", from: { name: "Me", number: "0" }, text: "yo", ts: 2, outgoing: true })
        ok("outgoing_message_no_toast", ctrl.visualState === "dormant")

        ok("blueferry_popup_suppressed",
            PhoneService.suppressPopup("BlueFerry", true, false) === true
            && PhoneService.suppressPopup("BlueFerry", false, false) === false
            && PhoneService.suppressPopup("BlueFerry", true, true) === false
            && PhoneService.suppressPopup("Signal", true, false) === false)

        const a1 = PhoneService.parseAncsTitle("📱 \u2068WhatsApp\u2069 · \u2068Thisuri\u2069")
        const a2 = PhoneService.parseAncsTitle("📱 Gmail")
        ok("ancs_title_parsed", a1.app === "WhatsApp" && a1.title === "Thisuri"
            && a2.app === "Gmail" && a2.title === "Gmail")

        toast.replyText = "on my way"
        toast.sendReply()
        ok("reply_failure_keeps_text", toast.replyText === "on my way" && toast.errorVisible
            && toast.errorText === "iPhone not connected" && stubController.cleared === 0,
            toast.replyText + " | " + toast.errorText)

        toast.service = stubOkService
        toast.sendReply()
        ok("reply_success_clears_and_closes", toast.replyText === "" && !toast.errorVisible
            && stubController.cleared === 1)

        toast.service = recService
        toast.entry = { threadId: "A", from: { name: "Ann", number: "1" }, text: "first" }
        toast.replyText = "typing to Ann"
        toast.entry = { threadId: "B", from: { name: "Bob", number: "2" }, text: "second" }
        toast.sendReply()
        ok("reply_targets_original_thread", root.lastReplyThread === "A", root.lastReplyThread)

        // --- round 2: AirPlay PIN + live indicators ------------------------
        ctrl.clearTransient()
        feed({ type: "call", id: "c1", state: "ended" })
        ok("priority_airplayPin_47", ctrl.statePriority(ctrl.airplayPin) === 47
            && ctrl.statePriority(ctrl.airplayPin) > ctrl.statePriority(ctrl.phoneMessage)
            && ctrl.statePriority(ctrl.airplayPin) < ctrl.statePriority(ctrl.call))
        ok("priority_live_34_between_media_and_callActive",
            ctrl.statePriority(ctrl.mirroring) === 34 && ctrl.statePriority(ctrl.camera) === 34
            && ctrl.statePriority(ctrl.mirroring) < ctrl.statePriority(ctrl.callActive)
            && ctrl.statePriority(ctrl.mirroring) > ctrl.statePriority(ctrl.media))

        feed({ type: "airplay", state: "pin", pin: "4821", device: null })
        ok("pin_appears", ctrl.visualState === "airplayPin" && ctrl.transientPriority === 47, ctrl.visualState)
        feed({ type: "message", id: "m9", threadId: "t1", from: { name: "Ada", number: "1" }, text: "hi", ts: 9, outgoing: false })
        ok("message_cannot_preempt_pin", ctrl.visualState === "airplayPin")
        feed({ type: "call", id: "c3", state: "incoming", number: "+1" })
        ok("call_preempts_pin", ctrl.visualState === "call")
        feed({ type: "call", id: "c3", state: "ended" })
        ctrl.clearTransient()
        ctrl.syncPhoneLive()
        ok("pin_returns_after_call", ctrl.visualState === "airplayPin", ctrl.visualState)
        feed({ type: "airplay", state: "mirroring", pin: null, device: "Ada's iPhone" })
        ok("pin_leaves_on_state_change", ctrl.visualState === "mirroring", ctrl.visualState)
        feed({ type: "airplay", state: "pin", pin: "1234" })
        feed({ type: "airplay", state: "idle", pin: null, device: null })
        ok("pin_leaves_to_idle", ctrl.visualState === "dormant" && ctrl.transientState === "", ctrl.visualState)

        feed({ type: "camera", active: true })
        ok("camera_indicator", ctrl.visualState === "camera" && ctrl.transientPriority === 34, ctrl.visualState)
        feed({ type: "airplay", state: "audio", device: "x" })
        ok("mirroring_wins_over_camera", ctrl.visualState === "mirroring")
        livePill.kind = "mirroring"
        ok("camera_shows_as_second_dot", livePill.cameraAlso === true && livePill.audioOnly === true
            && livePill.label === "iPhone audio")
        feed({ type: "airplay", state: "mirroring", device: "x" })
        ok("pill_labels", livePill.label === "iPhone screen" && livePill.glyph === "airplay")
        livePill.kind = "camera"
        ok("camera_label", livePill.label === "iPhone camera" && livePill.cameraAlso === false)
        livePill.kind = "mirroring"
        feed({ type: "airplay", state: "idle" })
        ok("camera_remains_when_mirroring_stops", ctrl.visualState === "camera", ctrl.visualState)

        ctrl.showMedia()
        ok("media_cannot_preempt_live", ctrl.visualState === "camera")
        ctrl.showVolume(0.5, false, "x")
        ok("osd_preempts_live", ctrl.visualState === "volume")
        ctrl.clearTransient()
        ctrl.syncPhoneLive()
        ok("live_restored_after_osd", ctrl.visualState === "camera", ctrl.visualState)
        feed({ type: "call", id: "c4", state: "active", number: "+1", startedAt: 1 })
        ok("callActive_preempts_live", ctrl.visualState === "callActive")
        feed({ type: "call", id: "c4", state: "ended" })
        ctrl.clearTransient()
        ctrl.syncPhoneLive()
        ok("live_restored_after_call", ctrl.visualState === "camera", ctrl.visualState)
        feed({ type: "status", connected: false, device: null })
        ok("live_survives_bluetooth_disconnect", ctrl.visualState === "camera")
        feed({ type: "camera", active: false })
        ok("live_leaves_when_inactive", ctrl.visualState === "dormant" && ctrl.transientState === "", ctrl.visualState)

        // --- network trust row ---
        root.trustCalls = []
        pwSat.service = trustService
        ok("trust_off_label", pwSat.networkTrusted === false && pwSat.mediaAvailable === false
            && pwSat.airplayValue === "Off" && pwSat.cameraLive === false)
        pwSat.toggleNetworkTrust()
        ok("trust_tap_runs_trust", root.trustCalls.join() === "trust")
        trustService.status = ({ trustedNetwork: true })
        ok("trust_on_label", pwSat.networkTrusted === true && pwSat.mediaAvailable === true
            && pwSat.airplayValue === "Ready")
        pwSat.toggleNetworkTrust()
        ok("trust_tap_when_trusted_untrusts", root.trustCalls.join() === "trust,untrust")
        pwSat.service = pwService

        // --- AirPlay password: never in the island, on request in the satellite ---
        pwView.service = pwService
        ok("pin_state_shows_device_no_secret", pwView.device === "Ada's iPhone"
            && pwView.children[0].children[0].text === "Ada's iPhone wants to AirPlay"
            && pwView.children[0].children[1].text === "Enter the AirPlay password \u00b7 Show it from the iPhone menu"
            && pwView.children[0].children[0].text.indexOf("k3J9") < 0)
        ok("pin_texts_plaintext", pwView.children[0].children[0].textFormat === Text.PlainText
            && pwView.children[0].children[1].textFormat === Text.PlainText
            && pwView.children[0].children[0].elide === Text.ElideRight)
        pwView.service = ({ airplayDevice: "<b>x</b>", airplayPin: "k3J9" })
        ok("pin_device_not_rich_text", pwView.children[0].children[0].textFormat === Text.PlainText
            && pwView.children[0].children[0].text.indexOf("k3J9") < 0)
        ok("service_never_stores_pin", (feed({ type: "airplay", state: "pin", pin: "SECRET123", device: "d" }),
            PhoneService.airplayPin === ""))
        feed({ type: "airplay", state: "idle" })

        PhoneAttention.lockedOverride = true
        pwSat.toggleAirplayPassword()
        ok("locked_no_reveal", pwSat.revealedPassword === "" && root.pwCalls === 0)
        PhoneAttention.lockedOverride = false
        pwSat.toggleAirplayPassword()
        ok("reveal_on_request", pwSat.passwordRevealed && root.pwCalls === 1
            && pwSat.groupPassword(pwSat.revealedPassword) === "fixt ure- airp lay-\npw-n ot-r eal")
        PhoneAttention.lockedOverride = true
        ok("lock_clears_reveal", pwSat.revealedPassword === "")
        PhoneAttention.lockedOverride = false
        pwSat.toggleAirplayPassword()
        ok("reveal_again", pwSat.passwordRevealed)
        pwSat.visible = false
        ok("close_clears_reveal", pwSat.revealedPassword === "")
        pwSat.visible = true
        pwSat.toggleAirplayPassword()
        ok("reveal_before_timeout", pwSat.passwordRevealed)
        pwTimeout.start()

        // --- locked = no phone text ---
        PhoneAttention.lockedOverride = true
        ok("locked_toast_text_hidden", toast.preview === "" && toast.sender === "iPhone", toast.preview)
        ok("locked_blueferry_hidden", PhoneService.hideNotificationText("BlueFerry", true, true) === true
            && PhoneService.hideNotificationText("BlueFerry", false, true) === false
            && PhoneService.hideNotificationText("BlueFerry", true, false) === false
            && PhoneService.hideNotificationText("Signal", true, true) === false)
        PhoneAttention.lockedOverride = false
        ok("unlocked_toast_text_shown", toast.preview.length > 0 && toast.preview === toast.shown.text && toast.sender !== "iPhone", toast.preview)
        PhoneAttention.lockedOverride = null

        // --- attention gate (services/PhoneAttention.qml) ---
        PhoneAttention.lockedOverride = false
        PhoneAttention.idleOverride = true
        const before = PhoneService.recentMessages.length
        feed({ type: "message", id: "q1", threadId: "t1", from: { name: "Ada", number: "1" }, text: "quiet one", ts: 50, outgoing: false })
        ok("idle_message_quiet_but_recorded", ctrl.visualState === "dormant" && ctrl.transientState === ""
            && PhoneService.recentMessages.length === before + 1)
        feed({ type: "airplay", state: "pin", pin: "9999" })
        ok("idle_pin_quiet", ctrl.visualState === "dormant" && PhoneService.airplayState === "pin")
        PhoneAttention.idleOverride = false
        ok("pin_shows_when_active_again", ctrl.visualState === "airplayPin", ctrl.visualState)
        PhoneAttention.idleOverride = true
        ok("pin_leaves_when_idle", ctrl.visualState === "dormant", ctrl.visualState)
        feed({ type: "airplay", state: "idle" })
        PhoneAttention.idleOverride = false

        PhoneAttention.idleOverride = true
        feed({ type: "call", id: "g1", state: "incoming", number: "+1", name: "Ada" })
        ok("idle_call_is_ringing_card", ctrl.visualState === "call" && ctrl.transientPriority === 48, ctrl.visualState)
        PhoneAttention.idleOverride = false
        ok("call_card_when_active_again", ctrl.visualState === "call", ctrl.visualState)
        PhoneAttention.lockedOverride = true
        ok("locked_call_quiet", ctrl.visualState === "dormant" && PhoneService.call !== null, ctrl.visualState)
        PhoneAttention.lockedOverride = false
        ok("call_card_after_unlock", ctrl.visualState === "call", ctrl.visualState)
        feed({ type: "call", id: "g1", state: "ended" })
        ok("call_ends_clean", ctrl.visualState === "dormant" && PhoneService.call === null)

        ctrl.showPhoneMessage({ threadId: "t1", from: { name: "Ada", number: "1" }, text: "shown", ts: 60, outgoing: false })
        ok("active_message_toast", ctrl.visualState === "phoneMessage")
        PhoneAttention.lockedOverride = true
        ok("toast_cleared_on_lock", ctrl.visualState === "dormant" && ctrl.phoneMessageEntry === null)
        ctrl.showPhoneMessage({ threadId: "t1", from: { name: "Ada", number: "1" }, text: "nope", ts: 61, outgoing: false })
        feed({ type: "camera", active: true })
        ok("locked_message_and_live_quiet", ctrl.visualState === "dormant" && ctrl.transientState === "")
        PhoneAttention.lockedOverride = false
        ok("live_returns_after_unlock", ctrl.visualState === "camera", ctrl.visualState)
        feed({ type: "camera", active: false })
        PhoneAttention.idleOverride = null
        PhoneAttention.lockedOverride = null

        deferred = true
    }
    property bool deferred: false
    Timer {
        id: pwTimeout
        interval: 200
        onTriggered: {
            ok("reveal_clears_after_timeout", pwSat.revealedPassword === "")
            PhoneAttention.lockedOverride = null
            PhoneAttention.idleOverride = null
        console.log("=== PHONE STATES TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
        }
    }
}
