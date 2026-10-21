import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../applications"
import "../core"
import "../services"
import "model.js" as M

/**
 * DockModel -- what the dock shows, and the actions that change it.
 *
 * The merge itself is pure (model.js, unit-tested with fake clients); this
 * file only feeds it the live Hyprland client list and desktop entries, and
 * dispatches. Pins persist in SettingsStore "dock"."pins" (desktop ids). When
 * the key is unset the default pins apply, filtered to apps that are
 * installed.
 *
 * Tests can bypass the live feeds: set `testClients` / `testLookup` (non-null)
 * and the model uses those instead of Hyprland / DesktopEntries.
 */
QtObject {
    id: root

    // ---- inputs ----
    property var testClients: null          // array of client maps, or null = live
    property var testLookup: null           // function(id)->entry, or null = live
    property var testForClass: null
    property string testActiveAddress: ""
    property int revision: 0

    readonly property var storedPins: SettingsStore.value("dock", "pins", null)
    readonly property var pinTokens: Array.isArray(storedPins) ? storedPins : M.DEFAULT_PIN_TOKENS
    property var launching: ({})            // item key -> start ms
    // Mutated in place (never reassigned) so writing it inside the items
    // binding cannot retrigger that binding.
    readonly property var _orderHolder: ({ order: [] })
    readonly property var items: _build()
    readonly property var pinnedIds: items.filter(i => i.kind === "app" && i.pinned).map(i => i.desktopId)

    property Connections _ctx: Connections {
        target: HyprlandService
        function onContextChanged(): void { root.revision += 1 }
    }

    // ---- live feeds ----
    function adapt(e): var {
        return e ? { id: e.id, name: e.name, icon: e.icon, startupWMClass: e.startupWMClass, entry: e } : null
    }
    function lookup(id): var {
        if (root.testLookup) return root.testLookup(id)
        return adapt(DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id))
    }
    function forClass(cls): var {
        if (root.testForClass) return root.testForClass(cls)
        if (root.testLookup) return null
        return adapt(RunningApps.desktopEntryFor(cls))
    }
    function liveClients(): var {
        const out = []
        for (const t of HyprlandService.toplevels) {
            const i = t?.lastIpcObject || {}
            out.push({ address: String(i.address || t?.address || ""), "class": i.class, initialClass: i.initialClass,
                title: i.title || t?.title || "", workspaceName: String(i.workspace?.name || ""),
                focusHistoryID: Number(i.focusHistoryID), mapped: i.mapped !== false })
        }
        return out
    }
    function activeAddress(): string {
        if (root.testClients) return root.testActiveAddress
        return String(HyprlandService.focusedToplevel?.lastIpcObject?.address || "")
    }
    function _build(): var {
        root.revision                       // re-evaluate on compositor events
        const r = M.build({
            pins: root.pinTokens,
            clients: root.testClients || root.liveClients(),
            lookup: root.lookup, forClass: root.forClass,
            prevOrder: root._orderHolder.order, activeAddress: root.activeAddress(),
            launching: root.launching
        })
        root._orderHolder.order = r.order
        return r.items
    }

    // ---- bounce bookkeeping ----
    function markLaunching(item): void {
        const next = Object.assign({}, root.launching)
        next[item.key] = Date.now()
        root.launching = next
        expiry.restart()
    }
    property Timer expiry: Timer {
        interval: 500; repeat: true
        onTriggered: {
            const limit = DockMetrics.bounceMaxSeconds * 1000, now = Date.now()
            const next = {}
            let any = false
            for (const k in root.launching)
                if (now - root.launching[k] < limit) { next[k] = root.launching[k]; any = true }
            root.launching = next
            if (!any) running = false
        }
    }

    // ---- actions ----
    function dispatch(cmd): void { if (cmd) Hyprland.dispatch(cmd) }

    function launch(item): void {
        const entry = root.lookup(item.desktopId)?.entry
        if (!entry) return
        root.markLaunching(item)
        ApplicationService.launch(entry)
    }

    function activate(item): void {
        if (item.kind === "minimized") { root.restore(item.address); return }
        if (item.windowCount === 0 && item.minimizedAddresses?.length > 0) {
            root.restore(item.minimizedAddresses[0]); return
        }
        if (!item.running) { root.launch(item); return }
        const active = root.activeAddress()
        const here = item.addresses.indexOf(active) >= 0
        const ranks = {}
        for (const c of (root.testClients || root.liveClients()))
            ranks[c.address] = c.focusHistoryID
        root.dispatch(M.focusCmd(here && item.addresses.length > 1
            ? M.nextAddress(item.addresses, active, ranks) : item.addresses[0]))
    }

    function restore(address): void {
        root.dispatch(M.restoreCmd(address, HyprlandService.activeWorkspaceId))
        root.dispatch(M.focusCmd(address))
    }

    function focusWindow(address): void { root.dispatch(M.focusCmd(address)) }

    function quit(item): void {
        for (const a of item.addresses.concat(item.minimizedAddresses || []))
            root.dispatch(M.closeCmd(a))
    }

    function newInstance(item): void {
        const entry = root.lookup(item.desktopId)?.entry
        if (!entry) return
        ApplicationService.launch(entry)
    }

    // ---- pins ----
    // Saving must not drop pins that don't resolve right now (desktop entries still
    // loading at startup, or an app briefly uninstalled): carry those tokens over.
    function setPins(ids): void {
        const kept = root.pinTokens.filter(t => ids.indexOf(t) < 0 && M.resolvePin(t, root.lookup) === null)
        SettingsStore.setValue("dock", "pins", ids.concat(kept))
    }
    function pin(item): void {
        if (!item.desktopId || root.pinnedIds.indexOf(item.desktopId) >= 0) return
        root.setPins(root.pinnedIds.concat([item.desktopId]))
    }
    function unpin(item): void { root.setPins(root.pinnedIds.filter(id => id !== item.desktopId)) }
    // `ids` = the new pinned order (desktop ids).
    function reorder(ids): void { root.setPins(ids) }
}
