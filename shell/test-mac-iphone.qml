// Component tests for the iPhone pieces of the mac Notification Center: the
// battery widget, the notification action buttons, the New Message sheet and
// the column's hand-off from the Spotlight. Stand-ins replace PhoneService, so
// no daemon is spawned and nothing is sent. Run with
// QMLRICE_NOTIFICATION_SERVER=0 so the real NotificationService never claims
// the notification server.
import QtQuick
import Quickshell
import "core"
import "services"
import "mac"

Item {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    // ---- stand-ins ----------------------------------------------------------
    QtObject {
        id: batteryPhone
        property var status: ({ device: { name: "Ada's iPhone" }, battery: 82, charging: null })
        property bool connected: true
    }

    QtObject {
        id: composePhone
        property var sent: []
        property var sendReply: ({ ok: true })
        function findContacts(query, cb) {
            cb({ v: 1, ok: true, contacts: [{ name: "Maya", number: "+15550001" }] })
        }
        function send(number, text, cb) {
            composePhone.sent.push(number + "|" + text)
            cb(composePhone.sendReply)
        }
    }

    QtObject {
        id: columnPhone
        property var composeTarget: null
        property var status: null
        property bool connected: false
        property bool callsEnabled: false
        function clearCompose() { columnPhone.composeTarget = null }
    }

    MacWidgetBattery {
        id: battery
        phone: batteryPhone
    }

    MacNotificationActions {
        id: actions
        entry: ({
            id: 1, timestamp: 1, active: true, source: null,
            actions: [
                { identifier: "default", text: "", invoke: function() {} },
                { identifier: "ancs-positive", text: "Accept", invoke: function() {} },
                { identifier: "ancs-negative", text: "Decline", invoke: function() {} }
            ]
        })
    }

    MacNotificationActions {
        id: noActions
        entry: ({
            id: 2, timestamp: 2, active: true, source: null,
            actions: [{ identifier: "default", text: "", invoke: function() {} }]
        })
    }

    MacCompose {
        id: compose
        phone: composePhone
    }

    MacNotificationColumn {
        id: column
        phone: columnPhone
        notifications: []
    }

    MacNotificationCard {
        id: card
        entry: ({
            id: 3, timestamp: 3, active: true, source: null, appName: "BlueFerry",
            title: "Maya", body: "hi", actions: [{ identifier: "ancs-positive", text: "Accept", invoke: function() {} }]
        })
    }

    // A banner with action buttons: compiles, shows the buttons, and reports them.
    MacBanner {
        id: banner
        entry: ({
            id: 4, timestamp: 4, active: true, source: null, appName: "BlueFerry", critical: false,
            title: "Maya", body: "hi", actions: [
                { identifier: "default", text: "", invoke: function() {} },
                { identifier: "ancs-positive", text: "Accept", invoke: function() {} }
            ]
        })
    }

    Component.onCompleted: {
        let bannerAction = -1
        let bannerDismissals = 0
        banner.actionInvoked.connect(index => { bannerAction = index })
        banner.dismissed.connect(() => { bannerDismissals++ })
        banner.actionInvoked(0)
        banner.dismissed()
        ok("banner_reports_action_index", bannerAction === 0)
        ok("banner_reports_user_dismissal", bannerDismissals === 1)
        ok("banner_not_critical", banner.critical === false)

        // ---- battery widget ----------------------------------------------------
        ok("battery_name_from_device", battery.line.name === "Ada's iPhone", battery.line.name)
        ok("battery_percent", battery.line.percent === "82%", battery.line.percent)
        ok("battery_connected_state", battery.line.state === "Connected", battery.line.state)
        ok("battery_online_flag", battery.online === true)
        batteryPhone.status = ({ device: { name: "Ada's iPhone" }, battery: 40, charging: true })
        ok("battery_charging_state", battery.line.state === "Charging" && battery.line.percent === "40%",
            battery.line.state)
        batteryPhone.connected = false
        ok("battery_offline_reads_offline", battery.line.percent === "Offline"
            && battery.line.state === "Not connected" && battery.online === false)
        ok("battery_hidden_when_phone_disabled", battery.visible === false && Config.phone.enabled === false)

        // ---- action buttons ----------------------------------------------------
        ok("actions_visible_when_offered", actions.visible === true && actions.actions.length === 2,
            String(actions.actions.length))
        ok("actions_skip_default", actions.actions.map(a => a.text).join("|") === "Accept|Decline")
        ok("actions_take_height", actions.implicitHeight > 0 && actions.height === actions.implicitHeight)
        ok("no_buttons_when_only_default", noActions.visible === false && noActions.implicitHeight === 0)
        let invokedWith = -1
        actions.invoked.connect(index => { invokedWith = index })
        actions.invoked(1)
        ok("button_reports_visible_index", invokedWith === 1, String(invokedWith))
        ok("card_shows_actions", card.height > 0 && card.activatable === true)

        // ---- New Message sheet -------------------------------------------------
        ok("compose_cannot_send_without_recipient", compose.canSend === false)
        compose.setRecipient({ name: "Maya", number: "+15550001" })
        ok("compose_recipient_set", compose.recipient.number === "+15550001")
        ok("compose_empty_text_cannot_send", compose.canSend === false)
        compose.draft = "  on my way  "
        ok("compose_text_enables_send", compose.canSend === true)
        ok("compose_send_does_not_run_by_itself", composePhone.sent.length === 0)
        compose.send()
        ok("compose_send_on_press_only", composePhone.sent.join() === "+15550001|on my way",
            composePhone.sent.join())
        ok("compose_sent_clears_text", compose.draft === "" && compose.status === "Sent", compose.status)

        composePhone.sendReply = ({ ok: false, error: "iPhone not connected" })
        compose.draft = "retry me"
        compose.send()
        ok("compose_failure_keeps_text", compose.draft === "retry me" && compose.status === "iPhone not connected",
            compose.status)
        ok("compose_not_sending_after_failure", compose.sending === false)

        composePhone.sendReply = ({ ok: true })
        compose.reset()
        compose.draft = "orphan"
        compose.send()
        // Two sends so far (the failed one was still attempted); none added here.
        ok("compose_without_recipient_sends_nothing", composePhone.sent.length === 2 && compose.recipient === null)

        compose.query = "ma"
        compose.search()
        ok("compose_contact_hits", compose.hits.length === 1 && compose.hits[0].name === "Maya", JSON.stringify(compose.hits))
        compose.query = "+1555"
        compose.search()
        ok("compose_typed_number_first", compose.hits.length === 2 && compose.hits[0].number === "+1555"
            && compose.hits[1].name === "Maya", JSON.stringify(compose.hits))
        compose.query = ""
        compose.search()
        ok("compose_empty_query_clears_hits", compose.hits.length === 0)

        // ---- column hand-off from the Spotlight -------------------------------
        ok("column_closed_by_default", column.composing === false)
        columnPhone.composeTarget = ({ name: "Maya", number: "+15550001" })
        ok("column_opens_sheet_on_target", column.composing === true && columnPhone.composeTarget === null)
        column.composing = false

        console.log("=== MAC IPHONE TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
