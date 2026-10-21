// Logic test for services/NotificationService.qml's toast queue and history
// persistence. The service is instantiated from its file rather than through
// the singleton: an instance with serverAllowed=false never claims the
// org.freedesktop.Notifications name, and statePath points at a temp file, so
// a live shell's ~/.local/state is never read or written. Notifications are
// plain JS objects with the members receive() reads (closed.connect, dismiss,
// urgency, actions). The toast is ended by calling toastFinished() directly,
// which is what island/Island.qml does when the popup has left the screen.
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "core"
import "services"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    readonly property string tmpPath: "/tmp/qmlrice-notif-queue-test-" + Date.now() + ".json"

    property var svcReload: null

    function makeService(path) {
        const component = Qt.createComponent(Qt.resolvedUrl("services/NotificationService.qml"))
        if (component.status !== Component.Ready) {
            console.log("component error: " + component.errorString())
            return null
        }
        return component.createObject(root, { serverAllowed: false, statePath: path })
    }

    function note(id, app, title, critical) {
        return {
            id: id, appName: app, summary: title, body: "", appIcon: "", desktopEntry: "",
            image: "", urgency: critical ? NotificationUrgency.Critical : NotificationUrgency.Normal,
            actions: [], tracked: false, dismissed: false,
            closed: { connect: function(fn) {} },
            dismiss: function() { this.dismissed = true }
        }
    }

    Timer {
        interval: 30; running: true; repeat: false
        onTriggered: root.run()
    }

    function run() {
        const s = makeService(root.tmpPath)
        if (!s) {
            root.ok("service_instantiates", false)
            return root.finish()
        }
        // Defaults are read from the live settings store. The queue behaviour
        // under test only applies when popups are on and DND is off.
        root.ok("popups_enabled_precondition",
            Config.notifications.showPopups && !Config.notifications.doNotDisturb,
            "showPopups=" + Config.notifications.showPopups
                + " doNotDisturb=" + Config.notifications.doNotDisturb)

        // ---- FIFO order ------------------------------------------------
        s.receive(note(1, "A", "first", false))
        s.receive(note(2, "B", "second", false))
        s.receive(note(3, "C", "third", false))
        root.ok("first_arrival_shown", s.current && s.current.id === 1, "current=" + (s.current ? s.current.id : "null"))
        root.ok("later_arrivals_queued_not_shown", s.queue.length === 2
            && s.queue[0].id === 2 && s.queue[1].id === 3, "queue=" + s.queue.map(e => e.id).join(","))
        root.ok("busy_while_toast_on_screen", s.toastBusy === true)

        s.toastFinished()
        root.ok("next_shown_after_finish_fifo", s.current && s.current.id === 2,
            "current=" + (s.current ? s.current.id : "null"))
        s.toastFinished()
        root.ok("third_shown_after_second", s.current && s.current.id === 3)
        s.toastFinished()
        root.ok("queue_drains_to_idle", s.current === null && s.toastBusy === false
            && s.queue.length === 0)

        // ---- critical jumps the queue ---------------------------------
        s.receive(note(10, "A", "base", false))
        s.receive(note(11, "B", "normal-1", false))
        s.receive(note(12, "C", "normal-2", false))
        s.receive(note(13, "D", "critical", true))
        root.ok("critical_queued_ahead_of_normals", s.queue.length === 3
            && s.queue[0].id === 13 && s.queue[1].id === 11 && s.queue[2].id === 12,
            "queue=" + s.queue.map(e => e.id).join(","))
        root.ok("visible_toast_not_replaced_by_critical", s.current && s.current.id === 10)
        s.toastFinished()
        root.ok("critical_shown_next", s.current.id === 13 && s.current.critical === true)
        s.toastFinished()
        root.ok("normals_resume_in_order", s.current.id === 11)
        s.toastFinished(); s.toastFinished()
        root.ok("drained_after_critical_jump", s.current === null && s.queue.length === 0)

        // ---- overflow drops the oldest normal, keeps it in history ----
        s.receive(note(20, "A", "head", false))
        for (let i = 21; i <= 27; i++)
            s.receive(note(i, "B", "burst-" + i, false))
        root.ok("queue_capped_at_limit", s.queue.length === s.queueLimit && s.queueLimit === 5,
            "length=" + s.queue.length)
        root.ok("overflow_kept_newest_five", s.queue.map(e => e.id).join(",") === "23,24,25,26,27",
            "queue=" + s.queue.map(e => e.id).join(","))
        const dropped = s.history.find(e => e.id === 21)
        root.ok("dropped_toast_stays_in_history", dropped !== undefined && dropped.active === true)

        // A critical in a full queue still lands at the head; the oldest normal goes.
        s.receive(note(30, "D", "urgent", true))
        root.ok("critical_in_full_queue_kept", s.queue.length === 5 && s.queue[0].id === 30
            && s.queue.every(e => e.id !== 23), "queue=" + s.queue.map(e => e.id).join(","))
        s.toastFinished()
        root.ok("queue_head_after_overflow", s.current.id === 30)

        // Queued toast closed by its sender must not be presented later.
        s.receive(note(40, "A", "keep-open", false))
        s.receive(note(41, "B", "closed-early", false))
        s.markClosed(41, s.history.find(e => e.id === 41).timestamp)
        root.ok("closed_queued_toast_removed", s.queue.every(e => e.id !== 41))

        // Removing a queued toast from the centre drops it from the queue.
        s.receive(note(42, "C", "removed", false))
        s.remove(s.history.find(e => e.id === 42))
        root.ok("removed_queued_toast_leaves_queue", s.queue.every(e => e.id !== 42))

        // Per-app clear removes every entry in that group, live or queued.
        s.clearApp("B")
        root.ok("clear_app_removes_group", s.history.every(e => e.appName !== "B"),
            "history=" + s.history.map(e => e.appName + ":" + e.id).join(","))
        s.clearHistory()
        s.toastFinished()
        root.ok("clear_history_resets_queue", s.queue.length === 0 && s.history.length === 0)

        root.runPersistence()
    }

    // ---- persistence round-trip ------------------------------------------
    // FileView loads asynchronously, so each step waits for `loaded` first.
    property int persistStep: 0
    property var persistA: null

    Timer {
        id: persistTimer
        interval: 20; repeat: true
        onTriggered: root.persistTick()
    }

    function runPersistence() {
        root.persistA = makeService(root.tmpPath)
        // ---- iPhone (ANCS) entries: actions, body click, source clear -------
        // BlueFerry posts ANCS popups as transient "BlueFerry" notifications with
        // an empty "default" action plus the iPhone's own buttons.
        // A scratch service: the persistence checks below own root.tmpPath's history.
        const s = makeService(root.tmpPath + ".ancs")
        const invokedActions = []
        const ancsDismissals = []
        function ancsNote(id) {
            const n = note(id, "BlueFerry", "📱 WhatsApp · Maya", false)
            n.transient = true
            n.body = "see you soon"
            n.actions = [
                { identifier: "default", text: "", invoke: function() { invokedActions.push("default") } },
                { identifier: "ancs-positive", text: "Accept", invoke: function() { invokedActions.push("accept") } },
                { identifier: "ancs-negative", text: "Decline", invoke: function() { invokedActions.push("decline") } }
            ]
            n.dismiss = function() { ancsDismissals.push("source" + id); this.dismissed = true }
            return n
        }

        s.receive(ancsNote(200))
        const ancsEntry = s.history[0]
        root.ok("ancs_flag_set", ancsEntry.ancs === true, String(ancsEntry.ancs))
        root.ok("ancs_split_into_app_and_headline", ancsEntry.appName === "WhatsApp" && ancsEntry.title === "Maya",
            ancsEntry.appName + " / " + ancsEntry.title)
        root.ok("ancs_buttons_drop_default", s.visibleActions(ancsEntry).map(a => a.text).join("|") === "Accept|Decline",
            s.visibleActions(ancsEntry).map(a => a.text).join("|"))
        root.ok("ancs_body_click_is_default", s.canActivate(ancsEntry) === true)
        s.invokeAction(ancsEntry, 1)
        root.ok("ancs_button_index_maps_to_visible_action", invokedActions.join() === "decline", invokedActions.join())

        // Body click on a live ANCS entry runs the iPhone's default action.
        s.receive(ancsNote(202))
        const ancsBody = s.history[0]
        invokedActions.length = 0
        s.activate(ancsBody)
        root.ok("ancs_body_click_invokes_default", invokedActions.join() === "default", invokedActions.join())

        // Banner close on an ANCS entry clears its source and leaves history inactive.
        s.receive(ancsNote(203))
        const ancsClosed = s.history[0]
        ancsDismissals.length = 0
        s.dismissBanner(ancsClosed)
        root.ok("ancs_banner_dismiss_clears_source", ancsDismissals.join() === "source203"
            && s.history[0].id === 203 && s.history[0].active === false, ancsDismissals.join())

        // Other apps: a banner close keeps the notification live and never touches the source.
        const plain = note(201, "Mail", "Invoice", false)
        plain.dismiss = function() { ancsDismissals.push("mail") }
        s.receive(plain)
        const plainEntry = s.history[0]
        root.ok("plain_not_ancs", plainEntry.ancs === false, String(plainEntry.ancs))
        s.dismissBanner(plainEntry)
        root.ok("plain_banner_close_keeps_live", plainEntry.active === true && ancsDismissals.indexOf("mail") < 0)
        Quickshell.execDetached(["rm", "-f", root.tmpPath + ".ancs"])

        root.persistStep = 0
        persistTimer.start()
    }

    function persistTick() {
        if (root.persistStep === 0) {
            if (!root.persistA.loaded)
                return
            const a = root.persistA
            a.receive(note(100, "Mail", "Invoice ready", false))
            a.receive(note(101, "Chat", "hi", true))
            a.history[0].actions = [{ identifier: "default", text: "Open", invoke: function() {} }]
            a.flushHistory()
            root.svcReload = makeService(root.tmpPath)
            root.persistStep = 1
            return
        }
        if (!root.svcReload.loaded)
            return
        persistTimer.stop()
        root.checkRestored()
    }

    function checkRestored() {
        const b = root.svcReload
        root.ok("restored_count", b.history.length === 2, "count=" + b.history.length)
        const first = b.history[0]
        const second = b.history[1]
        root.ok("restored_fields_kept", first && first.id === 101 && first.title === "hi"
            && first.critical === true && first.appName === "Chat"
            && second && second.id === 100 && second.title === "Invoice ready",
            "first=" + (first ? first.title : "-") + " second=" + (second ? second.title : "-"))
        root.ok("restored_rows_inert", first && first.active === false && first.source === null
            && first.actions.length === 0 && first.provenance === null)
        root.ok("restored_not_presented", b.current === null && b.queue.length === 0)

        // A live notification whose id matches a restored row must not evict it.
        b.receive(note(100, "Mail", "Invoice ready (new)", false))
        root.ok("same_id_live_arrival_keeps_restored_row", b.history.length === 3
            && b.history.filter(e => e.id === 100).length === 2,
            "count=" + b.history.length)

        // Respect historyLimit on restore.
        const limit = Config.notifications.historyLimit
        root.ok("history_limit_is_bounded", b.history.length <= limit, "limit=" + limit)

        root.finish()
    }

    function finish() {
        Quickshell.execDetached(["rm", "-f", root.tmpPath])
        for (const line of root.log) console.log(line)
        const failed = root.log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
