pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../core"

Singleton {
    id: root

    // QMLRICE_NOTIFICATION_SERVER=0 keeps this singleton from claiming the
    // org.freedesktop.Notifications name, so offscreen harnesses can run next
    // to a live shell.
    property bool serverAllowed: Quickshell.env("QMLRICE_NOTIFICATION_SERVER") !== "0"
    readonly property bool serverEnabled: serverAllowed
        && Config.notifications.enabled && Config.notifications.takeOverServer
    readonly property bool coexistenceMode: Config.notifications.enabled
        && !Config.notifications.takeOverServer
    readonly property bool doNotDisturb: Config.notifications.doNotDisturb
    property var history: []
    property var current: null
    // Toasts waiting behind the one on screen. Capped so a burst cannot build
    // an unbounded backlog; a dropped toast stays in history.
    readonly property int queueLimit: 5
    property var queue: []
    // True from the moment a toast is handed to the island until the island
    // reports that its exit has finished. `current` is cleared earlier (on
    // click), and a new toast must not land inside that exit fade.
    property bool toastBusy: false
    // The D-Bus reply can reach the observer just before Quickshell delivers
    // the matching Notification object. Keep only a short, bounded in-memory
    // handoff so that ordering race does not discard exact provenance.
    property var pendingProvenance: ({})
    property var pendingExactFocus: null
    property var pendingTransientDismiss: null
    property bool provenanceRestartPending: false
    readonly property string provenanceHelperPath:
        Quickshell.shellDir + "/scripts/notification-provenance.py"
    property string statePath: resolveStateRoot() + "/qml-rice/notifications.json"
    property bool loaded: false

    readonly property int count: history.length
    readonly property bool hasCurrent: current !== null
    readonly property bool currentCritical: current?.critical ?? false

    signal presentationRequested(bool critical)
    signal presentationDismissRequested()
    // Emitted before removal so a transient click can tear down its overlay
    // before the generic current-cleared signal exposes any hover state.
    signal transientDismissRequested()
    signal activationCompleted()

    function plainText(value: string): string {
        return (value || "")
            .replace(/<img\b[^>]*>/gi, "")
            .replace(/<br\s*\/?>/gi, " ")
            .replace(/<[^>]+>/g, "")
            // Senders escape with numeric references too (Python's html.escape
            // turns ' into &#x27;). &amp; goes last so "&amp;lt;" stays "&lt;".
            .replace(/&#x([0-9a-f]+);/gi, (m, h) => String.fromCodePoint(parseInt(h, 16)))
            .replace(/&#([0-9]+);/g, (m, d) => String.fromCodePoint(parseInt(d, 10)))
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"")
            .replace(/&apos;/g, "'")
            .replace(/&nbsp;/g, " ")
            .replace(/&amp;/g, "&")
            .trim()
    }

    // iPhone apps have no desktop entry here, so guess the icon theme name:
    // "WhatsApp" is whatsapp-desktop / whatsapp-for-linux in Papirus, while
    // "Reddit" is plain reddit. First existing candidate wins; "" falls back
    // to the avatar's letter.
    function ancsIconName(app: string): string {
        const base = (app || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
        if (!base)
            return ""
        for (const name of [base, base + "-desktop", base + "-for-linux", base + "-nativefier", base.replace(/-/g, "")]) {
            if (Quickshell.iconPath(name, true))
                return name
        }
        return ""
    }

    // Untyped so the queue and persistence can be driven by plain objects.
    function receive(notification): void {
        if (!notification)
            return

        notification.tracked = true
        const entry = {
            id: notification.id,
            source: notification,
            appName: notification.appName || "Application",
            appIcon: notification.appIcon || "",
            desktopEntry: notification.desktopEntry || "",
            image: notification.image || "",
            title: plainText(notification.summary) || "Notification",
            body: plainText(notification.body),
            urgency: notification.urgency,
            critical: notification.urgency === NotificationUrgency.Critical,
            timestamp: Date.now(),
            // Preserve unlabeled `default` actions: many applications use
            // those specifically for clicking the notification body.
            actions: (notification.actions || []).filter(action => !!action),
            provenance: takePendingProvenance(notification.id),
            // An iPhone (ANCS) notification relayed by BlueFerry. Its clear is
            // synced back to the phone through source.dismiss() (dismissBanner).
            ancs: notification.appName === "BlueFerry" && notification.transient === true,
            active: true
        }

        // iPhone app notifications relayed by BlueFerry: show the real app.
        if (entry.appName === "BlueFerry" && notification.transient) {
            const ancs = PhoneService.parseAncsTitle(entry.title)
            if (ancs.app) {
                entry.appName = ancs.app
                entry.appIcon = ancsIconName(ancs.app)
                entry.title = ancs.title
            }
        }

        // Restored history uses ids from an earlier session, which the server
        // can reuse, so only a live entry is replaced by a same-id arrival.
        history = [entry].concat(history.filter(existing => !existing.active
                || existing.id !== entry.id))
            .slice(0, Config.notifications.historyLimit)
        notification.closed.connect(reason => markClosed(entry.id, entry.timestamp))

        // The sender's own name: an iPhone entry was renamed to its app above.
        const sender = notification.appName || ""
        if (presentable(entry) && !PhoneService.suppressPopup(
                sender, Config.phone.enabled && PhoneService.active,
                !!notification.transient)
                && !PhoneService.hideNotificationText(sender,
                    PhoneAttention.locked, Config.phone.enabled)) {
            if (toastBusy)
                enqueue(entry)
            else
                showToast(entry)
        }
    }

    function presentable(entry): bool {
        return entry.critical
            ? Config.notifications.allowCriticalAlerts
            : Config.notifications.showPopups && !doNotDisturb
    }

    function showToast(entry): void {
        current = entry
        toastBusy = true
        // Fallback clock only: the island's finished signal normally arrives
        // first. It covers a toast that is pre-empted or has no island to show it.
        toastTimer.interval = (entry.critical ? Config.notifications.criticalTimeout
            : Config.notifications.timeout) + Animations.fast + 40
        toastTimer.restart()
        presentationRequested(entry.critical)
    }

    // Criticals keep their own arrival order and sit ahead of normal toasts.
    function enqueue(entry): void {
        const pending = queue.slice()
        if (entry.critical) {
            let at = 0
            while (at < pending.length && pending[at].critical)
                at++
            pending.splice(at, 0, entry)
        } else {
            pending.push(entry)
        }
        if (pending.length > queueLimit) {
            // Drop the oldest normal toast. Falls back to the oldest critical
            // only when the queue holds nothing else.
            let drop = pending.findIndex(item => !item.critical)
            if (drop < 0)
                drop = 0
            pending.splice(drop, 1)
        }
        queue = pending
    }

    function presentNext(): void {
        while (queue.length > 0) {
            const next = queue[0]
            queue = queue.slice(1)
            // Settings may have changed while the toast waited; re-check.
            if (presentable(next)) {
                showToast(next)
                return
            }
        }
    }

    // Called by the island once a toast has fully left the screen.
    function toastFinished(): void {
        toastTimer.stop()
        current = null
        toastBusy = false
        presentNext()
    }

    function markClosed(id: int, timestamp: double): void {
        history = history.map(entry => {
            if (entry.id !== id || entry.timestamp !== timestamp)
                return entry
            return Object.assign({}, entry, { active: false, source: null, actions: [] })
        })
        queue = queue.filter(entry => entry.id !== id || entry.timestamp !== timestamp)
        if (current?.id === id && current?.timestamp === timestamp) {
            current = null
            presentationDismissRequested()
        }
    }

    function dismiss(entry): void {
        if (!entry)
            return
        if (entry.source)
            entry.source.dismiss()
        markClosed(entry.id, entry.timestamp)
    }

    function dismissCurrent(): void {
        dismiss(current)
    }

    // The user closed a banner (X or swipe). Other apps keep the notification
    // in the Notification Center and on their side; an iPhone (ANCS) one is
    // cleared through its source so BlueFerry can sync the clear to the phone.
    function dismissBanner(entry): void {
        if (entry?.ancs && entry.active)
            dismiss(entry)
    }

    function invokePrimaryAction(): void {
        activate(current)
    }

    function visibleActions(entry): var {
        return (entry?.actions || []).filter(action =>
            plainText(action?.text || "").length > 0)
    }

    function takePendingProvenance(notificationId): var {
        const key = String(notificationId)
        const pending = pendingProvenance[key]
        if (!pending)
            return null
        const updated = Object.assign({}, pendingProvenance)
        delete updated[key]
        pendingProvenance = updated
        return Date.now() - pending.timestamp <= 2000 ? pending.provenance : null
    }

    function cachePendingProvenance(notificationId, provenance): void {
        const key = String(notificationId)
        const updated = Object.assign({}, pendingProvenance)
        updated[key] = { provenance: provenance, timestamp: Date.now() }
        const keys = Object.keys(updated).sort((left, right) =>
            updated[left].timestamp - updated[right].timestamp)
        while (keys.length > 32)
            delete updated[keys.shift()]
        pendingProvenance = updated
    }

    function queueExactFocus(provenance): void {
        pendingExactFocus = provenance
        exactFocusTimer.restart()
    }

    function canActivate(entry): bool {
        if (!entry)
            return false
        if ((entry.actions || []).some(action => action?.identifier === "default"))
            return true
        return HyprlandService.hasValidExactProvenance(entry.provenance)
    }

    function activate(entry): bool {
        if (!entry)
            return false
        // When we have an exact live origin, release the expanded Island focus
        // grab first, then focus that verified window. A producer default action
        // is retained for entries without exact provenance.
        if (HyprlandService.hasValidExactProvenance(entry.provenance)) {
            requestTransientDismiss(entry)
            activationCompleted()
            queueExactFocus(entry.provenance)
            return true
        }
        const defaultAction = (entry.actions || []).find(action =>
            action?.identifier === "default")
        if (defaultAction) {
            defaultAction.invoke()
            requestTransientDismiss(entry)
            activationCompleted()
            return true
        }
        // Freedesktop metadata identifies an application, not a particular
        // window. Without a live producer action or revalidated provenance,
        // leaving the notification in history is safer than guessing.
        return false
    }

    function invokeAction(entry, index: int): void {
        const actions = visibleActions(entry)
        const action = actions.length > index ? actions[index] : null
        if (action)
            action.invoke()
    }

    function remove(entry): void {
        if (!entry)
            return
        if (entry.active && entry.source)
            entry.source.dismiss()
        history = history.filter(existing => existing.id !== entry.id
            || existing.timestamp !== entry.timestamp)
        queue = queue.filter(existing => existing.id !== entry.id
            || existing.timestamp !== entry.timestamp)
        if (current?.id === entry.id && current?.timestamp === entry.timestamp) {
            current = null
            presentationDismissRequested()
        }
    }

    function dismissTransient(): void {
        requestTransientDismiss(current)
    }

    function requestTransientDismiss(entry): void {
        if (!entry)
            return
        if (current?.id !== entry.id || current?.timestamp !== entry.timestamp) {
            remove(entry)
            return
        }
        if (pendingTransientDismiss)
            return
        pendingTransientDismiss = entry
        transientDismissRequested()
    }

    function completeTransientDismiss(): void {
        const entry = pendingTransientDismiss
        pendingTransientDismiss = null
        if (entry)
            remove(entry)
    }

    function clearHistory(): void {
        for (const entry of history) {
            if (entry.active && entry.source)
                entry.source.dismiss()
        }
        if (current)
            presentationDismissRequested()
        current = null
        queue = []
        history = []
    }

    // Matches the group key panels/NotificationCenter.qml builds.
    function clearApp(appName: string): void {
        for (const entry of history.filter(item =>
                (item.appName || "Application") === appName))
            remove(entry)
    }

    function toggleDoNotDisturb(): void {
        setDoNotDisturb(!doNotDisturb)
    }

    function setDoNotDisturb(enabled: bool): void {
        SettingsStore.setNotificationToggle("doNotDisturb", enabled)
        if (enabled && current) {
            current = null
            presentationDismissRequested()
        }
    }

    function setShowPopups(enabled: bool): void {
        SettingsStore.setNotificationToggle("showPopups", enabled)
        if (!enabled && current && !currentCritical) {
            current = null
            presentationDismissRequested()
        }
    }

    function setAllowCriticalAlerts(enabled: bool): void {
        SettingsStore.setNotificationToggle("allowCriticalAlerts", enabled)
        if (!enabled && currentCritical) {
            current = null
            presentationDismissRequested()
        }
    }

    function setDuration(key: string, milliseconds: real): void {
        SettingsStore.setNotificationDuration(key, milliseconds)
    }

    function setHistoryLimit(limit: real): void {
        if (SettingsStore.setNotificationHistoryLimit(limit))
            history = history.slice(0, Math.round(Math.max(20,
                Math.min(100, limit))))
    }

    function resetPreferences(): void {
        SettingsStore.resetNotifications()
        history = history.slice(0, 50)
    }

    // ── HISTORY PERSISTENCE ──────────────────────────────────────────────────
    // Same XDG_STATE_HOME-first resolution as services/TodoService.qml. Only
    // display fields are written: live handles (source, actions, provenance)
    // do not outlive the process, so restored rows are inert and inactive.
    function resolveStateRoot(): string {
        const explicit = Quickshell.env("XDG_STATE_HOME") || ""
        if (explicit.length > 0)
            return explicit
        return (Quickshell.env("HOME") || "") + "/.local/state"
    }

    function restoreHistory(raw: string): void {
        let saved = []
        try {
            const parsed = JSON.parse(raw)
            saved = Array.isArray(parsed?.history) ? parsed.history : []
        } catch (error) {
            saved = []
        }
        const restored = saved
            .filter(entry => entry && entry.id !== undefined && entry.timestamp)
            .map(entry => Object.assign({}, entry, {
                source: null, actions: [], provenance: null, active: false
            }))
        // Anything that arrived before the file loaded stays newest-first.
        history = history.concat(restored).slice(0, Config.notifications.historyLimit)
    }

    function saveHistory(): void {
        if (!root.loaded)
            return
        const rows = history.slice(0, Config.notifications.historyLimit).map(entry => ({
            id: entry.id, appName: entry.appName, appIcon: entry.appIcon,
            desktopEntry: entry.desktopEntry, image: entry.image, title: entry.title,
            body: entry.body, urgency: entry.urgency, critical: entry.critical,
            timestamp: entry.timestamp
        }))
        historyFile.setText(JSON.stringify({ version: 1, history: rows }, null, 2))
    }

    // Writes now instead of waiting for the debounce. Used by the test.
    function flushHistory(): void {
        saveTimer.stop()
        saveHistory()
    }

    onHistoryChanged: {
        // The restore itself assigns history before `loaded` is set, so it
        // never schedules a write back over the file it just read.
        if (root.loaded)
            saveTimer.restart()
    }

    property Timer saveTimer: Timer {
        interval: 500
        repeat: false
        onTriggered: root.saveHistory()
    }

    property Timer toastTimer: Timer {
        repeat: false
        onTriggered: root.toastFinished()
    }

    property FileView historyFile: FileView {
        path: root.statePath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.restoreHistory(text())
            root.loaded = true
        }
        onLoadFailed: error => {
            root.loaded = true
            if (error !== FileViewError.FileNotFound)
                console.warn("qml-rice NotificationService:", FileViewError.toString(error))
        }
        onSaveFailed: error => console.warn("qml-rice NotificationService:",
            FileViewError.toString(error))
    }

    function bindProvenance(notificationId, pid, availableToplevels): void {
        const id = Number(notificationId)
        const senderPid = Number(pid)
        if (!Number.isInteger(id) || id <= 0 || !Number.isInteger(senderPid)
                || senderPid <= 0)
            return
        const provenance = HyprlandService.snapshotToplevelForPid(senderPid,
            availableToplevels)
        if (!provenance)
            return
        const index = history.findIndex(entry => entry.id === id
            && entry.active && entry.provenance === null)
        if (index < 0) {
            cachePendingProvenance(id, provenance)
            return
        }
        const updated = history.slice()
        updated[index] = Object.assign({}, updated[index], { provenance: provenance })
        history = updated
        if (current?.id === id && current?.timestamp === updated[index].timestamp)
            current = updated[index]
    }

    function startProvenanceObserver(): void {
        if (!serverEnabled || provenanceProcess.running)
            return
        provenanceRestartPending = false
        provenanceProcess.command = ["python3", provenanceHelperPath]
        provenanceProcess.running = true
    }

    onServerEnabledChanged: {
        if (serverEnabled)
            startProvenanceObserver()
        else if (provenanceProcess.running)
            provenanceProcess.signal(15)
    }

    Component.onCompleted: startProvenanceObserver()

    property Timer provenanceRestartTimer: Timer {
        interval: 3000
        repeat: false
        onTriggered: root.startProvenanceObserver()
    }

    property Timer exactFocusTimer: Timer {
        // IslandController releases HyprlandFocusGrab after Animations.fast.
        interval: Animations.fast + 40
        repeat: false
        onTriggered: {
            const provenance = root.pendingExactFocus
            root.pendingExactFocus = null
            if (provenance)
                HyprlandService.focusExactProvenance(provenance)
        }
    }

    property Process provenanceProcess: Process {
        running: false
        stdout: SplitParser {
            onRead: line => {
                try {
                    const event = JSON.parse(line)
                    if (event?.version === 1 && event?.event === "provenance"
                            && Object.keys(event).length === 4)
                        root.bindProvenance(event.notificationId, event.pid)
                } catch (error) {
                    console.warn("Odyssey notification provenance parse failed")
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.serverEnabled && !root.provenanceRestartPending) {
                root.provenanceRestartPending = true
                root.provenanceRestartTimer.restart()
            }
        }
    }

    Instantiator {
        model: root.serverEnabled ? 1 : 0

        delegate: NotificationServer {
            keepOnReload: false
            persistenceSupported: true
            bodySupported: true
            bodyMarkupSupported: true
            bodyHyperlinksSupported: false
            bodyImagesSupported: true
            actionsSupported: true
            actionIconsSupported: true
            imageSupported: true
            inlineReplySupported: false

            onNotification: notification => root.receive(notification)
        }
    }
}
