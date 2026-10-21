// Unit tests for dock/model.js (pure merge of pins, running apps and
// minimised windows) and a smoke test of dock/DockModel.qml fed fake data.
import QtQuick
import Quickshell
import "dock"
import "dock/model.js" as M

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) { log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : "")) }

    // Desktop entries installed on the fake machine (note: no discord/slack).
    readonly property var entries: ({
        "brave-browser": { id: "brave-browser", name: "Brave", icon: "brave-browser", startupWMClass: "brave-browser" },
        "kitty": { id: "kitty", name: "kitty", icon: "kitty", startupWMClass: "kitty" },
        "code-oss": { id: "code-oss", name: "Code - OSS", icon: "code-oss", startupWMClass: "Code - OSS" },
        "spotify": { id: "spotify", name: "Spotify", icon: "spotify", startupWMClass: "spotify" },
        "thunar": { id: "thunar", name: "Thunar", icon: "thunar", startupWMClass: "thunar" },
        "org.gnome.Calculator": { id: "org.gnome.Calculator", name: "Calculator", icon: "calc", startupWMClass: "org.gnome.Calculator" },
        "mpv": { id: "mpv", name: "mpv", icon: "mpv", startupWMClass: "mpv" }
    })
    function lookup(id) {
        const k = String(id).toLowerCase().replace(/\.desktop$/, "")
        for (const key in entries) if (key.toLowerCase() === k) return entries[key]
        return null
    }
    function forClass(cls) {
        const c = String(cls).toLowerCase()
        for (const key in entries) {
            const e = entries[key]
            if (e.startupWMClass.toLowerCase() === c || e.id.toLowerCase() === c) return e
        }
        return null
    }
    function cl(addr, cls, ws, fh, title) {
        return { address: addr, "class": cls, title: title === undefined ? cls + " window" : title,
                 workspaceName: ws || "1", focusHistoryID: fh === undefined ? 5 : fh, mapped: true }
    }
    function build(clients, extra) {
        return M.build(Object.assign({ pins: M.DEFAULT_PIN_TOKENS, clients: clients,
            lookup: lookup, forClass: forClass, prevOrder: [] }, extra || {}))
    }
    function ids(r) { return r.items.map(i => i.key).join(",") }

    Component.onCompleted: {
        // 1. default pins keep only installed apps, in order, aliases resolved
        let r = build([])
        ok("default_pins_installed_only", ids(r) === "brave-browser,kitty,code-oss,spotify,thunar", ids(r))
        ok("pins_flagged", r.items.every(i => i.pinned && !i.running && i.windowCount === 0))
        ok("no_separator_without_minimised", !r.items.some(i => i.kind === "separator"))
        ok("pin_names_and_icons", r.items[0].name === "Brave" && r.items[2].icon === "code-oss")

        // 2. running pinned app is marked, unpinned running appended
        r = build([cl("0x1", "brave-browser", "1", 0), cl("0x2", "mpv", "2", 3), cl("0x3", "Code - OSS", "1", 2)])
        ok("running_pinned_marked", r.items[0].running && r.items[0].windowCount === 1 && r.items[2].running)
        ok("unpinned_running_after_pins", ids(r) === "brave-browser,kitty,code-oss,spotify,thunar,mpv", ids(r))
        ok("unpinned_flag", r.items[5].pinned === false && r.items[5].running)
        ok("startupwmclass_match", r.items[2].addresses[0] === "0x3")

        // 3. window grouping and MRU order within an app
        r = build([cl("0x10", "kitty", "1", 4), cl("0x11", "kitty", "2", 1), cl("0x12", "kitty", "1", 7)])
        ok("group_by_class", r.items[1].windowCount === 3)
        ok("addresses_mru_first", r.items[1].addresses.join() === "0x11,0x10,0x12", r.items[1].addresses.join())
        ok("windows_have_titles", r.items[1].windows.length === 3 && r.items[1].windows[0].address === "0x11")

        // 4. focus
        r = build([cl("0x10", "kitty", "1", 0), cl("0x20", "thunar", "1", 1)], { activeAddress: "0x10" })
        ok("focused_flag", r.items[1].focused && !r.items[4].focused)

        // 5. minimised windows -> separator + restorable tiles; app still "running"
        r = build([cl("0x30", "spotify", "special:minimized", 2), cl("0x31", "thunar", "special:minimized", 3),
                   cl("0x32", "thunar", "1", 1)])
        const sep = r.items.findIndex(i => i.kind === "separator")
        ok("separator_before_minimised", sep === 5 && r.items.length === 8, ids(r))
        ok("minimised_items", r.items[6].kind === "minimized" && r.items[6].address === "0x30"
            && r.items[7].address === "0x31" && r.items[7].appKey === "thunar")
        ok("minimised_app_still_running", r.items[3].running && r.items[3].windowCount === 0
            && r.items[3].minimizedAddresses[0] === "0x30")
        ok("minimised_not_in_focus_targets", r.items[4].addresses.join() === "0x32" && r.items[4].minimizedAddresses.join() === "0x31")

        // 6. shell windows and unmapped windows are ignored
        r = build([cl("0x40", "quickshell", "1", 0), { address: "0x41", "class": "mpv", title: "x", workspaceName: "1", mapped: false }])
        ok("shell_and_unmapped_ignored", ids(r) === "brave-browser,kitty,code-oss,spotify,thunar")

        // 7. stable order of unpinned running apps across rebuilds
        let a = build([cl("0x50", "mpv", "1", 1), cl("0x51", "org.gnome.Calculator", "1", 0)])
        ok("unpinned_first_seen_order", ids(a).endsWith("mpv,org.gnome.calculator") || ids(a).endsWith("org.gnome.calculator,mpv"))
        const firstOrder = a.order.slice()
        const b = build([cl("0x50", "mpv", "1", 0), cl("0x51", "org.gnome.Calculator", "1", 1)], { prevOrder: a.order })
        ok("order_stable_when_focus_changes", b.order.join() === firstOrder.join())
        const c = build([cl("0x51", "org.gnome.Calculator", "1", 0)], { prevOrder: a.order })
        ok("closed_app_leaves", !ids(c).includes("mpv"))

        // 8. unknown class without desktop entry still gets a tile
        r = build([cl("0x60", "weird-app", "1", 0)])
        const w = r.items[r.items.length - 1]
        ok("unknown_class_tile", w.key === "class:weird-app" && w.name === "weird-app" && w.desktopId === "" && w.running)

        // 9. custom pins (desktop ids), unresolved/duplicate dropped
        r = M.build({ pins: ["mpv", "nonexistent", "mpv", "kitty"], clients: [], lookup: lookup, forClass: forClass })
        ok("custom_pins", ids(r) === "mpv,kitty", ids(r))

        // 10. launching flag only while not yet running
        r = build([cl("0x70", "kitty", "1", 0)], { launching: { kitty: 1, spotify: 1 } })
        ok("launching_until_window_maps", r.items[1].launching === false && r.items[3].launching === true)

        // 11. dispatch strings
        ok("focus_cmd", M.focusCmd("0xabc") === 'hl.dsp.focus({ window = "address:0xabc" })', M.focusCmd("0xabc"))
        ok("restore_cmd", M.restoreCmd("0xabc", 3) === 'hl.dsp.window.move({ workspace = 3, window = "address:0xabc" })', M.restoreCmd("0xabc", 3))
        ok("close_cmd", M.closeCmd("0xabc") === 'hl.dsp.window.close({ window = "address:0xabc" })')
        ok("bad_address_rejected", M.focusCmd('0x1" }); os.exit() --') === "" && M.restoreCmd("zzz", 1) === "" && M.restoreCmd("0x1", 0) === "")

        // 12. cycling
        ok("cycle_next", M.nextAddress(["0x2", "0x1", "0x3"], "0x1") === "0x2")
        ok("cycle_wraps", M.nextAddress(["0x2", "0x1", "0x3"], "0x3") === "0x1")
        ok("cycle_unfocused_starts_first", M.nextAddress(["0x2", "0x1"], "0x9") === "0x1")

        // 13. DockModel.qml binding smoke test with fake feeds
        ok("DockModel_items", dm.items.length > 0 && dm.items.some(i => i.key === "mpv" && i.running),
           JSON.stringify(dm.items.map(i => i.key)))
        ok("DockModel_pinnedIds_match", dm.pinnedIds.every(id => !!root.lookup(id)))

        console.log("=== test-dock-model ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.startsWith("FAIL")).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.callLater(function () { Qt.quit() })   // deferred: quitting inside onCompleted has no receiver yet
    }

    DockModel {
        id: dm
        testLookup: root.lookup
        testForClass: root.forClass
        testClients: [root.cl("0x1", "mpv", "1", 0)]
    }
}
