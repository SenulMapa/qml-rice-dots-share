import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../core"
import "../services"
import "../components"
import "MissionControlLayout.js" as Layout

/**
 * MissionControlWindow -- the Mission Control overlay for ONE screen
 * (namespace qml-rice:mission-control). One instance per screen; only the
 * instance on the monitor that was focused at open time is visible.
 *
 * Content:
 *   - a dim (ink at 0.45) over the desktop
 *   - a top strip of workspace thumbnails for this monitor, plus "+"
 *   - every mapped window on the monitor's active workspace, animated from
 *     its real rect (progress 0) into its packed slot (progress 1), using
 *     MissionControlLayout.js. The same animation runs back on close.
 *
 * Interaction: hover = outline + title pill; click = focus that window and
 * close; drag a window onto a thumbnail = silent move to that workspace
 * (Hyprland.dispatch, the same call RunningApps uses); click a thumbnail =
 * switch to it; "+" = switch to the first free workspace id; Esc, F3, or a
 * click on empty space = close.
 *
 * Captures use ScreencopyView on the toplevel's wayland handle. Thumbnails of
 * windows on OTHER workspaces are captured the same way; whether Hyprland
 * returns live content for hidden workspaces is not verified here.
 */
PanelWindow {
    id: win

    required property var modelData
    property var owner: null

    screen: modelData
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qml-rice:mission-control"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: win.onMine && win.owner && win.owner.open
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var hmon: HyprlandService.monitorFor(win.screen)
    readonly property bool onMine: win.owner !== null && win.hmon !== null
        && win.hmon !== undefined && win.owner.monitorId === win.hmon.id
    readonly property bool shownNow: win.onMine && win.owner !== null
        && (win.owner.open || win.progress > 0.001)
    visible: win.shownNow

    // 0 = windows at their real rects, 1 = Mission Control slots.
    readonly property real progressTarget: win.onMine && win.owner && win.owner.open ? 1 : 0
    property real progress: win.progressTarget
    Behavior on progress {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

    // ---- geometry (logical px of this screen) ------------------------------
    readonly property int thumbH: Math.round(Math.max(72, Math.min(130, win.height * 0.12)))
    readonly property int thumbW: Math.round(thumbH * win.width / Math.max(1, win.height))
    readonly property int plusW: Math.round(thumbH * 0.5)
    readonly property int stripTop: Math.round(win.height * 0.03)
    readonly property int stripBottom: stripTop + thumbH + 26
    readonly property int gap: 22
    readonly property var area: ({
        x: 48, y: win.stripBottom + 40,
        w: win.width - 96, h: win.height - (win.stripBottom + 40) - 48
    })

    // ---- state rebuilt from Hyprland -----------------------------------------
    property var wins: []      // [{address, pid, title, wl, real}] in reading order
    property var slots: []     // packed slots, parallel to wins
    property var thumbs: []    // [{id, current, plus, wins:[{address, wl, real}]}]
    property string winSig: ""
    property string thumbSig: ""
    property int currentWs: -1
    property int dropWs: -1

    function nextFreeId(): int {
        const count = Number(Config.hyprland.workspaceCount) || 10
        for (let id = 1; id <= count; id++) {
            if (!HyprlandService.workspaceById(id))
                return id
        }
        return -1
    }

    // Mapped, non-hidden toplevels on one workspace, with rects relative to this monitor.
    function collectOn(wsId: int): var {
        const out = []
        const mon = win.hmon
        if (!mon)
            return out
        for (const t of HyprlandService.toplevels) {
            const ipc = t?.lastIpcObject || {}
            if (!ipc.mapped || ipc.hidden)
                continue
            if (Number(ipc.workspace?.id) !== wsId)
                continue
            const at = ipc.at || [0, 0]
            const size = ipc.size || [0, 0]
            if (!(size[0] > 0 && size[1] > 0))
                continue
            out.push({
                address: String(ipc.address || ""),
                pid: Number(ipc.pid || 0),
                title: String(t.title || ipc.title || ipc.class || ""),
                wl: t.wayland ?? null,
                real: { x: at[0] - mon.x, y: at[1] - mon.y, w: size[0], h: size[1] }
            })
        }
        return out
    }

    function refreshWindows(): void {
        const wsId = Number(win.hmon?.activeWorkspace?.id ?? -1)
        win.currentWs = wsId
        const list = wsId > 0 ? win.collectOn(wsId) : []
        const order = Layout.readingOrder(list.map(w => w.real))
        const ordered = order.map(i => list[i])
        const sig = ordered.map(w => w.address + "@" + Math.round(w.real.x) + ","
            + Math.round(w.real.y) + "," + Math.round(w.real.w) + "x" + Math.round(w.real.h)).join("|")
        if (sig !== win.winSig) {
            win.winSig = sig
            win.wins = ordered
        }
        win.slots = Layout.pack(win.wins.map(w => w.real), win.area, win.gap)
    }

    function refreshThumbs(): void {
        const mon = win.hmon
        const list = mon ? HyprlandService.workspacesFor(mon) : []
        const built = []
        for (const ws of list) {
            const ws0 = ws.id
            const wins = win.collectOn(ws0).map(w => ({ address: w.address, wl: w.wl, real: w.real }))
            built.push({ id: ws0, current: ws0 === win.currentWs, plus: false, wins: wins })
        }
        const freeId = win.nextFreeId()
        built.push({ id: freeId, current: false, plus: true, wins: [] })
        const sig = built.map(t => t.id + "[" + t.wins.map(w => w.address + "@"
            + Math.round(w.real.x) + "," + Math.round(w.real.y) + "," + Math.round(w.real.w)
            + "x" + Math.round(w.real.h)).join(",") + "]").join("|")
        if (sig !== win.thumbSig) {
            win.thumbSig = sig
            win.thumbs = built
        }
    }

    function refreshAll(): void {
        win.refreshWindows()
        win.refreshThumbs()
    }

    // Workspace id of the thumbnail under a stage point, or -1.
    function workspaceAt(px: real, py: real): int {
        for (let i = 0; i < thumbRep.count; i++) {
            const t = thumbRep.itemAt(i)
            if (!t)
                continue
            const p = t.mapFromItem(win.stageItem, px, py)
            if (p.x >= 0 && p.y >= 0 && p.x <= t.width && p.y <= t.height)
                return t.wsId
        }
        return -1
    }

    function closeAndFocus(address: string): void {
        const cmd = Layout.focusCmd(address)
        if (cmd)
            Hyprland.dispatch(cmd)
        win.owner.close()
    }

    Connections {
        target: HyprlandService
        function onContextChanged(): void {
            if (win.visible)
                win.refreshAll()
        }
    }

    Connections {
        target: win.owner
        function onOpenChanged(): void {
            if (win.owner.open && win.onMine) {
                win.refreshAll()
                win.stageItem.forceActiveFocus()
            }
        }
    }

    onWidthChanged: win.refreshAll()
    onHeightChanged: win.refreshAll()

    // Settle timer: Hyprland's move event is not in the context list, so
    // refresh a moment after a drop to drop the moved window from the grid.
    Timer {
        id: settle
        interval: 160
        repeat: false
        onTriggered: {
            Hyprland.refreshToplevels()
            win.refreshAll()
        }
    }

    // Background dim and the empty-space close target (below everything else).
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.45)
        opacity: win.progress
    }

    MouseArea {
        anchors.fill: parent
        onClicked: if (win.owner) win.owner.close()
    }

    // The coordinate frame for every drag and drop test.
    Item {
        id: stage
        anchors.fill: parent
        focus: win.visible
        Keys.onEscapePressed: if (win.owner) win.owner.close()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_F3 && win.owner) {
                win.owner.close()
                event.accepted = true
            }
        }
    }
    readonly property Item stageItem: stage

    // ---- workspace strip -----------------------------------------------------
    Row {
        id: strip
        x: Math.round((win.width - width) / 2)
        y: win.stripTop
        spacing: 16
        opacity: win.progress

        Repeater {
            id: thumbRep
            model: win.thumbs

            delegate: Item {
                id: thumb
                required property var modelData
                required property int index
                readonly property bool plus: modelData.plus === true
                readonly property int wsId: modelData.id
                readonly property bool current: modelData.current === true
                readonly property bool dropHit: wsId > 0 && win.dropWs === wsId

                width: thumb.plus ? win.plusW : win.thumbW
                height: win.thumbH

                Squircle {
                    anchors.fill: parent
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.06)
                    borderColor: thumb.dropHit ? Theme.accentFill
                        : (thumb.current ? Theme.t1 : Qt.rgba(1, 1, 1, 0.18))
                    borderWidth: thumb.dropHit || thumb.current ? 2 : 1
                }

                // Live windows of this workspace, scaled from their real rects.
                Item {
                    id: shot
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    visible: !thumb.plus

                    Repeater {
                        model: thumb.plus ? [] : thumb.modelData.wins
                        delegate: ScreencopyView {
                            required property var modelData
                            readonly property real kx: shot.width / Math.max(1, win.width)
                            readonly property real ky: shot.height / Math.max(1, win.height)
                            x: modelData.real.x * kx
                            y: modelData.real.y * ky
                            width: modelData.real.w * kx
                            height: modelData.real.h * ky
                            captureSource: modelData.wl
                            live: win.visible
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.bottom
                    anchors.topMargin: 6
                    text: thumb.plus ? "+" : String(thumb.wsId)
                    font.family: Theme.fontUi
                    font.pixelSize: thumb.plus ? 22 : 12
                    color: thumb.current ? Theme.t1 : Theme.t2
                }

                MouseArea {
                    anchors.fill: parent
                    // "+" carries the first free id; Hyprland creates the workspace on switch.
                    onClicked: {
                        if (thumb.wsId > 0)
                            HyprlandService.activateWorkspace(thumb.wsId)
                        if (win.owner)
                            win.owner.close()
                    }
                }
            }
        }
    }

    // ---- windows -------------------------------------------------------------
    Repeater {
        model: win.wins

        delegate: Item {
            id: tile
            required property var modelData
            required property int index

            readonly property var real: modelData.real
            readonly property var slot: win.slots[index] ?? real
            readonly property real p: win.progress
            property real dragX: 0
            property real dragY: 0
            property bool dragging: false
            readonly property bool hovered: hover.hovered

            x: real.x + (slot.x - real.x) * p + dragX
            y: real.y + (slot.y - real.y) * p + dragY
            width: real.w + (slot.w - real.w) * p
            height: real.h + (slot.h - real.h) * p
            z: tile.dragging ? 10 : (tile.hovered ? 2 : 1)

            Behavior on dragX {
                enabled: !tile.dragging
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            Behavior on dragY {
                enabled: !tile.dragging
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            HoverHandler { id: hover }

            ScreencopyView {
                anchors.fill: parent
                captureSource: tile.modelData.wl
                live: win.visible
            }

            // Hover outline.
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: Theme.t1
                border.width: 2
                radius: 8
                visible: tile.hovered && !tile.dragging
            }

            // Hover title, ink pill under the window.
            Rectangle {
                id: titlePill
                visible: tile.hovered && !tile.dragging && tile.modelData.title !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height + 8
                height: 22
                width: Math.min(titleText.implicitWidth + 20, 320)
                radius: height / 2
                color: Qt.rgba(Theme.ink.r, Theme.ink.g, Theme.ink.b, 0.85)

                Text {
                    id: titleText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, titlePill.width - 20)
                    text: tile.modelData.title
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    color: Theme.t1
                }
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor

                property point pressAt: Qt.point(0, 0)
                property bool moved: false

                onPressed: mouse => {
                    pressAt = ma.mapToItem(win.stageItem, mouse.x, mouse.y)
                    moved = false
                }
                onPositionChanged: mouse => {
                    if (!ma.pressed)
                        return
                    const p = ma.mapToItem(win.stageItem, mouse.x, mouse.y)
                    const dx = p.x - ma.pressAt.x
                    const dy = p.y - ma.pressAt.y
                    if (!ma.moved && Math.hypot(dx, dy) < 8)
                        return
                    ma.moved = true
                    tile.dragging = true
                    tile.dragX = dx
                    tile.dragY = dy
                    win.dropWs = win.workspaceAt(p.x, p.y)
                }
                onReleased: mouse => {
                    if (!ma.moved) {
                        win.closeAndFocus(tile.modelData.address)
                        return
                    }
                    const p = ma.mapToItem(win.stageItem, mouse.x, mouse.y)
                    const target = win.workspaceAt(p.x, p.y)
                    tile.dragging = false
                    tile.dragX = 0
                    tile.dragY = 0
                    win.dropWs = -1
                    if (target > 0 && target !== win.currentWs) {
                        const cmd = Layout.moveCmd(tile.modelData.address, target)
                        if (cmd) {
                            Hyprland.dispatch(cmd)
                            settle.restart()
                        }
                    }
                }
            }
        }
    }
}
