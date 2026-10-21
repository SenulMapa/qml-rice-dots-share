import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"

/**
 * MacBanners -- the Tahoe notification banners (spec 3.1, 3.2).
 *
 * Wired by mac/MacStyleRoot.qml only while uiStyle is "mac". Each banner is
 * its own layer window (namespace qml-rice:mac-banner), stacked down from the
 * top right, newest on top, at most `maxBanners`.
 *
 * Queue contract. showNotification() returns early in mac style, so this
 * surface owns the toast. A banner is adopted as soon as presentationRequested
 * fires, and toastFinished() is called at the same moment. That frees the
 * service's single toast slot so the next toast can stack. Waiting for each
 * banner's exit instead would serialise banners, so no stack could form.
 * The service's queue therefore stays short. Overflow past the stack limit
 * retires the oldest banner early. Its notification stays in history.
 *
 * Lifecycle. A banner leaves on timeout, on click (after activate), on X or
 * swipe, when its notification leaves NotificationService.history (closed by
 * the sender, removed, or cleared), or when DND or popups are turned off.
 */
Item {
    id: root

    visible: false
    width: 0
    height: 0

    readonly property int maxBanners: MacTokens.bannerMaxVisible

    // uid -> notification entry. Reassigned, never mutated, so bindings see it.
    property var live: ({})
    property int nextUid: 1

    ListModel {
        id: rows
    }

    // Newest first. Banners past maxBanners stay queued behind the stack
    // (held, timers paused, hidden) and show as the front ones leave. Only a
    // deep pile (maxBanners + pileCap) retires its oldest, so memory stays bounded.
    readonly property int pileCap: 5
    readonly property int pileCount: Math.max(0, rows.count - MacTokens.bannerMaxVisible)

    function adopt(entry): void {
        if (!entry)
            return
        if (rows.count >= root.maxBanners + root.pileCap) {
            for (let i = rows.count - 1; i >= 0; i--) {
                const row = rows.get(i)
                if (!row.leaving && !root.live[row.uid]?.critical) {
                    rows.setProperty(i, "leaving", true)
                    break
                }
            }
        }
        const uid = root.nextUid++
        root.live = Object.assign({}, root.live, { [uid]: entry })
        rows.insert(0, { uid: uid, leaving: false })
    }

    function removeUid(uid: int): void {
        for (let i = 0; i < rows.count; i++) {
            if (rows.get(i).uid === uid) {
                rows.remove(i)
                break
            }
        }
        const pruned = Object.assign({}, root.live)
        delete pruned[uid]
        root.live = pruned
    }

    function retireRows(critical: bool): void {
        for (let i = 0; i < rows.count; i++) {
            const row = rows.get(i)
            if (!row.leaving && !!root.live[row.uid]?.critical === critical)
                rows.setProperty(i, "leaving", true)
        }
    }

    // A banner stays only while its notification is still live in history.
    function syncHistory(): void {
        for (let i = 0; i < rows.count; i++) {
            const row = rows.get(i)
            if (row.leaving)
                continue
            const entry = root.live[row.uid]
            const found = NotificationService.history.find(item =>
                item.id === entry?.id && item.timestamp === entry?.timestamp)
            if (!found || !found.active)
                rows.setProperty(i, "leaving", true)
        }
    }

    // Style switch (or any unload of this root): banners still on screen go back
    // to the service queue, so the pill presents them. Nothing is dropped; the
    // notifications stay in history either way.
    Component.onDestruction: {
        const live = []
        for (let i = 0; i < rows.count; i++) {
            const row = rows.get(i)
            const entry = root.live[row.uid]
            if (!row.leaving && entry)
                live.push(entry)
        }
        for (const entry of live) {
            const found = NotificationService.history.find(item =>
                item.id === entry.id && item.timestamp === entry.timestamp && item.active)
            if (found)
                NotificationService.enqueue(entry)
        }
        if (live.length > 0 && !NotificationService.toastBusy)
            NotificationService.presentNext()
    }

    Connections {
        target: NotificationService

        function onPresentationRequested(critical: bool): void {
            root.adopt(NotificationService.current)
            NotificationService.toastFinished()
        }

        function onPresentationDismissRequested(): void {
            root.retireRows(false)
        }

        function onHistoryChanged(): void {
            root.syncHistory()
        }

        function onDoNotDisturbChanged(): void {
            if (NotificationService.doNotDisturb)
                root.retireRows(false)
        }
    }

    Repeater {
        model: rows

        // One layer window per banner, built only with layer shell (see
        // MacTokens.layerShell). The offscreen harness keeps the queue and
        // draws nothing.
        delegate: Loader {
            id: slot

            required property int uid
            required property bool leaving
            required property int index

            active: MacTokens.layerShell
            // Chosen once, at creation: banners already on screen keep their
            // screen when focus moves (setSource props are not re-bound).
            Component.onCompleted: if (active)
                setSource("MacBannerWindow.qml", { screen: MacScreen.choose() })
            onLoaded: {
                item.owner = root
                item.uid = Qt.binding(() => slot.uid)
                item.index = Qt.binding(() => slot.index)
                item.leaving = Qt.binding(() => slot.leaving)
            }
        }
    }
}
