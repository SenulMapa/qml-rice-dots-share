pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

/**
 * RunningApps -- the running applications as Alt+Tab sees them.
 *
 * Source: HyprlandService.toplevels (Hyprland's client list, refreshed on the
 * same compositor events the rest of the shell already listens to). Windows
 * are grouped by `class` and each group is ordered most-recently-used by the
 * compositor's focusHistoryID (0 = the focused window). A group's rank is its
 * best window's rank, so the group the user last focused comes first.
 *
 * Each group is a plain object:
 *   class        Hyprland class (the grouping key)
 *   name         desktop-entry name, falling back to the class
 *   title        title of the group's most recent window
 *   windowCount  number of windows in the group
 *   iconName     desktop-entry icon name, falling back to the class
 *   desktopId    desktop-entry id (e.g. "org.mozilla.firefox"), or ""
 *   addresses    window addresses, most recently used first
 *   specialName  name of the scratchpad the best window lives on, or ""
 *   rank         focusHistoryID of the best window (lower = more recent)
 */
QtObject {
    id: root

    // The shell's own windows (ShellCompatShortcuts registers them under the
    // default appid "quickshell") never appear in the switcher.
    readonly property var excludedClasses: ["quickshell", "org.quickshell"]

    // Bumped on every HyprlandService context change so the groups below
    // re-read the live lastIpcObject maps, which are not reactive on their own.
    property int revision: 0

    readonly property var groups: buildGroups(HyprlandService.toplevels, revision)
    readonly property int count: groups.length

    property Connections contextWatcher: Connections {
        target: HyprlandService
        function onContextChanged(): void { root.revision += 1 }
    }

    function ipc(toplevel): var {
        return toplevel?.lastIpcObject || {}
    }

    function lower(value): string {
        return String(value || "").toLowerCase()
    }

    function isShellWindow(className): bool {
        return root.excludedClasses.indexOf(className) !== -1
    }

    function rankOf(toplevel): int {
        const rank = Number(root.ipc(toplevel).focusHistoryID)
        return Number.isFinite(rank) ? rank : 1000000
    }

    function specialNameOf(toplevel): string {
        const workspaceName = String(root.ipc(toplevel).workspace?.name || "")
        return workspaceName.indexOf("special:") === 0
            ? workspaceName.slice("special:".length) : ""
    }

    // Desktop entry for a window class, matched by StartupWMClass, then the
    // entry id, then a case-insensitive version of either.
    function desktopEntryFor(className: string): var {
        if (!className)
            return null
        const direct = DesktopEntries.heuristicLookup(className)
            || DesktopEntries.heuristicLookup(root.lower(className))
        if (direct)
            return direct
        const wanted = root.lower(className)
        const entries = DesktopEntries.applications.values || []
        for (let i = 0; i < entries.length; ++i) {
            const entry = entries[i]
            if (root.lower(entry.startupWMClass) === wanted
                    || root.lower(entry.id) === wanted)
                return entry
        }
        return null
    }

    function buildGroups(toplevels, _revision): var {
        const byClass = ({})
        const order = []
        for (const toplevel of toplevels || []) {
            const info = root.ipc(toplevel)
            const className = String(info.class || info.initialClass || "")
            const address = String(info.address || toplevel?.address || "")
            if (className.length === 0 || root.isShellWindow(className))
                continue
            if (String(info.title || toplevel?.title || "").trim().length === 0)
                continue
            if (!HyprlandService.validAddress(address))
                continue
            const key = root.lower(className)
            if (!byClass[key]) {
                byClass[key] = { windows: [], className: className }
                order.push(key)
            }
            byClass[key].windows.push({ toplevel: toplevel, address: address,
                title: String(info.title || toplevel?.title || ""),
                rank: root.rankOf(toplevel), special: root.specialNameOf(toplevel) })
        }

        const result = []
        for (const key of order) {
            const bucket = byClass[key]
            const windows = bucket.windows.slice().sort((a, b) => a.rank - b.rank)
            const best = windows[0]
            const entry = root.desktopEntryFor(bucket.className)
            const specials = ({})
            for (const window of windows)
                specials[window.address] = window.special
            result.push({
                class: bucket.className,
                name: entry?.name || bucket.className,
                title: best.title,
                windowCount: windows.length,
                iconName: entry?.icon || bucket.className,
                desktopId: entry?.id || "",
                addresses: windows.map(window => window.address),
                specialName: best.special,
                specials: specials,
                rank: best.rank
            })
        }
        result.sort((a, b) => a.rank - b.rank)
        return result
    }

    // The live group for a class, or null when that app has no windows left.
    function byClass(className: string): var {
        const wanted = root.lower(className)
        for (const group of root.groups) {
            if (root.lower(group.class) === wanted)
                return group
        }
        return null
    }

    // The running group that belongs to a desktop entry, or null. Used by the
    // launcher to mark apps that are already open.
    function groupForEntry(entry): var {
        if (!entry)
            return null
        const id = root.lower(entry.id)
        const wmClass = root.lower(entry.startupWMClass)
        for (const group of root.groups) {
            const className = root.lower(group.class)
            if (group.desktopId.length > 0 && root.lower(group.desktopId) === id)
                return group
            if (className === wmClass || className === id)
                return group
        }
        return null
    }

    // Move a window hidden by hide() (on special:hidden) back to the current workspace.
    function unhide(address): void {
        const ws = Number(HyprlandService.activeWorkspaceId)
        if (ws > 0)
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${ws}, window = ${JSON.stringify("address:" + address)} })`)
    }

    // Focus one window of a group. Every window the app has on special:hidden comes
    // back first (macOS un-hides the whole app), then the window is focused; a window
    // on another scratchpad is shown the way the scratchpad keybind does it.
    function focusAddress(address, live): bool {
        if (!HyprlandService.validAddress(address))
            return false
        const specials = live?.specials || ({})
        for (const a of live?.addresses || [])
            if (specials[a] === "hidden")
                root.unhide(a)
        const name = specials[address] || ""
        if (name && name !== "hidden") {
            const special = HyprlandService.workspaces.find(workspace =>
                workspace?.name === "special:" + name)
            if (!special?.active)
                Hyprland.dispatch(`hl.dsp.workspace.toggle_special(${JSON.stringify(name)})`)
        }
        Hyprland.dispatch(`hl.dsp.focus({ window = ${JSON.stringify("address:" + address)} })`)
        return true
    }

    // Focus the most recently used window of an app.
    function focus(group): bool {
        const live = root.byClass(group?.class) || group
        const addresses = live?.addresses || []
        if (addresses.length === 0)
            return false
        return root.focusAddress(addresses[0], live)
    }

    // Hide every window of an app: move them silently to special:hidden.
    // Returns false when the app has no valid windows.
    function hide(group): bool {
        const live = root.byClass(group?.class) || group
        const addresses = (live?.addresses || []).filter(a => HyprlandService.validAddress(a))
        if (addresses.length === 0)
            return false
        for (const address of addresses)
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = "special:hidden", follow = false, window = ${JSON.stringify("address:" + address)} })`)
        return true
    }

    // Hide the focused window's app (Super+H).
    function hideFocused(): bool {
        const cls = String(HyprlandService.focusedToplevel?.lastIpcObject?.class || "")
        return cls.length > 0 && root.hide(root.byClass(cls))
    }

    // Focus the next window of the focused app in MRU order (Super+`). The
    // addresses of a group are already most-recent first, so this walks them.
    // Goes through focusAddress, so a window on a scratchpad is brought back too.
    function cycle(): bool {
        const active = String(HyprlandService.focusedToplevel?.lastIpcObject?.address || "")
        const cls = String(HyprlandService.focusedToplevel?.lastIpcObject?.class || "")
        const group = root.byClass(cls)
        const addresses = group?.addresses || []
        if (addresses.length < 2)
            return false
        const i = addresses.indexOf(active)
        const next = addresses[(i + 1) % addresses.length]
        return root.focusAddress(next, group)
    }
}
