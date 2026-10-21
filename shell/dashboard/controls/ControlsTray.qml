// Ported from impasto's bar/island/controls/ControlsTray.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// The card of blocks, shown while the grid is being arranged, so a block
// can be dragged from it onto the grid within one window.
//
// Every block at the smallest size it offers, which is the size it is added
// at, packed in the grid's own cells; it grows on the grid.
//
// Adaptation only: ControlsService -> DashServices.DashBlocksService;
// Theme -> Desk.DeskTheme; EditTray is desktop/components/EditTray.qml,
// the exact same shared mosaic-card component this shell's own desktop
// widget tray (desktop/Tray.qml) already uses -- not a re-port, upstream's
// EditTray IS this file (see EditTray.qml's own header). Upstream's tray
// lived on the bar's surface, outside the panel, so a block could cross
// from the bar onto the island in one drag; this shell's control centre has
// no such separate surface (it is a page inside the island, not the bar),
// so `host` is this file's own dashboard page root instead -- the ghost
// still parents to it and the drag/drop math against `board` is unchanged.
import QtQuick

import "../../desktop/services" as Desk
import "../../desktop/components" as DeskComponents
import "../services" as DashServices
import "../../components"

DeskComponents.EditTray {
    id: root

    // Parent for the drag ghost (the dashboard page's own root), so it can
    // cross the grid.
    required property Item host

    // Where the card starts: under the top row, handed in by the panel.
    property real homeTop: 0

    // The block being dragged out of the card, or empty.
    property string pulling: ""

    entries: DashServices.DashBlocksService.catalogue.map(entry => {
        const shape = DashServices.DashBlocksService.parse(root.smallest(entry.id))
        return { id: entry.id, name: entry.name, cols: shape.cols, rows: shape.rows }
    })
    unitWidth: Desk.DeskTheme.centreCellWidth
    unitHeight: Desk.DeskTheme.centreCellHeight
    unitGap: Desk.DeskTheme.centreGutter
    // A block is drawn denser than a desktop widget, so it is shown larger
    // than the desktop's three quarters: at nine tenths, six across and
    // five down, the card opens at the desktop card's size.
    startColumns: 6
    startRows: 5
    factor: 0.9
    homeX: (root.width - root.card.width) / 2
    homeY: root.homeTop
    at: DashServices.DashBlocksService.galleryAt
    onMoved: (x, y) => DashServices.DashBlocksService.galleryAt = { x: x, y: y }
    size: DashServices.DashBlocksService.gallerySize
    onResized: (columns, rows) => DashServices.DashBlocksService.gallerySize = { columns: columns, rows: rows }
    receiving: DashServices.DashBlocksService.dragging !== "" && DashServices.DashBlocksService.landing === null

    function smallest(id: string): string {
        return DashServices.DashBlocksService.sizesFor(id)[0] ?? "2x2"
    }

    // Published as an item rather than a rectangle so the service maps
    // points into it on demand; the card moves, and the panel may still be
    // animating when it is made.
    Binding {
        target: DashServices.DashBlocksService
        property: "tray"
        value: root.card
    }

    Component.onDestruction: {
        DashServices.DashBlocksService.tray = null
        DashServices.DashBlocksService.landing = null
    }

    // ── PIECE ───────────────────────────────────────────────────────────────

    delegate: Item {
        id: tile

        required property var modelData

        readonly property string blockId: tile.modelData.id
        readonly property string size: root.smallest(tile.blockId)
        readonly property var box: DashServices.DashBlocksService.pixels(tile.size)
        readonly property real factor: tile.width / tile.box.width
        readonly property bool pulled: root.pulling === tile.blockId

        x: tile.modelData.x
        y: tile.modelData.y
        width: tile.modelData.width
        height: tile.modelData.height

        Item {
            width: tile.box.width
            height: tile.box.height
            scale: tile.factor
            transformOrigin: Item.TopLeft

            Squircle {
                anchors.fill: parent
                radius: Desk.DeskTheme.radiusMedium
                color: "transparent"
                borderColor: tile.pulled ? Desk.DeskTheme.accent : "transparent"
                borderWidth: 2 / tile.factor
            }

            BlockFace {
                anchors.fill: parent
                blockId: tile.blockId
                size: tile.size
                enabled: false
            }
        }

        HoverHandler {
            cursorShape: tile.pulled ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        }

        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: DashServices.DashBlocksService.add(tile.blockId)
        }

        DragHandler {
            id: pull

            target: null

            onActiveChanged: {
                if (pull.active) {
                    root.pulling = tile.blockId
                    root.aim(pull.centroid.scenePosition)
                    return
                }
                const spot = DashServices.DashBlocksService.landing
                const blockId = root.pulling
                root.pulling = ""
                DashServices.DashBlocksService.landing = null
                if (spot)
                    DashServices.DashBlocksService.add(blockId, spot.col, spot.row)
            }

            onCentroidChanged: {
                if (pull.active)
                    root.aim(pull.centroid.scenePosition)
            }
        }
    }

    // ── GHOST ───────────────────────────────────────────────────────────────
    //
    // The dragged block at its landing size, over the grid, with the
    // landing cell highlighted on the grid. Hidden while the pointer is
    // over the card.
    function aim(scene: point): void {
        const board = DashServices.DashBlocksService.board
        const at = root.host.mapFromItem(null, scene.x, scene.y)
        ghost.x = at.x - ghost.width / 2
        ghost.y = at.y - ghost.height / 2
        if (!board)
            return
        const pointer = board.mapFromItem(null, scene.x, scene.y)
        if (DashServices.DashBlocksService.overTray(pointer.x, pointer.y)) {
            DashServices.DashBlocksService.landing = null
            return
        }
        const corner = board.mapFromItem(root.host, ghost.x, ghost.y)
        const spot = DashServices.DashBlocksService.nearestFree(
            DashServices.DashBlocksService.cellX(corner.x), DashServices.DashBlocksService.cellY(corner.y), ghost.size, "")
        DashServices.DashBlocksService.landing = spot
            ? { col: spot.col, row: spot.row, size: ghost.size } : null
    }

    Item {
        id: ghost

        readonly property string size: root.smallest(root.pulling)
        readonly property var box: DashServices.DashBlocksService.pixels(ghost.size)

        parent: root.host
        z: 100
        visible: root.pulling !== ""
        width: ghost.box.width
        height: ghost.box.height
        opacity: 0.9

        Squircle {
            anchors.fill: parent
            anchors.margins: -6
            radius: Desk.DeskTheme.radiusLarge
            color: Desk.DeskTheme.island
            borderColor: Desk.DeskTheme.accent
            borderWidth: 2
        }

        BlockFace {
            anchors.fill: parent
            blockId: root.pulling
            size: ghost.size
            enabled: false
        }
    }
}
