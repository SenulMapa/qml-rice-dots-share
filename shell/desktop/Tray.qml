// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   T   R   A   Y                                                          │
// │   widget tray · drag modules onto the grid                               │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick

import "services" as DeskServices
import "components"
import "../components"


// The card shown while arranging: every module as its real face at the
// smallest family it offers, which is the face it lands with. Drag one onto
// the grid, or click it to place it on the first free cell, and change its
// shape there; drop a widget on the card to remove it. Every module is offered
// regardless of its current state.
//
// The ghost (the face at full size while dragged) lives on the board rather
// than here, so it can leave the card.
EditTray {
    id: root

    required property Item board

    // The module being dragged out of the card, or empty.
    property string pulling: ""

    // Packed in squares: a 2×2 face is one unit, a 4×2 face two.
    entries: DeskServices.DeskDesktopService.offerable.map(entry => {
        const shape = DeskServices.DeskDesktopService.family(root.smallest(entry.id))
        return { id: entry.id, name: entry.name, cols: shape.cols / 2, rows: shape.rows / 2 }
    })
    unitWidth: DeskServices.DeskDesktopService.sizeFor("2x2").width
    unitHeight: DeskServices.DeskDesktopService.sizeFor("2x2").height
    unitGap: DeskServices.DeskTheme.desktopGutter
    startColumns: 5
    startRows: 2
    factor: 0.75
    homeX: (root.width - root.card.width) / 2
    homeY: root.height - root.card.height - DeskServices.DeskTheme.desktopGutter
    at: DeskServices.DeskDesktopService.galleryAt
    onMoved: (x, y) => DeskServices.DeskDesktopService.galleryAt = { x: x, y: y }
    size: DeskServices.DeskDesktopService.gallerySize
    onResized: (columns, rows) => DeskServices.DeskDesktopService.gallerySize = { columns: columns, rows: rows }
    receiving: DeskServices.DeskDesktopService.dragging !== "" && DeskServices.DeskDesktopService.landing === null

    function smallest(id: string): string {
        return DeskServices.DeskDesktopService.familiesFor(id)[0] ?? "4x2"
    }

    // The card's rect in board coordinates, so a drop can tell whether it
    // landed there. This item fills the board.
    Binding {
        target: DeskServices.DeskDesktopService
        property: "trayBox"
        value: ({
            x: root.card.x, y: root.card.y,
            width: root.card.width, height: root.card.height
        })
    }

    Component.onDestruction: {
        DeskServices.DeskDesktopService.trayBox = null
        DeskServices.DeskDesktopService.landing = null
    }

    // ── PIECE ───────────────────────────────────────────────────────────────

    delegate: Item {
        id: tile

        required property var modelData

        readonly property string moduleId: tile.modelData.id
        readonly property string familyId: root.smallest(tile.moduleId)
        readonly property var box: DeskServices.DeskDesktopService.sizeFor(tile.familyId)
        readonly property real factor: tile.width / tile.box.width
        readonly property bool pulled: root.pulling === tile.moduleId

        x: tile.modelData.x
        y: tile.modelData.y
        width: tile.modelData.width
        height: tile.modelData.height

        // The real face, scaled to the mosaic, on the island's black.
        Item {
            width: tile.box.width
            height: tile.box.height
            scale: tile.factor
            transformOrigin: Item.TopLeft

            Squircle {
                anchors.fill: parent
                radius: DeskServices.DeskTheme.desktopRadius
                color: DeskServices.DeskTheme.island
                borderColor: tile.pulled ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.islandBorder
                borderWidth: (tile.pulled ? 2 : 1) / tile.factor
            }

            Face {
                anchors.fill: parent
                moduleId: tile.moduleId
                family: tile.familyId
                ink: DeskServices.DeskDesktopService.inkFor(null)
                enabled: false
            }
        }

        HoverHandler {
            cursorShape: tile.pulled ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        }

        // Exclusive from the press, so the background's tap handler does not
        // also fire.
        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: DeskServices.DeskDesktopService.add(tile.moduleId)
        }

        DragHandler {
            id: pull

            target: null

            onActiveChanged: {
                if (pull.active) {
                    root.pulling = tile.moduleId
                    DeskServices.DeskDesktopService.selected = ""
                    root.aim(pull.centroid.scenePosition)
                    return
                }
                const spot = DeskServices.DeskDesktopService.landing
                const edge = DeskServices.DeckService.receiving
                const moduleId = root.pulling
                root.pulling = ""
                DeskServices.DeskDesktopService.landing = null
                DeskServices.DeckService.receiving = ""
                if (edge !== "" && moduleId === "notes")
                    DeskServices.DeskDesktopService.addDeck(edge)
                else if (spot)
                    DeskServices.DeskDesktopService.add(moduleId, spot.col, spot.row)
            }

            onCentroidChanged: {
                if (pull.active)
                    root.aim(pull.centroid.scenePosition)
            }
        }
    }

    // ── GHOST ───────────────────────────────────────────────────────────────
    //
    // The dragged face at its final size, following the pointer; the surface
    // draws the target cell under it. Parented to the board so it can leave the
    // card.
    function aim(scene: point): void {
        const pointer = root.board.mapFromItem(null, scene.x, scene.y)
        ghost.x = pointer.x - ghost.width / 2
        ghost.y = pointer.y - ghost.height / 2
        if (DeskServices.DeskDesktopService.overTray(pointer.x, pointer.y)) {
            DeskServices.DeskDesktopService.landing = null
            DeskServices.DeckService.receiving = ""
            return
        }
        // A notes piece against an edge is a deck there, not a square.
        const edge = root.pulling === "notes"
            ? DeskServices.DeckService.edgeAt(pointer.x, pointer.y, root.board.width, root.board.height) : ""
        DeskServices.DeckService.receiving = edge
        if (edge !== "") {
            DeskServices.DeskDesktopService.landing = null
            return
        }
        const spot = DeskServices.DeskDesktopService.nearestFree(
            DeskServices.DeskDesktopService.cellX(ghost.x), DeskServices.DeskDesktopService.cellY(ghost.y), ghost.familyId, "")
        DeskServices.DeskDesktopService.landing = spot
            ? { col: spot.col, row: spot.row, family: ghost.familyId } : null
    }

    Item {
        id: ghost

        readonly property string familyId: root.smallest(root.pulling)
        readonly property var box: DeskServices.DeskDesktopService.sizeFor(ghost.familyId)

        parent: root.board
        z: 10
        visible: root.pulling !== ""
        width: ghost.box.width
        height: ghost.box.height
        opacity: 0.9

        Squircle {
            anchors.fill: parent
            radius: DeskServices.DeskTheme.desktopRadius
            color: DeskServices.DeskTheme.island
            borderColor: DeskServices.DeskTheme.accent
            borderWidth: 2
        }

        Face {
            anchors.fill: parent
            moduleId: root.pulling
            family: ghost.familyId
            ink: DeskServices.DeskDesktopService.inkFor(null)
            enabled: false
        }
    }
}
