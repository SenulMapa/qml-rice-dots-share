import QtQuick
import Quickshell
import "../core"
import "../services"
import "../components"
import "magnify.js" as Mag

/**
 * DockSurface -- everything the dock draws and every gesture on it, with no
 * window and no compositor calls, so render-dock.qml can host it offscreen.
 * Dock.qml wraps it in the layer surface and turns its signals into actions.
 *
 * Geometry (all px, DockMetrics values x dockScale):
 *   - the shelf is a fixed-height Tahoe liquid-glass plate (TahoeGlass);
 *     icons sit on iconBase inside it and grow UPWARD when magnified, the
 *     plate widens to fit;
 *   - the whole dock layer slides down by (1 - slide) for autohide.
 * The glass body is a light white tint over the compositor blur (layer rule
 * on qml-rice:dock). It never paints a dark base.
 */
Item {
    id: root

    // ---- inputs ----
    property var items: []
    property real dockScale: Theme.u(1) / 44
    property real slide: 1                  // 0 hidden .. 1 shown
    property bool animateAppear: false
    property bool synthetic: false          // harness drives the pointer
    property real syntheticX: NaN           // surface coordinates
    property bool syntheticInside: false

    // ---- outputs ----
    signal activated(var item, int button)  // Qt.LeftButton / Qt.MiddleButton
    signal menuAction(string action, var item, var arg)
    signal reordered(var ids)
    signal unpinned(var item)
    signal interacting(bool active)         // pointer on dock / menu open / dragging

    readonly property alias hit: hitArea
    readonly property alias menuBox: menuBox
    readonly property alias scrim: scrim
    readonly property bool menuOpen: menuBox.open
    readonly property bool dragging: dragIndex >= 0

    // ---- scaled metrics ----
    readonly property real tile: DockMetrics.tileSize * dockScale
    readonly property real gap: DockMetrics.slotGap * dockScale
    readonly property real pad: DockMetrics.shelfPadding * dockScale
    readonly property real shelfH: 2 * pad + tile       // the running dot sits in the bottom padding
    readonly property real shelfY: height - DockMetrics.bottomMargin * dockScale - shelfH
    readonly property real iconBase: shelfY + pad + tile
    readonly property real hiddenDrop: shelfH + DockMetrics.bottomMargin * dockScale + 6 * dockScale

    // ---- layout ----
    property var order: items.map((it, i) => i)         // visual order of item indices
    onItemsChanged: if (dragIndex < 0) order = items.map((it, i) => i)
    readonly property var widths: order.map(i => {
        const it = items[i]
        return it && it.kind === "separator"
            ? (DockMetrics.separatorWidth + 2 * DockMetrics.separatorMargin) * dockScale
            : tile + gap
    })
    readonly property var flags: order.map(i => items[i] && items[i].kind !== "separator")
    readonly property real restTotal: widths.reduce((a, b) => a + b, 0)
    readonly property var rest: Mag.restLayout(widths, (width - restTotal) / 2)
    readonly property var posOf: {
        const p = new Array(items.length)
        for (let k = 0; k < order.length; ++k) p[order[k]] = k
        return p
    }
    readonly property var magSpec: ({ peakScale: DockMetrics.peakScale,
        radiusPx: DockMetrics.radiusTiles * (tile + gap), falloff: DockMetrics.falloff })
    readonly property var layout: Mag.magnify(ptrX, rest.centers, widths, magSpec, flags, amount)

    // ---- pointer state ----
    property real ptrRaw: NaN               // latest pointer x (surface coords)
    property real ptrX: NaN                 // smoothed
    property real ptrV: 0
    property real amount: 0                 // magnification ramp 0..1
    property real amountV: 0
    readonly property bool inside: synthetic ? syntheticInside : hitArea.containsMouse
    readonly property real rawX: synthetic ? syntheticX : ptrRaw
    readonly property bool wantMagnify: inside && !dragging
    property real frozenX: NaN              // pointer position kept while a menu is open

    onWantMagnifyChanged: if (wantMagnify && amount < 0.02) { ptrX = rawX; ptrV = 0 }
    onRawXChanged: if (!menuOpen && wantMagnify && isNaN(ptrX)) ptrX = rawX

    readonly property real targetX: menuOpen ? frozenX : (inside ? rawX : ptrX)
    readonly property real targetAmount: (wantMagnify || menuOpen) ? 1 : 0
    readonly property bool needsFrame: (isFinite(targetX) && Math.abs(ptrX - targetX) > 0.05)
        || Math.abs(ptrV) > 0.5 || Math.abs(amount - targetAmount) > 0.001 || Math.abs(amountV) > 0.001

    FrameAnimation {
        running: root.needsFrame
        onTriggered: {
            const dt = Math.min(frameTime, 0.05)
            if (isFinite(root.targetX)) {
                if (isNaN(root.ptrX)) root.ptrX = root.targetX
                const r = Mag.smoothDamp(root.ptrX, root.targetX, root.ptrV, DockMetrics.pointerOmega, dt)
                root.ptrX = r[0]; root.ptrV = r[1]
                // Snap once settled so the tail never keeps the layout "live".
                if (Math.abs(root.ptrX - root.targetX) <= 0.05 && Math.abs(root.ptrV) <= 0.5) {
                    root.ptrX = root.targetX; root.ptrV = 0
                }
            }
            const a = Mag.smoothDamp(root.amount, root.targetAmount, root.amountV, DockMetrics.rampOmega, dt)
            root.amount = Math.max(0, Math.min(1, a[0])); root.amountV = a[1]
            if (Math.abs(root.amount - root.targetAmount) <= 0.001 && Math.abs(root.amountV) <= 0.001) {
                root.amount = root.targetAmount; root.amountV = 0
            }
        }
    }

    onInsideChanged: root.interacting(inside || menuOpen || dragging)

    // ---- hover / press / drag state ----
    property int pressIndex: -1
    property int pressButton: 0
    property point pressPoint: Qt.point(0, 0)
    property int dragIndex: -1
    property real dragX: 0
    property real dragY: 0
    readonly property bool dragOff: dragging && dragY < shelfY - DockMetrics.unpinDistance * dockScale

    function itemAt(x): int {
        if (items.length === 0) return -1
        const l = layout
        if (x < l.left || x > l.left + l.widths.reduce((a, b) => a + b, 0)) return -1
        return order[Mag.slotIndexAt(x, l.centers, l.widths)]
    }
    readonly property int hoverIndex: (inside && !dragging && !menuOpen && !isNaN(rawX))
        ? itemAt(rawX) : -1

    function pinnedCount(): int {
        let n = 0
        for (const it of items) if (it.kind === "app" && it.pinned) ++n
        return n
    }

    function updateDragOrder(): void {
        const it = items[dragIndex]
        const base = items.map((x, i) => i)
        if (!it || !it.pinned) { order = base; return }
        const rem = base.filter(i => i !== dragIndex)
        // Target slot = the slot of the ORIGINAL (identity-order) layout under
        // the pointer, so the gap opens exactly where the icon will land.
        const lay = Mag.restLayout(items.map(x => x.kind === "separator"
            ? (DockMetrics.separatorWidth + 2 * DockMetrics.separatorMargin) * dockScale : tile + gap),
            (width - restTotal) / 2)
        let k = Mag.slotIndexAt(dragX, lay.centers, items.map(x => x.kind === "separator" ? 1 : tile + gap))
        k = Math.min(k, pinnedCount() - 1)
        rem.splice(Math.max(0, k), 0, dragIndex)
        order = rem
    }

    function commitDrag(): void {
        const idx = dragIndex
        const it = items[idx]
        dragIndex = -1
        interacting(inside || menuOpen)
        if (!it) { order = items.map((x, i) => i); return }
        if (dragOffAtRelease && it.pinned) {
            poofAt(dragX, dragY)
            unpinned(it)
        } else if (it.pinned) {
            const ids = order.filter(i => items[i].kind === "app" && items[i].pinned).map(i => items[i].desktopId)
            reordered(ids)
        }
        order = items.map((x, i) => i)
    }
    property bool dragOffAtRelease: false

    // ---- layers ----
    Item {
        id: dockLayer
        anchors.fill: parent
        y: (1 - root.slide) * root.hiddenDrop
        visible: root.slide > 0.002 && root.items.length > 0

        // Shelf: macOS 26 Tahoe liquid glass (components/TahoeGlass.qml). A light
        // white body over the compositor blur, a specular rim lit from above
        // and a soft drop shadow. Shape + shadow margin come from TahoeGlass.
        TahoeGlass {
            id: shelf
            x: root.layout.left - root.pad
            y: root.shelfY
            width: root.layout.widths.reduce((a, b) => a + b, 0) + 2 * root.pad
            height: root.shelfH
            radius: DockMetrics.shelfRadius * root.dockScale
            tintAlpha: DockMetrics.glassTintAlpha
            rimTop: DockMetrics.glassRimTop
            rimSide: DockMetrics.glassRimSide
            innerGlow: DockMetrics.glassInnerGlow
            shadowAlpha: DockMetrics.glassShadowAlpha
            shadowBlur: DockMetrics.glassShadowBlur * root.dockScale
            shadowY: DockMetrics.glassShadowY * root.dockScale
        }

        // Separator line.
        Repeater {
            model: root.items.length
            Rectangle {
                required property int index
                readonly property int pos: root.posOf[index]
                visible: root.items[index] && root.items[index].kind === "separator"
                width: Math.max(1, DockMetrics.separatorWidth * root.dockScale)
                height: root.shelfH - 2 * DockMetrics.separatorInset * root.dockScale
                x: root.layout.centers[pos] - width / 2
                y: root.shelfY + DockMetrics.separatorInset * root.dockScale
                color: Qt.rgba(1, 1, 1, 0.18)
            }
        }

        Repeater {
            model: ScriptModel { values: root.items; objectProp: "key" }
            DockItem {
                id: di
                required property var modelData
                required property int index
                readonly property int pos: root.posOf[index] ?? index
                readonly property bool isDragged: root.dragIndex === index
                visible: modelData.kind !== "separator"
                model: modelData
                baseSize: root.tile
                dockScale: root.dockScale
                appear: root.animateAppear
                size: root.tile * (root.layout.scales[pos] ?? 1)
                hovered: root.hoverIndex === index
                pressed: root.pressIndex === index && root.pressButton === Qt.LeftButton && !root.dragging
                dragging: isDragged
                z: isDragged ? 10 : 0
                x: isDragged ? root.dragX - width / 2 : (root.layout.centers[pos] ?? 0) - size / 2
                y: isDragged ? root.dragY - height / 2 : root.iconBase - size
            }
        }

        // "Remove" tag while an icon is dragged off the dock.
        MacMaterial {
            visible: root.dragOff
            readonly property real w: removeText.implicitWidth + 24 * root.dockScale
            width: w; height: 28 * root.dockScale; radius: 7 * root.dockScale
            shadowYOffset: 3 * root.dockScale; shadowOpacity: 0.35
            x: root.dragX - width / 2
            y: root.dragY - root.tile - 14 * root.dockScale - height
            z: 11
            Text {
                id: removeText
                anchors.centerIn: parent
                text: "Remove"
                color: "white"
                font.family: "system-ui"
                font.pixelSize: DockMetrics.labelFontPx * root.dockScale
            }
        }

        // Hover label: macOS dark-mode tooltip (dark translucent rounded rect, light text, hairline).
        MacMaterial {
            id: label
            property int shownIndex: -1
            readonly property bool want: root.hoverIndex >= 0 && root.items[root.hoverIndex] !== undefined
                && root.items[root.hoverIndex].kind !== "separator"
            onWantChanged: if (want) shownIndex = root.hoverIndex
            Connections { target: root; function onHoverIndexChanged() { if (label.want) label.shownIndex = root.hoverIndex } }
            readonly property var it: shownIndex >= 0 ? root.items[shownIndex] : null
            readonly property int pos: shownIndex >= 0 ? (root.posOf[shownIndex] ?? 0) : 0
            readonly property real iconSize: root.tile * (root.layout.scales[pos] ?? 1)
            width: labelText.implicitWidth + 24 * root.dockScale
            height: 26 * root.dockScale
            radius: 7 * root.dockScale
            shadowYOffset: 3 * root.dockScale
            shadowOpacity: 0.32
            shadowSpread: 12
            x: Math.max(4, Math.min(root.width - width - 4, (root.layout.centers[pos] ?? 0) - width / 2))
            y: root.iconBase - iconSize - (it && it.launching ? root.tile * DockMetrics.bounceHeight : 0)
               - DockMetrics.labelGap * root.dockScale - height
            opacity: want ? 1 : 0
            visible: opacity > 0.01 && it !== null
            Behavior on opacity { NumberAnimation { duration: label.want ? 90 : 140; easing.type: Easing.OutQuad } }
            z: 12
            Text {
                id: labelText
                anchors.centerIn: parent
                text: label.it ? label.it.name : ""
                color: Qt.rgba(1, 1, 1, 0.96)
                font.family: "system-ui"
                font.pixelSize: DockMetrics.labelFontPx * root.dockScale
                font.weight: Font.Medium
            }
        }

        // Input: one area over the shelf and the space the magnified icons rise into.
        Item {
            id: hitArea
            property alias containsMouse: ma.containsMouse
            x: shelf.x
            width: shelf.width
            y: root.iconBase - root.tile * DockMetrics.peakScale - 6 * root.dockScale
            height: root.height - y
            visible: root.items.length > 0 && root.slide > 0.05 && !root.synthetic

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onEntered: root.ptrRaw = hitArea.x + mouseX
                onPositionChanged: mouse => {
                    root.ptrRaw = hitArea.x + mouse.x
                    if (root.pressIndex >= 0 && root.pressButton === Qt.LeftButton) {
                        const px = hitArea.x + mouse.x, py = hitArea.y + mouse.y
                        const dx = px - root.pressPoint.x, dy = py - root.pressPoint.y
                        const it = root.items[root.pressIndex]
                        if (!root.dragging && it && it.kind === "app"
                                && Math.hypot(dx, dy) > DockMetrics.reorderStartPx * root.dockScale) {
                            root.dragIndex = root.pressIndex
                            root.interacting(true)
                        }
                        if (root.dragging) {
                            root.dragX = px; root.dragY = py
                            root.updateDragOrder()
                        }
                    }
                }
                onPressed: mouse => {
                    const px = hitArea.x + mouse.x
                    const i = root.itemAt(px)
                    root.pressIndex = i
                    root.pressButton = mouse.button
                    root.pressPoint = Qt.point(px, hitArea.y + mouse.y)
                    if (i >= 0 && root.items[i].kind !== "separator" && mouse.button === Qt.RightButton) {
                        root.openMenu(i)
                        root.pressIndex = -1
                    }
                }
                onReleased: mouse => {
                    const i = root.pressIndex, b = root.pressButton
                    root.pressIndex = -1
                    if (root.dragging) {
                        root.dragOffAtRelease = root.dragOff
                        root.commitDrag()
                        return
                    }
                    if (i >= 0 && root.itemAt(hitArea.x + mouse.x) === i
                            && root.items[i].kind !== "separator"
                            && (b === Qt.LeftButton || b === Qt.MiddleButton))
                        root.activated(root.items[i], b)
                }
                onExited: root.interacting(root.menuOpen || root.dragging)
            }
        }
    }

    // ---- context menu ----
    property int menuIndex: -1
    function openMenu(i): void {
        const it = items[i]
        if (!it) return
        frozenX = isNaN(ptrX) ? rawX : ptrX
        menuIndex = i
        menuBox.entries = buildMenu(it)
        const pos = posOf[i] ?? 0
        const cx = layout.centers[pos]
        const iconTop = iconBase - tile * (layout.scales[pos] ?? 1)
        menuBox.x = Math.max(8, Math.min(width - menuBox.width - 8, cx - menuBox.width / 2))
        menuBox.y = iconTop - 10 * dockScale - menuBox.height
        menuBox.open = true
        interacting(true)
    }
    function closeMenu(): void {
        menuBox.open = false
        menuIndex = -1
        interacting(inside || dragging)
    }
    function buildMenu(it): var {
        const m = []
        if (it.kind === "minimized") {
            m.push({ label: "Restore", action: "restore" })
            m.push({ label: "Close Window", action: "closeWindow" })
            return m
        }
        const wins = (it.windows || []).slice(0, 8)
        for (const w of wins)
            m.push({ label: w.title && w.title.length > 0 ? w.title : it.name, action: "focusWindow", arg: w.address })
        for (const a of it.minimizedAddresses || [])
            m.push({ label: "Restore minimised window", action: "restore", arg: a })
        if (m.length > 0) m.push({ sep: true })
        if (!it.running) m.push({ label: "Open", action: "open" })
        m.push({ header: "Options" })
        m.push({ label: it.pinned ? "Remove from Dock" : "Keep in Dock", action: it.pinned ? "unpin" : "pin", indent: true,
                 enabled: it.desktopId.length > 0 })
        if (it.running) {
            m.push({ sep: true })
            if (it.windowCount > 0) m.push({ label: "Show All Windows", action: "showAll" })
            m.push({ label: "Quit", action: "quit" })
        }
        return m
    }

    // Catches clicks outside the menu so it closes like a native one.
    Item {
        id: scrim
        width: root.menuOpen ? root.width : 0
        height: root.menuOpen ? root.height : 0
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: root.closeMenu()
        }
    }

    MacMaterial {
        id: menuBox
        property bool open: false
        property var entries: []
        readonly property real rowH: 24 * root.dockScale
        readonly property real fontPx: 13 * root.dockScale
        width: 240 * root.dockScale
        height: entries.reduce((h, e) => h + (e.sep ? 11 * root.dockScale : rowH), 0) + 10 * root.dockScale
        visible: open
        opacity: open ? 1 : 0
        radius: 10 * root.dockScale
        fill: Qt.rgba(0.16, 0.16, 0.17, 0.74)
        z: 20
        Column {
            x: 5 * root.dockScale; y: 5 * root.dockScale
            width: parent.width - 10 * root.dockScale
            Repeater {
                model: menuBox.entries
                Item {
                    id: row
                    required property var modelData
                    width: parent.width
                    height: modelData.sep ? 11 * root.dockScale : menuBox.rowH
                    readonly property bool actionable: !modelData.sep && !modelData.header && modelData.enabled !== false
                    Rectangle {
                        visible: row.modelData.sep === true
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8 * root.dockScale; width: parent.width - 16 * root.dockScale; height: 1
                        color: Qt.rgba(1, 1, 1, 0.12)
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 5 * root.dockScale
                        visible: row.actionable && rowMouse.containsMouse
                        color: "#0A84FF"
                    }
                    Text {
                        visible: row.modelData.sep !== true
                        anchors.verticalCenter: parent.verticalCenter
                        x: (row.modelData.indent ? 22 : 10) * root.dockScale
                        width: parent.width - x - 10 * root.dockScale
                        elide: Text.ElideRight
                        text: row.modelData.header ? row.modelData.header : (row.modelData.label ?? "")
                        font.family: "system-ui"
                        font.pixelSize: menuBox.fontPx
                        font.weight: row.modelData.header ? Font.DemiBold : Font.Normal
                        color: row.modelData.header || row.modelData.enabled === false ? Qt.rgba(1, 1, 1, 0.45)
                            : Qt.rgba(1, 1, 1, rowMouse.containsMouse ? 1 : 0.92)
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: row.actionable
                        onClicked: {
                            const it = root.items[root.menuIndex]
                            const act = row.modelData.action, arg = row.modelData.arg
                            root.closeMenu()
                            if (it) root.menuAction(act, it, arg)
                        }
                    }
                }
            }
        }
    }

    // ---- poof (unpin) ----
    Component {
        id: poofComponent
        Item {
            id: poof
            property real t: 0
            width: 1; height: 1
            NumberAnimation on t { from: 0; to: 1; duration: DockMetrics.poofSeconds * 1000; easing.type: Easing.OutCubic
                onFinished: poof.destroy() }
            Repeater {
                model: 7
                Rectangle {
                    required property int index
                    readonly property real ang: index * 2.4 + 0.5
                    readonly property real r: root.tile * (0.12 + 0.34 * poof.t) * (0.7 + (index % 3) * 0.25)
                    width: root.tile * (0.45 + 0.5 * poof.t); height: width; radius: width / 2
                    x: Math.cos(ang) * r - width / 2
                    y: Math.sin(ang) * r - height / 2 - poof.t * root.tile * 0.25
                    color: Qt.rgba(0.92, 0.92, 0.94, 1)
                    opacity: 0.85 * (1 - poof.t)
                }
            }
        }
    }
    function poofAt(x, y): void {
        poofComponent.createObject(root, { x: x, y: y, z: 30 })
    }
}
