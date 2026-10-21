// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   D E C K                                                                │
// │   notes on the screen edges · tabs that peek and drag                    │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

import "../services" as DeskServices
import "../components"


// Notes docked on the screen edges. At rest each is a thin strip of colour;
// hovering slides the tabs out with their titles, the tab under the pointer
// peeks the full note beside it, and a click opens the note in the island.
//
// While the desktop is being arranged the tabs stay out: drag a tab along its
// edge to reorder, to another edge to move it, onto the grid to make it a
// widget, or onto the tray to remove it. Clicking a tab opens the deck's
// inspector.
//
// A full-screen surface with a computed input mask (DeckService), like the
// dock, so it shares the desktop's origin and grid cells line up. It moves to
// the overlay layer while arranging: the desktop is raised to `top` then, and
// its full-screen mask would otherwise take every press meant for a tab. Never
// takes the keyboard.
PanelWindow {
    id: root

    readonly property bool editing: DeskServices.DeskDesktopService.editing

    // Published for the desktop's focus grab, so a press on a tab while
    // arranging does not end the mode.
    Component.onCompleted: DeskServices.DeckService.surface = root
    Component.onDestruction: {
        if (DeskServices.DeckService.surface === root)
            DeskServices.DeckService.surface = null
    }

    // Reset any press in progress when the mode changes; a region left expanded
    // would swallow every click.
    onEditingChanged: {
        DeskServices.DeckService.held = ""
        DeskServices.DeckService.dragging = ""
        DeskServices.DeckService.sliding = ""
    }

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    WlrLayershell.namespace: "impasto-deck"
    WlrLayershell.layer: root.editing ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Full screen and inset to the same board as the desktop, so grid cells
    // match.
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "transparent"

    // Hidden with no decks, under a fullscreen window, or under any window when
    // decks only show on an empty workspace. Always shown while arranging.
    visible: (root.editing || !DeskServices.DeckService.away)
        && (DeskServices.DeckService.count > 0 || DeskServices.DeckService.receiving !== "" || root.editing)

    // ── REVEAL ──────────────────────────────────────────────────────────────
    //
    // How far the tabs are out, from 0 (strips) to 1 (tabs). Fully out while
    // arranging.
    readonly property bool out: root.editing || DeskServices.DeckService.revealed
        || DeskServices.DeckService.peeked !== "" || DeskServices.DeckService.receiving !== ""

    property real reveal: root.out ? 1 : 0

    Behavior on reveal {
        NumberAnimation { duration: DeskServices.DeskTheme.durationMedium; easing.type: DeskServices.DeskTheme.easing }
    }

    readonly property real depth: DeskServices.DeckService.sliver
        + (DeskServices.DeckService.tabDepth - DeskServices.DeckService.sliver) * root.reveal

    // The peeking note, if any.
    readonly property var peekedNote: DeskServices.DeckService.dragging === "" && !root.menu
        ? DeskServices.NotesService.entry(DeskServices.DeckService.peeked) : null

    // Where a note's tab peeks from, or null for a note on no edge.
    function boxFor(key: string): var {
        for (const deck of DeskServices.DeckService.decks) {
            const index = deck.notes.findIndex(note => note.key === key)
            if (index >= 0)
                return DeskServices.DeckService.peekBox(deck.edge, index,
                    root.startOf(deck.edge, deck.notes.length, deck.along), board.width, board.height)
        }
        return null
    }

    readonly property var peekAt: root.boxFor(DeskServices.DeckService.peeked)

    // Where a deck starts along its edge, from the fraction on its row.
    function startOf(edge: string, count: int, along: real): real {
        return DeskServices.DeckService.startOf(edge, count, along, board.width, board.height)
    }

    // Retract after a delay, so moving from a tab to its peek is not leaving.
    readonly property Timer retract: Timer {
        interval: 320
        onTriggered: {
            DeskServices.DeckService.revealed = false
            DeskServices.DeckService.peeked = ""
        }
    }

    // ── CONTEXT MENU ────────────────────────────────────────────────────────
    //
    // Right-click menu on a tab at rest: open the note, or arrange the deck.
    // While it is open the mask covers the screen, so a click elsewhere closes
    // it.
    property var menu: null

    // ── INPUT MASK ──────────────────────────────────────────────────────────
    //
    // Only the tabs and the peek take input. The mask grows to the whole
    // surface as soon as a tab or grip is pressed, not when the drag starts:
    // the compositor re-checks the region on every motion, and the drag
    // threshold is enough to leave a 26 px tab and lose the press. Also the
    // whole surface while a menu is open.
    readonly property bool whole: DeskServices.DeckService.held !== "" || DeskServices.DeckService.dragging !== ""
        || DeskServices.DeckService.sliding !== "" || root.menu !== null

    // Empty while the desktop is dragging a widget, so a note dragged over a
    // tab does not hand the pointer to this surface. The desktop resolves the
    // drop edge itself.
    readonly property bool deaf: DeskServices.DeskDesktopService.dragging !== ""

    mask: Region {
        x: 0
        y: 0
        width: root.whole && !root.deaf ? root.width : 0
        height: root.whole && !root.deaf ? root.height : 0
        regions: root.whole || root.deaf ? [] : root.cutouts.concat(root.peekAt ? [peekRegion] : [])
    }

    readonly property var cutouts: {
        const list = []
        for (let index = 0; index < strips.count; index++) {
            const part = strips.objectAt(index)
            if (part)
                list.push(part)
        }
        return list
    }

    Instantiator {
        id: strips

        model: DeskServices.DeckService.decks

        delegate: Region {
            required property var modelData

            readonly property real start: root.startOf(modelData.edge, modelData.notes.length, modelData.along)
            readonly property var box: DeskServices.DeckService.stripBox(
                modelData.edge, modelData.notes.length, start, board.width, board.height)

            // While arranging, the strip also covers the grip before the first
            // tab.
            readonly property real reach: root.editing ? DeskServices.DeckService.grip + 8 : 0

            x: board.x + (modelData.edge === "right" ? board.width - root.depth
                : (modelData.edge === "bottom" ? box.x - reach : 0))
            y: board.y + (modelData.edge === "bottom" ? board.height - root.depth : box.y - reach)
            width: modelData.edge === "bottom" ? box.width + reach : root.depth
            height: modelData.edge === "bottom" ? root.depth : box.height + reach
        }
    }

    Region {
        id: peekRegion

        x: root.peekAt ? board.x + root.peekAt.x - 6 : 0
        y: root.peekAt ? board.y + root.peekAt.y - 6 : 0
        width: root.peekAt ? root.peekAt.width + 12 : 0
        height: root.peekAt ? root.peekAt.height + 12 : 0
    }

    // Input only arrives inside the mask, so one handler over the surface
    // covers exactly the decks.
    HoverHandler {
        id: hover

        onHoveredChanged: {
            if (hover.hovered) {
                root.retract.stop()
                DeskServices.DeckService.revealed = true
                return
            }
            root.retract.restart()
        }
    }

    // Closes an open menu on any click outside it. A MouseArea, because the
    // click must be consumed.
    MouseArea {
        anchors.fill: parent
        enabled: root.menu !== null
        acceptedButtons: Qt.AllButtons
        onPressed: root.menu = null
    }

    // ── TABS ────────────────────────────────────────────────────────────────

    Item {
        id: board

        anchors.fill: parent
        anchors.topMargin: DeskServices.DeskDesktopService.insets.top
        anchors.leftMargin: DeskServices.DeskDesktopService.insets.left
        anchors.rightMargin: DeskServices.DeskDesktopService.insets.right
        anchors.bottomMargin: DeskServices.DeskDesktopService.insets.bottom

        // Where the dragged tab would land: an edge and a position along it, or
        // empty over the grid or the tray.
        property string dropEdge: ""
        property int dropIndex: -1

        // Keyed by deck (and the tabs by note key) rather than by row: a
        // Repeater given a new array rebuilds every delegate, and the rows are
        // a new array on every write, which would destroy the grip mid-drag.
        Repeater {
            model: DeskServices.DeskDesktopService.deckKeys

            Item {
                id: deck

                required property string modelData

                readonly property string deckKey: deck.modelData
                readonly property var row: DeskServices.DeskDesktopService.entryOf(deck.deckKey)
                readonly property string edge: deck.row && deck.row.edge ? deck.row.edge : "right"
                readonly property real along: DeskServices.DeskDesktopService.alongOf(deck.row)

                // Reassigned only when the set changes, so delegates are not
                // rebuilt.
                readonly property var wanted: DeskServices.DeskDesktopService.deckNotes(deck.row)
                property var noteKeys: []

                function syncNotes(): void {
                    const next = deck.wanted
                    if (next.length === deck.noteKeys.length
                            && next.every((key, index) => key === deck.noteKeys[index]))
                        return
                    deck.noteKeys = next
                }

                onWantedChanged: deck.syncNotes()
                Component.onCompleted: deck.syncNotes()

                readonly property int count: deck.noteKeys.length
                readonly property real start: root.startOf(deck.edge, deck.count, deck.along)
                readonly property bool selected: DeskServices.DeskDesktopService.selected === deck.deckKey
                readonly property bool receiving: board.dropEdge === deck.edge
                    || DeskServices.DeckService.receiving === deck.edge

                anchors.fill: parent

                // ── GRIP ────────────────────────────────────────────────
                //
                // While arranging, the grip before the first tab slides the
                // whole deck along its edge; tabs are dragged one by one. The
                // inspector closes when the drag starts.
                Rectangle {
                    id: grip

                    readonly property var box: DeskServices.DeckService.gripBox(
                        deck.edge, deck.start, board.width, board.height)

                    x: grip.box.x
                    y: grip.box.y
                    width: DeskServices.DeckService.grip
                    height: DeskServices.DeckService.grip
                    radius: width / 2
                    color: DeskServices.DeskTheme.island
                    border.color: slide.active ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.islandBorder
                    border.width: slide.active ? 2 : 1
                    visible: opacity > 0
                    opacity: root.editing ? 1 : 0
                    z: 2

                    Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }

                    Text {
                        anchors.centerIn: parent
                        text: deck.edge === "bottom" ? "󰡏" : "󰡎"
                        font.family: DeskServices.DeskTheme.fontMono
                        font.pixelSize: 12
                        color: DeskServices.DeskTheme.scrimText
                    }

                    HoverHandler {
                        cursorShape: deck.edge === "bottom" ? Qt.SizeHorCursor : Qt.SizeVerCursor
                    }

                    // Exclusive from the press, so the tab's handlers
                    // underneath never see the drag.
                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                    }

                    // Grows the region on press, before any drag. Also released
                    // on destruction: a grip destroyed under the pointer never
                    // reports its release, and a region left grown swallows
                    // every click.
                    PointHandler {
                        id: gripHold

                        acceptedButtons: Qt.LeftButton
                        onActiveChanged: {
                            if (gripHold.active)
                                DeskServices.DeckService.held = deck.deckKey
                            else if (DeskServices.DeckService.held === deck.deckKey)
                                DeskServices.DeckService.held = ""
                        }
                    }

                    Component.onDestruction: {
                        if (DeskServices.DeckService.held === deck.deckKey)
                            DeskServices.DeckService.held = ""
                        if (DeskServices.DeckService.sliding === deck.deckKey)
                            DeskServices.DeckService.sliding = ""
                    }

                    DragHandler {
                        id: slide

                        enabled: root.editing
                        target: null

                        onActiveChanged: {
                            if (slide.active) {
                                DeskServices.DeskDesktopService.selected = ""
                                DeskServices.DeckService.sliding = deck.deckKey
                                return
                            }
                            if (DeskServices.DeckService.sliding === deck.deckKey)
                                DeskServices.DeckService.sliding = ""
                        }

                        onCentroidChanged: {
                            if (!slide.active)
                                return
                            const point = board.mapFromItem(null,
                                slide.centroid.scenePosition.x, slide.centroid.scenePosition.y)
                            const start = (deck.edge === "bottom" ? point.x : point.y)
                                + DeskServices.DeckService.grip / 2 + 4
                            DeskServices.DeskDesktopService.setDeckAlong(deck.deckKey, DeskServices.DeckService.alongAt(
                                deck.edge, deck.count, start, board.width, board.height))
                        }
                    }
                }

                Repeater {
                    model: deck.noteKeys

                    Item {
                        id: tab

                        required property string modelData
                        required property int index

                        readonly property string noteKey: tab.modelData
                        readonly property var note: DeskServices.NotesService.entry(tab.noteKey)
                        readonly property color paper: DeskServices.NotesService.paperOf(tab.note ? tab.note.tint : "yellow")
                        readonly property bool held: DeskServices.DeckService.dragging === tab.noteKey
                        readonly property bool peeking: DeskServices.DeckService.peeked === tab.noteKey

                        // Its own slot, or one along while the dragged tab is
                        // dropped before it on this edge.
                        readonly property int shown: {
                            if (DeskServices.DeckService.dragging === "" || tab.held || board.dropEdge !== deck.edge)
                                return tab.index
                            const from = deck.noteKeys.indexOf(DeskServices.DeckService.dragging)
                            let at = tab.index
                            if (from >= 0 && from < tab.index)
                                at -= 1
                            if (board.dropIndex <= at)
                                at += 1
                            return at
                        }

                        readonly property var box: DeskServices.DeckService.tabBox(
                            deck.edge, tab.shown, deck.start, root.depth, board.width, board.height)

                        x: tab.box.x
                        y: tab.box.y
                        width: tab.box.width
                        height: tab.box.height
                        opacity: tab.held ? 0.3 : 1
                        z: tab.peeking ? 1 : 0

                        Behavior on x {
                            enabled: DeskServices.DeckService.dragging !== ""
                            NumberAnimation { duration: DeskServices.DeskTheme.durationFast; easing.type: DeskServices.DeskTheme.easing }
                        }
                        Behavior on y {
                            enabled: DeskServices.DeckService.dragging !== ""
                            NumberAnimation { duration: DeskServices.DeskTheme.durationFast; easing.type: DeskServices.DeskTheme.easing }
                        }

                        // Rounded on the screen side, square against the edge.
                        Rectangle {
                            anchors.fill: parent
                            color: tab.paper
                            topLeftRadius: deck.edge === "left" ? 0 : DeskServices.DeskTheme.radiusSmall
                            bottomLeftRadius: deck.edge === "left" || deck.edge === "bottom" ? 0 : DeskServices.DeskTheme.radiusSmall
                            topRightRadius: deck.edge === "right" ? 0 : DeskServices.DeskTheme.radiusSmall
                            bottomRightRadius: deck.edge === "right" || deck.edge === "bottom" ? 0 : DeskServices.DeskTheme.radiusSmall
                            border.color: DeskServices.DeskTheme.accent
                            border.width: root.editing && deck.selected ? 2 : 0
                        }

                        // The title along the tab, once there is room to read
                        // it.
                        Text {
                            anchors.centerIn: parent
                            width: DeskServices.DeckService.tabLength - 16
                            rotation: deck.edge === "right" ? 90 : (deck.edge === "left" ? -90 : 0)
                            text: tab.note ? DeskServices.NotesService.titleOf(tab.note).toUpperCase() : ""
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            font.family: DeskServices.DeskTheme.fontFamily
                            font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1
                            color: DeskServices.DeskTheme.paperInk
                            opacity: root.reveal
                        }

                        HoverHandler {
                            cursorShape: root.editing
                                ? (tab.held ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                                : Qt.PointingHandCursor
                            onHoveredChanged: {
                                if (hovered && !root.editing) {
                                    root.retract.stop()
                                    DeskServices.DeckService.peeked = tab.noteKey
                                }
                            }
                        }

                        // At rest a press opens the note; while arranging it
                        // selects the deck. Exclusive from the press; the drag
                        // can still take over.
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: {
                                if (root.editing)
                                    DeskServices.DeskDesktopService.selected = deck.selected ? "" : deck.deckKey
                                else
                                    root.openNote(tab.noteKey)
                            }
                        }

                        TapHandler {
                            enabled: !root.editing
                            acceptedButtons: Qt.RightButton
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: eventPoint => {
                                const point = board.mapFromItem(null,
                                    eventPoint.scenePosition.x, eventPoint.scenePosition.y)
                                root.menu = { note: tab.noteKey, deck: deck.deckKey, x: point.x, y: point.y }
                            }
                        }

                        // Grows the region on press. Must be declared after the
                        // tap handlers, or it never becomes active. Released on
                        // destruction, as for the grip.
                        PointHandler {
                            id: tabHold

                            acceptedButtons: Qt.LeftButton
                            onActiveChanged: {
                                if (tabHold.active)
                                    DeskServices.DeckService.held = tab.noteKey
                                else if (DeskServices.DeckService.held === tab.noteKey)
                                    DeskServices.DeckService.held = ""
                            }
                        }

                        Component.onDestruction: {
                            if (DeskServices.DeckService.held === tab.noteKey)
                                DeskServices.DeckService.held = ""
                            if (DeskServices.DeckService.dragging === tab.noteKey)
                                DeskServices.DeckService.dragging = ""
                        }

                        DragHandler {
                            id: pull

                            enabled: root.editing
                            target: null

                            onActiveChanged: {
                                if (pull.active) {
                                    DeskServices.DeckService.dragging = tab.noteKey
                                    DeskServices.DeckService.peeked = ""
                                    DeskServices.DeskDesktopService.selected = ""
                                    root.aim(pull.centroid.scenePosition)
                                    return
                                }
                                root.drop(tab.noteKey, pull.centroid.scenePosition)
                            }

                            onCentroidChanged: {
                                if (pull.active)
                                    root.aim(pull.centroid.scenePosition)
                            }
                        }
                    }
                }

                // Highlights the edge while something is dragged over it.
                Rectangle {
                    x: deck.edge === "right" ? board.width - 3 : 0
                    y: deck.edge === "bottom" ? board.height - 3 : 0
                    width: deck.edge === "bottom" ? board.width : 3
                    height: deck.edge === "bottom" ? 3 : board.height
                    color: DeskServices.DeskTheme.accent
                    opacity: deck.receiving ? 1 : 0
                    visible: opacity > 0

                    Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }
                }
            }
        }

        // Edges with no deck yet, lit while something is held against them.
        Repeater {
            model: ["left", "right", "bottom"].filter(
                edge => !DeskServices.DeckService.decks.some(deck => deck.edge === edge))

            Rectangle {
                required property string modelData

                x: modelData === "right" ? board.width - 3 : 0
                y: modelData === "bottom" ? board.height - 3 : 0
                width: modelData === "bottom" ? board.width : 3
                height: modelData === "bottom" ? 3 : board.height
                color: DeskServices.DeskTheme.accent
                opacity: DeskServices.DeckService.receiving === modelData || board.dropEdge === modelData ? 1 : 0
                visible: opacity > 0

                Behavior on opacity { NumberAnimation { duration: DeskServices.DeskTheme.durationFast } }
            }
        }
    }

    // ── PEEK ────────────────────────────────────────────────────────────────
    //
    // The hovered note, slid out beside its tab. Shadowed rather than boxed.
    Item {
        id: peek

        parent: board

        readonly property bool showing: root.peekedNote !== null && !root.editing

        // Which note is shown and where, held through the fade-out: bound
        // directly to the hovered tab, they would reset as the pointer leaves
        // and the paper would fade out from the board's corner. Only taken when
        // there is a tab, and by key rather than as an object, since an object
        // goes stale when the note is edited and `peekedNote` is null while a
        // menu is open or a tab is held. The box is computed for the key rather
        // than read off a sibling binding that may lag.
        property string key: ""
        property var box: null

        readonly property string live: DeskServices.DeckService.peeked

        onLiveChanged: {
            if (peek.live !== "") {
                peek.key = peek.live
                peek.box = root.boxFor(peek.live)
            }
        }

        x: peek.box ? peek.box.x : 0
        y: peek.box ? peek.box.y : 0
        width: DeskServices.DeckService.peekWidth
        height: DeskServices.DeckService.peekHeight
        visible: opacity > 0
        opacity: peek.showing ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: DeskServices.DeskTheme.durationFast; easing.type: DeskServices.DeskTheme.easing }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 1
            shadowOpacity: 0.5
            shadowVerticalOffset: 3
            shadowColor: DeskServices.DeskTheme.island
        }

        Sticky {
            anchors.fill: parent
            note: DeskServices.NotesService.entry(peek.key)
            padding: 14
            titleSize: DeskServices.DeskTheme.fontSizeRegular
            bodySize: 17
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: {
                if (hovered)
                    root.retract.stop()
            }
        }

        TapHandler {
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: root.openNote(DeskServices.DeckService.peeked)
        }
    }

    // ── DRAGGED TAB ─────────────────────────────────────────────────────────
    //
    // The dragged tab, drawn as a small square of its paper under the pointer.
    Item {
        id: ghost

        parent: board

        readonly property var note: DeskServices.NotesService.entry(DeskServices.DeckService.dragging)

        z: 10
        visible: DeskServices.DeckService.dragging !== ""
        width: 72
        height: 72
        opacity: 0.94

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowBlur: 1
            shadowOpacity: 0.5
            shadowVerticalOffset: 3
            shadowColor: DeskServices.DeskTheme.island
        }

        Sticky {
            anchors.fill: parent
            note: ghost.note
            padding: 8
            titleSize: DeskServices.DeskTheme.fontSizeLabel
            bodySize: 11
            showAge: false
        }
    }

    // ── MENU ────────────────────────────────────────────────────────────────

    Loader {
        id: menuLoader

        parent: board
        active: root.menu !== null
        x: root.menu ? Math.max(DeskServices.DeskTheme.desktopGutter, Math.min(board.width - DeskServices.DeskTheme.desktopGutter - width, root.menu.x)) : 0
        y: root.menu ? Math.max(DeskServices.DeskTheme.desktopGutter, Math.min(board.height - DeskServices.DeskTheme.desktopGutter - height, root.menu.y)) : 0
        z: 20

        sourceComponent: PopMenu {
            rows: [
                { id: "open", label: "Open", icon: "󰏫", warn: false },
                { id: "edit", label: "Edit", icon: "󰆾", warn: false }
            ]
            onChosen: id => {
                const menu = root.menu
                root.menu = null
                if (!menu)
                    return
                if (id === "open")
                    root.openNote(menu.note)
                else if (id === "edit") {
                    DeskServices.DeskDesktopService.edit(true)
                    DeskServices.DeskDesktopService.selected = menu.deck
                }
            }
        }
    }

    // While dragging: the edge and position under the pointer, or the grid
    // cell, lit by the desktop's landing mark.
    function aim(scene: point): void {
        const point = board.mapFromItem(null, scene.x, scene.y)
        ghost.x = point.x - ghost.width / 2
        ghost.y = point.y - ghost.height / 2
        if (DeskServices.DeskDesktopService.overTray(point.x, point.y)) {
            board.dropEdge = ""
            board.dropIndex = -1
            DeskServices.DeskDesktopService.landing = null
            return
        }
        const edge = DeskServices.DeckService.edgeAt(point.x, point.y, board.width, board.height)
        if (edge !== "") {
            const deck = DeskServices.DeckService.decks.find(deck => deck.edge === edge)
            board.dropEdge = edge
            board.dropIndex = deck
                ? DeskServices.DeckService.indexAt(edge, point.x, point.y, deck.notes.length,
                    root.startOf(deck.edge, deck.notes.length, deck.along))
                : 0
            DeskServices.DeskDesktopService.landing = null
            return
        }
        board.dropEdge = ""
        board.dropIndex = -1
        const size = DeskServices.DeskDesktopService.sizeFor("2x2")
        const spot = DeskServices.DeskDesktopService.nearestFree(
            DeskServices.DeskDesktopService.cellX(point.x - size.width / 2),
            DeskServices.DeskDesktopService.cellY(point.y - size.height / 2), "2x2", "")
        DeskServices.DeskDesktopService.landing = spot ? { col: spot.col, row: spot.row, family: "2x2" } : null
    }

    // Dropped on an edge, it takes its place there; on the desktop, the nearest
    // free grid cell; on the tray, it is removed. With no free cell it stays
    // where it was.
    function drop(key: string, scene: point): void {
        const point = board.mapFromItem(null, scene.x, scene.y)
        const edge = board.dropEdge
        const index = board.dropIndex
        DeskServices.DeckService.dragging = ""
        DeskServices.DeckService.held = ""
        board.dropEdge = ""
        board.dropIndex = -1
        DeskServices.DeskDesktopService.landing = null
        if (DeskServices.DeskDesktopService.overTray(point.x, point.y)) {
            DeskServices.DeskDesktopService.removeNote(key)
            return
        }
        if (edge !== "") {
            DeskServices.DeskDesktopService.placeNote(key, edge, index)
            return
        }
        const size = DeskServices.DeskDesktopService.sizeFor("2x2")
        DeskServices.DeskDesktopService.noteToGrid(key,
            DeskServices.DeskDesktopService.cellX(point.x - size.width / 2),
            DeskServices.DeskDesktopService.cellY(point.y - size.height / 2))
    }

    function openNote(key: string): void {
        DeskServices.DeckService.peeked = ""
        DeskServices.DeckService.revealed = false
        DeskServices.NotesService.open(key)
        DeskServices.ModuleService.requestPanel("notes")
    }
}
