// Ported from impasto's bar/island/controls/Block.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// One block on the control centre grid: position, size, face, and the drag
// that moves it while arranging. Draws nothing itself; the face is already
// a card.
//
// Adaptation only: ControlsService -> DashServices.DashBlocksService;
// Theme -> Desk.DeskTheme. Grid math, drag, resize, snapping and the
// badge/handle chrome are all verbatim.

import QtQuick

import "../../desktop/services" as Desk
import "../services" as DashServices

Item {
    id: root

    required property string modelData

    // Named `board` because a property would shadow the container's
    // `surface` id.
    required property Item board

    signal panelRequested(string panel)
    signal dismissed()

    readonly property string key: root.modelData

    // Null briefly after the row is removed, before the Repeater destroys
    // the delegate.
    readonly property var block: DashServices.DashBlocksService.entryOf(root.key)
    readonly property string blockId: root.block ? root.block.id : ""
    readonly property string size: DashServices.DashBlocksService.sizeOf(root.block)
    readonly property var box: root.block
        ? DashServices.DashBlocksService.geometry(root.block)
        : ({ x: 0, y: 0, width: 0, height: 0 })

    readonly property bool editing: DashServices.DashBlocksService.editing
    readonly property bool held: DashServices.DashBlocksService.dragging === root.key
    readonly property bool selected: DashServices.DashBlocksService.selected === root.key
    readonly property bool hovered: hover.hovered

    width: root.box.width
    height: root.box.height
    visible: root.block !== null

    // Dragging assigns x and y directly, which would break a plain binding,
    // so the grid position is a Binding disabled while held.
    Binding {
        target: root
        property: "x"
        value: root.box.x
        when: !drag.active
        restoreMode: Binding.RestoreBindingOrValue
    }

    Binding {
        target: root
        property: "y"
        value: root.box.y
        when: !drag.active
        restoreMode: Binding.RestoreBindingOrValue
    }

    // Animates the snap to the nearest cell after a drop or resize.
    Behavior on x {
        enabled: !drag.active
        NumberAnimation { duration: Desk.DeskTheme.durationMedium; easing.type: Desk.DeskTheme.easing }
    }

    Behavior on y {
        enabled: !drag.active
        NumberAnimation { duration: Desk.DeskTheme.durationMedium; easing.type: Desk.DeskTheme.easing }
    }

    Behavior on width {
        NumberAnimation { duration: Desk.DeskTheme.durationMedium; easing.type: Desk.DeskTheme.easing }
    }

    Behavior on height {
        NumberAnimation { duration: Desk.DeskTheme.durationMedium; easing.type: Desk.DeskTheme.easing }
    }

    // The held block draws above the others, and the selected one above the
    // rest, so its outline isn't cut by a neighbour.
    z: root.held ? 2 : (root.selected ? 1 : 0)

    // Disabled while arranging so a drag can't also press a button.
    // `enabled` rather than an overlay, which would swallow the drag too.
    BlockFace {
        anchors.fill: parent
        active: root.block !== null
        blockId: root.blockId
        blockKey: root.key
        size: root.size
        enabled: !root.editing
        onPanelRequested: panel => root.panelRequested(panel)
        onDismissed: root.dismissed()
    }

    // ── ARRANGING ───────────────────────────────────────────────────────────
    //
    // Inactive outside editing mode.

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        visible: root.editing
        radius: Desk.DeskTheme.radiusMedium + 3
        color: "transparent"
        border.color: root.held || root.selected ? Desk.DeskTheme.accent : Desk.DeskTheme.hairline
        border.width: root.held || root.selected ? 2 : 1
    }

    // Click to select and open the inspector. Declared before the drag so a
    // press that moves goes to the drag; exclusive so the ground's tap
    // doesn't close it.
    TapHandler {
        enabled: root.editing
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: DashServices.DashBlocksService.selected = root.selected ? "" : root.key
    }

    DragHandler {
        id: drag

        enabled: root.editing && root.block !== null
        target: root
        xAxis.minimum: 0
        xAxis.maximum: Math.max(0, root.board.width - root.width)
        yAxis.minimum: 0
        yAxis.maximum: Math.max(0, root.board.height - root.height)

        onActiveChanged: {
            if (drag.active) {
                DashServices.DashBlocksService.dragging = root.key
                DashServices.DashBlocksService.selected = ""
                return
            }
            DashServices.DashBlocksService.dragging = ""
            DashServices.DashBlocksService.landing = null
            // Dropped on the tray, it is removed; otherwise `place` puts it
            // in the cell under the pointer, or the nearest free one, or
            // back where it was.
            const pointer = root.board.mapFromItem(
                null, drag.centroid.scenePosition.x, drag.centroid.scenePosition.y)
            if (DashServices.DashBlocksService.overTray(pointer.x, pointer.y)) {
                DashServices.DashBlocksService.remove(root.key)
                return
            }
            DashServices.DashBlocksService.place(root.key,
                DashServices.DashBlocksService.cellX(root.x), DashServices.DashBlocksService.cellY(root.y))
        }
    }

    // Highlights the landing cell; none while over the tray.
    function aim(): void {
        if (!drag.active)
            return
        const pointer = root.board.mapFromItem(
            null, drag.centroid.scenePosition.x, drag.centroid.scenePosition.y)
        if (DashServices.DashBlocksService.overTray(pointer.x, pointer.y)) {
            DashServices.DashBlocksService.landing = null
            return
        }
        const spot = DashServices.DashBlocksService.nearestFree(
            DashServices.DashBlocksService.cellX(root.x), DashServices.DashBlocksService.cellY(root.y),
            root.size, root.key)
        DashServices.DashBlocksService.landing = spot
            ? { col: spot.col, row: spot.row, size: root.size } : null
    }

    onXChanged: root.aim()
    onYChanged: root.aim()

    // The wheel steps through the block's sizes, one step per notch and then
    // a pause; touchpads send an event per pixel.
    property real wheelSpent: 0

    WheelHandler {
        enabled: root.editing
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (wheelRest.running)
                return
            root.wheelSpent += event.angleDelta.y
            if (Math.abs(root.wheelSpent) < 120)
                return
            const step = root.wheelSpent < 0 ? 1 : -1
            root.wheelSpent = 0
            DashServices.DashBlocksService.cycleSize(root.key, step)
            wheelRest.restart()
        }
    }

    Timer {
        id: wheelRest
        interval: 250
        onTriggered: root.wheelSpent = 0
    }

    HoverHandler {
        id: hover

        enabled: root.editing
        cursorShape: root.held ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    }

    // ── BADGE AND HANDLE ────────────────────────────────────────────────────
    //
    // Shown on hover and on the selected block. The badge removes the
    // block; the handle resizes it, snapping between the sizes it offers.
    readonly property bool dressed: root.editing && !root.held && (root.hovered || root.selected)

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.leftMargin: -7
        anchors.topMargin: -7
        width: 20
        height: 20
        radius: 10
        color: Desk.DeskTheme.island
        border.color: Desk.DeskTheme.islandBorder
        border.width: 1
        visible: opacity > 0
        opacity: root.dressed ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Desk.DeskTheme.durationFast }
        }

        Rectangle {
            anchors.centerIn: parent
            width: 8
            height: 2
            radius: 1
            color: Desk.DeskTheme.scrimText
        }

        HoverHandler { cursorShape: Qt.PointingHandCursor }

        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: DashServices.DashBlocksService.remove(root.key)
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -7
        anchors.bottomMargin: -7
        width: 20
        height: 20
        radius: 10
        color: Desk.DeskTheme.island
        border.color: resize.active ? Desk.DeskTheme.accent : Desk.DeskTheme.islandBorder
        border.width: resize.active ? 2 : 1
        visible: opacity > 0
        opacity: root.dressed || resize.active ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: Desk.DeskTheme.durationFast }
        }

        Item {
            anchors.centerIn: parent
            width: 8
            height: 8

            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 8
                height: 2
                radius: 1
                color: Desk.DeskTheme.scrimText
            }

            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: 2
                height: 8
                radius: 1
                color: Desk.DeskTheme.scrimText
            }
        }

        HoverHandler { cursorShape: Qt.SizeFDiagCursor }

        // Claims the press before the drag: a drag whose passive grab is
        // overridden by an exclusive one loses the point.
        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
        }

        DragHandler {
            id: resize

            target: null

            onCentroidChanged: {
                if (!resize.active)
                    return
                const pointer = root.board.mapFromItem(null,
                    resize.centroid.scenePosition.x, resize.centroid.scenePosition.y)
                const cols = (pointer.x - root.box.x + Desk.DeskTheme.centreGutter) / Desk.DeskTheme.centreStrideX
                const rows = (pointer.y - root.box.y + Desk.DeskTheme.centreGutter) / Desk.DeskTheme.centreStrideY
                const next = DashServices.DashBlocksService.sizeNearest(root.blockId, cols, rows)
                if (next !== root.size)
                    DashServices.DashBlocksService.setSize(root.key, next)
            }
        }
    }
}
