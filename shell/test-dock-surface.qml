// Gesture-logic tests for dock/DockSurface.qml with a synthetic pointer:
// hit mapping, drag-to-reorder, drag-off-to-unpin, menu contents, magnified
// layout symmetry. Offscreen, no real input, no layer surface.
import QtQuick
import Quickshell
import "dock"

ShellRoot {
    id: root
    property var log: []
    property var reorderedIds: null
    property var unpinnedItem: null
    function ok(name, cond, detail) { log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : "")) }
    function app(key, pinned, running) {
        return { kind: "app", key: key, desktopId: key, name: key, icon: key, "class": key, pinned: pinned, running: running,
            windowCount: running ? 1 : 0, minimizedAddresses: [], addresses: running ? ["0x" + key.length] : [],
            windows: running ? [{ address: "0x1", title: "w " + key }] : [], focused: false, launching: false, title: "" }
    }

    Item {
        id: stage
        width: 1000; height: 400
        DockSurface {
            id: s
            anchors.fill: parent
            dockScale: 1
            synthetic: true
            items: [root.app("a", true, true), root.app("b", true, false), root.app("c", true, false), root.app("d", true, false),
                    root.app("u", false, true), { kind: "separator", key: "separator" },
                    { kind: "minimized", key: "min:0x9", address: "0x9", name: "m", icon: "m", running: false, pinned: false, focused: false, launching: false }]
            onReordered: ids => root.reorderedIds = ids
            onUnpinned: item => root.unpinnedItem = item
        }
    }

    Component.onCompleted: {
        const cx = i => s.rest.centers[s.posOf[i]]
        // hit mapping at rest
        ok("itemAt_rest", s.itemAt(cx(0)) === 0 && s.itemAt(cx(3)) === 3 && s.itemAt(5) === -1)
        ok("separator_narrow", s.widths[5] < s.widths[0] / 2, "" + s.widths[5])
        ok("rest_centred", Math.abs((s.rest.centers[0] - s.widths[0] / 2 + s.restTotal / 2) - s.width / 2) < 1e-6)

        // magnified layout: symmetric widening, separator never scales
        s.syntheticX = cx(2); s.syntheticInside = true
        s.ptrX = cx(2); s.amount = 1
        ok("peak_on_hovered", Math.abs(s.layout.scales[2] - DockMetrics.peakScale) < 1e-9)
        ok("separator_not_magnified", s.layout.scales[5] === 1)
        ok("hover_index", s.hoverIndex === 2)
        const total = s.layout.widths.reduce((a, b) => a + b, 0)
        ok("dock_widens", total > s.restTotal + 50, total.toFixed(1) + " vs " + s.restTotal.toFixed(1))
        ok("dock_widens_symmetrically", Math.abs((s.layout.left + total / 2) - s.width / 2) < 1e-6)
        s.syntheticInside = false; s.amount = 0; s.ptrX = NaN

        // drag item 0 to the right of item 2 -> order b,c,a,d,...
        s.dragIndex = 0; s.dragX = cx(2) + 5; s.dragY = s.iconBase - 10
        s.updateDragOrder()
        ok("drag_order", s.order.slice(0, 4).join() === "1,2,0,3", s.order.join())
        ok("drag_keeps_tail", s.order.slice(4).join() === "4,5,6")
        s.dragOffAtRelease = false
        s.commitDrag()
        ok("reordered_signal", root.reorderedIds && root.reorderedIds.join() === "b,c,a,d", JSON.stringify(root.reorderedIds))
        ok("order_reset_after_drop", s.order.join() === "0,1,2,3,4,5,6" && s.dragIndex === -1)

        // drag pinned item far right: clamped inside the pinned region
        s.dragIndex = 0; s.dragX = cx(6); s.dragY = s.iconBase
        s.updateDragOrder()
        ok("drag_clamped_to_pinned", s.order.indexOf(0) === 3, s.order.join())
        s.dragOffAtRelease = false; s.commitDrag()

        // drag off the dock -> unpin
        root.reorderedIds = null
        s.dragIndex = 1; s.dragX = cx(1); s.dragY = s.shelfY - 200
        ok("drag_off_detected", s.dragOff === true)
        s.dragOffAtRelease = s.dragOff
        s.commitDrag()
        ok("unpinned_signal", root.unpinnedItem && root.unpinnedItem.key === "b" && root.reorderedIds === null)

        // unpinned running app cannot be reordered / unpinned by drag-off
        root.unpinnedItem = null; root.reorderedIds = null
        s.dragIndex = 4; s.dragX = cx(0); s.dragY = s.shelfY - 200
        s.updateDragOrder()
        ok("unpinned_drag_keeps_order", s.order.join() === "0,1,2,3,4,5,6")
        s.dragOffAtRelease = true; s.commitDrag()
        ok("unpinned_not_unpinned", root.unpinnedItem === null && root.reorderedIds === null)

        // menus
        const m = s.buildMenu(s.items[0]).map(e => e.label || e.header || "-")
        ok("menu_running_pinned", m.join("|") === "w a|-|Options|Remove from Dock|-|Show All Windows|Quit", m.join("|"))
        const m2 = s.buildMenu(s.items[1]).map(e => e.label || e.header || "-")
        ok("menu_not_running", m2.join("|") === "Open|Options|Remove from Dock", m2.join("|"))
        const m3 = s.buildMenu(s.items[4]).map(e => e.label || e.header || "-")
        ok("menu_unpinned_offers_keep", m3.indexOf("Keep in Dock") >= 0 && m3.indexOf("Quit") >= 0, m3.join("|"))
        const m4 = s.buildMenu(s.items[6]).map(e => e.label)
        ok("menu_minimised", m4.join("|") === "Restore|Close Window")
        s.openMenu(0)
        ok("menu_opens_above_icon", s.menuOpen && s.menuBox.y + s.menuBox.height < s.iconBase - s.tile + 1,
           "y=" + s.menuBox.y + " h=" + s.menuBox.height)
        ok("menu_on_screen", s.menuBox.x >= 0 && s.menuBox.x + s.menuBox.width <= s.width)
        s.closeMenu()
        ok("menu_closes", !s.menuOpen)

        // slide: fully hidden layer is not drawn
        s.slide = 0
        ok("hidden_when_slid_out", s.hit.visible === false)

        console.log("=== test-dock-surface ===")
        for (const l of log) console.log(l)
        const failed = log.filter(l => l.startsWith("FAIL")).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.callLater(function () { Qt.quit() })
    }
}
