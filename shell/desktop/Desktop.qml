// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   D   E   S   K   T   O   P                                              │
// │   the layer under the windows · widgets on the wallpaper                 │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

import "services" as DeskServices
import "components"
import "." as Desktop
import "../services"
import "../components"

// The layer between the wallpaper and the windows: no exclusive zone, and on
// the bottom layer so any window covers it.
//
// ── ARRANGING ───────────────────────────────────────────────────────────────
//
// Arranging raises the surface to the top layer and takes the whole screen for
// input, so widgets can be moved even with windows open. A card holds every
// module; drag a widget to move it, pull its corner to resize it, click it
// for its inspector.
//
// Arranging holds the keyboard, on demand and under a focus grab as the bar
// holds it, and ends with Escape, a right-click or a click on any other
// surface. The right-click menu is a surface of its own, so opening it never
// raises the widgets.
PanelWindow {
    id: root

    readonly property bool editing: DeskServices.DeskDesktopService.editing

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    // Namespace for layer rules, e.g. `layerrule = blur, impasto-desktop`. Not
    // set by default.
    WlrLayershell.namespace: "impasto-desktop"

    // Raised above the windows while arranging, and only then.
    WlrLayershell.layer: root.editing ? WlrLayer.Top : WlrLayer.Bottom

    // While arranging. The grab keeps the keyboard here while the pointer is
    // elsewhere, and a click on any surface but this one and the edges' clears
    // it, which ends the mode; the compositor hands the keyboard back.
    WlrLayershell.keyboardFocus: root.editing
        ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Arming delay: when arranging is entered from a bind or `desktop
    // arrange` IPC rather than from a right-click on the desk itself, the
    // pointer/keyboard still belongs to whatever window was focused, so the
    // grab is reported cleared on the very next event and the mode ended
    // before a single frame of it was drawn (the reported symptom: "widgets
    // don't work" -- `desktop arrange` answered ON and `desktop status`
    // answered OFF immediately after). Arm the grab a beat after the mode
    // opens so that first clear is not treated as the user dismissing it.
    property bool grabArmed: false

    Timer {
        id: grabArming
        interval: 300
        onTriggered: root.grabArmed = true
    }

    onEditingChanged: {
        root.grabArmed = false
        if (root.editing)
            grabArming.restart()
        else
            grabArming.stop()
        root.raised = false
        root.synced = false
    }

    HyprlandFocusGrab {
        active: root.editing
        windows: DeskServices.DeckService.surface ? [root, DeskServices.DeckService.surface] : [root]
        onCleared: {
            if (root.grabArmed)
                DeskServices.DeskDesktopService.edit(false)
        }
    }

    // Whether the desk has been drawn on `top` since arranging began. The
    // backdrop waits for it: shown before, it covers the widgets for as long
    // as the desk takes to draw the card.
    property bool raised: false
    property bool synced: false



    // A frame synchronised after the change carries the new layer; one
    // already rendering when it happened does not.
    Connections {
        target: root.editing && !root.raised ? surface.Window.window : null

        function onAfterSynchronizing(): void {
            root.synced = true
        }

        function onFrameSwapped(): void {
            if (root.synced)
                root.raised = true
        }
    }

    // The whole screen, ignoring exclusive zones, so a widget dragged into the
    // bar's area stays on this surface; the compositor sends away a pointer
    // that leaves its surface, and the drag would drop. The board inside is
    // inset by what the bar and the dock reserve (`DeskServices.DeskDesktopService.insets`).
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "transparent"

    readonly property var menu: DeskServices.DeskDesktopService.menu

    // ── INPUT MASK ──────────────────────────────────────────────────────────
    //
    // The whole screen: a right-click anywhere opens the desktop menu. A left
    // click on the background only closes a menu.
    mask: Region {
        width: root.width
        height: root.height
    }

    // This mask is exactly why DitherWallpaper's own cursor tracking goes
    // dark whenever the desktop is present: Wayland hands the pointer to the
    // topmost surface holding input, never to the Background-layer surface
    // underneath. A passive HoverHandler over the whole window (not the
    // inset `surface` FocusScope -- the mask, and therefore the dead zone,
    // covers the full window) republishes the pointer through
    // PointerService so DitherWallpaper can drive its reveal spotlight from
    // it. Passive: it must never claim the point or block the TapHandlers
    // and widgets that already handle it.
    Item {
        anchors.fill: parent

        HoverHandler {
            id: pointerPublisher
            target: null

            onHoveredChanged: {
                if (pointerPublisher.hovered) {
                    PointerService.screenName = root.screen ? root.screen.name : ""
                    PointerService.hovered = true
                } else if (PointerService.screenName === (root.screen ? root.screen.name : "")) {
                    // Multi-monitor safety: only clear if we're still the
                    // screen PointerService thinks owns the pointer -- a
                    // stale un-hover from a screen the pointer already left
                    // must not clobber the new owner's report.
                    PointerService.hovered = false
                }
            }

            onPointChanged: {
                if (!pointerPublisher.hovered)
                    return
                PointerService.screenName = root.screen ? root.screen.name : ""
                PointerService.x = pointerPublisher.point.position.x
                PointerService.y = pointerPublisher.point.position.y
                PointerService.hovered = true
            }
        }
    }

    // ── BOARD ───────────────────────────────────────────────────────────────

    // Not `id: board`: the widgets take a `board` property, and an id with the
    // same name as a property in scope resolves to the property, handing each
    // widget itself. A scope, so Escape reaches it and a caption field inside
    // keeps its own.
    FocusScope {
        id: surface

        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: DeskServices.DeskDesktopService.edit(false)
        anchors.topMargin: DeskServices.DeskDesktopService.insets.top
        anchors.leftMargin: DeskServices.DeskDesktopService.insets.left
        anchors.rightMargin: DeskServices.DeskDesktopService.insets.right
        anchors.bottomMargin: DeskServices.DeskDesktopService.insets.bottom

        // The grid's available area, published because the service works in
        // cells and placing from the tray needs the same answer.
        Binding {
            target: DeskServices.DeskDesktopService
            property: "boardWidth"
            value: surface.width
        }

        Binding {
            target: DeskServices.DeskDesktopService
            property: "boardHeight"
            value: surface.height
        }

        // Anywhere on the background: leaves arranging, and a left click
        // dismisses the inspector. Declared first, so widget handlers take
        // presses before these. At rest, the right button opens the desktop
        // menu.
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: eventPoint => {
                if (root.editing) {
                    DeskServices.DeskDesktopService.edit(false)
                    return
                }
                const point = surface.mapFromItem(null,
                    eventPoint.scenePosition.x, eventPoint.scenePosition.y)
                DeskServices.DeskDesktopService.openMenu("", point.x, point.y)
            }
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: {
                DeskServices.DeskDesktopService.closeMenu()
                if (root.editing)
                    DeskServices.DeskDesktopService.selected = ""
            }
        }

        // Grid lines, only while arranging; built and destroyed with the mode.
        Loader {
            anchors.fill: parent
            active: root.editing
            sourceComponent: lattice
        }

        // Landing mark: the cell the held item would drop into. Positioned
        // imperatively so it appears in place instead of animating in from
        // wherever it was last hidden; it only animates between cells.
        Rectangle {
            id: landing

            readonly property var spot: DeskServices.DeskDesktopService.landing
            property bool showing: false

            visible: root.editing && landing.showing
            radius: DeskServices.DeskTheme.desktopRadius
            color: Qt.rgba(DeskServices.DeskTheme.accent.r, DeskServices.DeskTheme.accent.g, DeskServices.DeskTheme.accent.b, 0.14)
            border.color: DeskServices.DeskTheme.accent
            border.width: 2

            onSpotChanged: {
                if (!landing.spot) {
                    landing.showing = false
                    return
                }
                const shape = DeskServices.DeskDesktopService.family(landing.spot.family)
                const x = DeskServices.DeskDesktopService.offsetX(landing.spot.col)
                const y = DeskServices.DeskDesktopService.offsetY(landing.spot.row)
                slide.enabled = landing.showing
                landing.x = x
                landing.y = y
                landing.width = DeskServices.DeskDesktopService.offsetX(landing.spot.col + shape.cols) - DeskServices.DeskTheme.desktopGutter - x
                landing.height = DeskServices.DeskDesktopService.offsetY(landing.spot.row + shape.rows) - DeskServices.DeskTheme.desktopGutter - y
                slide.enabled = true
                landing.showing = true
            }

            Behavior on x { id: slide; NumberAnimation { duration: DeskServices.DeskTheme.durationFast; easing.type: DeskServices.DeskTheme.easing } }
            Behavior on y { enabled: slide.enabled; NumberAnimation { duration: DeskServices.DeskTheme.durationFast; easing.type: DeskServices.DeskTheme.easing } }
            Behavior on width { enabled: slide.enabled; NumberAnimation { duration: DeskServices.DeskTheme.durationFast; easing.type: DeskServices.DeskTheme.easing } }
            Behavior on height { enabled: slide.enabled; NumberAnimation { duration: DeskServices.DeskTheme.durationFast; easing.type: DeskServices.DeskTheme.easing } }
        }

        // One widget per key: a Repeater given a new array rebuilds every
        // delegate. The rows change on every drop; the keys only on add and
        // remove.
        Repeater {
            model: DeskServices.DeskDesktopService.keys

            Widget {
                board: surface
            }
        }

        // The card of every module, only while arranging. Above the widgets but
        // below the one being dragged, so a widget dropped onto it is seen
        // arriving. It fills the board and places its card itself.
        Loader {
            anchors.fill: parent
            z: 1
            active: root.editing
            sourceComponent: Tray { board: surface }
        }

        // The inspector, beside the selected widget and above everything. It
        // closes when a drag starts.
        Loader {
            anchors.fill: parent
            z: 5
            active: root.editing && DeskServices.DeskDesktopService.selected !== "" && DeskServices.DeskDesktopService.picking === ""
            sourceComponent: Inspector { board: surface }
        }

        // A photo's picker, in the inspector's place while it is open.
        Loader {
            anchors.fill: parent
            z: 5
            active: root.editing && DeskServices.DeskDesktopService.picking !== ""
            sourceComponent: Picker { board: surface }
        }

    }

    // ── BACKDROP ────────────────────────────────────────────────────────────
    //
    // While arranging, the wallpaper under the grid: the windows on the
    // workspace go out of the way and the desk looks as it does empty. A
    // surface of its own under this one, so the blur rule still has the
    // wallpaper behind the widgets to blur, as at rest; drawn inside this
    // surface, the capsules showed it sharp. Mapped from the start and never
    // unmapped, so it keeps its place in the top layer below the desk, which
    // joins that layer later. On and off at once, never faded: the blur would
    // show the windows through a half-drawn wallpaper.
    PanelWindow {
        id: backdropWindow

        screen: root.screen

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        WlrLayershell.namespace: "impasto-desktop-backdrop"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        color: "transparent"

        // Takes no input, ever.
        mask: Region {}

        // The board's part of the screen: the bar and the dock keep their
        // bands.
        ClippingRectangle {
            x: DeskServices.DeskDesktopService.insets.left
            y: DeskServices.DeskDesktopService.insets.top
            width: DeskServices.DeskDesktopService.boardWidth
            height: DeskServices.DeskDesktopService.boardHeight
            color: "transparent"
            visible: root.editing && root.raised && backdrop.status === Image.Ready

            // The whole screen, cropped and centred as the wallpaper daemon
            // draws it, and kept loaded at the screen's own pixels so
            // arranging opens on it.
            Image {
                id: backdrop

                readonly property real ratio:
                    backdropWindow.screen ? backdropWindow.screen.devicePixelRatio : 1

                x: -DeskServices.DeskDesktopService.insets.left
                y: -DeskServices.DeskDesktopService.insets.top
                width: backdropWindow.width
                height: backdropWindow.height
                // currentStill, not currentWallpaper: when the wallpaper is
                // a video, currentWallpaper is an mp4 path and Image cannot
                // decode it ("Unsupported image format"). currentStill is
                // the extracted frame in that case, the same path otherwise.
                source: WallpaperService.currentStill !== ""
                    ? DeskServices.DeskDesktopService.urlOf(WallpaperService.currentStill) : ""
                sourceSize.width: backdropWindow.width * backdrop.ratio
                sourceSize.height: backdropWindow.height * backdrop.ratio
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
    }

    // ── MENU ────────────────────────────────────────────────────────────────
    //
    // Right-click menu. On the background: arrange, new note, wallpaper,
    // palette, settings. On a widget: Edit (opens its inspector), Remove, and
    // Open for a note.
    //
    // A surface of its own on the top layer, so the desk stays under the
    // windows while it is open: raising the desk for it drew every widget over
    // a floating window. It is the whole screen and clear, so a click anywhere
    // else closes it.
    LazyLoader {
        active: root.menu !== null && !root.editing

        PanelWindow {
            id: menuWindow

            readonly property var menu: root.menu
            readonly property var row: menu && menu.key !== "" ? DeskServices.DeskDesktopService.entryOf(menu.key) : null
            readonly property bool onNote: row !== null && row.id === "notes"

            screen: root.screen

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            WlrLayershell.namespace: "impasto-desktop-menu"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"

            mask: Region {
                width: menuWindow.width
                height: menuWindow.height
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: DeskServices.DeskDesktopService.closeMenu()
            }

            // At the click, in the board's coordinates, kept on the board.
            PopMenu {
                x: DeskServices.DeskDesktopService.insets.left + (menuWindow.menu
                    ? Math.max(DeskServices.DeskTheme.desktopGutter, Math.min(
                        DeskServices.DeskDesktopService.boardWidth - DeskServices.DeskTheme.desktopGutter - width, menuWindow.menu.x))
                    : 0)
                y: DeskServices.DeskDesktopService.insets.top + (menuWindow.menu
                    ? Math.max(DeskServices.DeskTheme.desktopGutter, Math.min(
                        DeskServices.DeskDesktopService.boardHeight - DeskServices.DeskTheme.desktopGutter - height, menuWindow.menu.y))
                    : 0)

                rows: {
                    if (!menuWindow.menu)
                        return []
                    if (menuWindow.menu.key === "") {
                        return [
                            { id: "arrange", label: "Arrange widgets", icon: "󰆾", warn: false },
                            { id: "note", label: "New note", icon: "󰎞", warn: false },
                            { id: "wallpaper", label: "Wallpaper", icon: "󰸉", warn: false },
                            { id: "palette", label: "Palette", icon: "󰏘", warn: false },
                            { id: "settings", label: "Settings", icon: "󰒓", warn: false }
                        ]
                    }
                    const rows = []
                    if (menuWindow.onNote)
                        rows.push({ id: "open", label: "Open", icon: "󰏫", warn: false })
                    rows.push({ id: "edit", label: "Edit", icon: "󰆾", warn: false })
                    rows.push({ id: "remove", label: "Remove", icon: "󰆴", warn: true })
                    return rows
                }
                onChosen: id => {
                    const menu = menuWindow.menu
                    const row = menuWindow.row
                    DeskServices.DeskDesktopService.closeMenu()
                    switch (id) {
                    case "arrange":
                        DeskServices.DeskDesktopService.edit(true)
                        break
                    case "note":
                        DeskServices.NotesService.create()
                        DeskServices.ModuleService.requestPanel("notes")
                        break
                    case "wallpaper":
                        DeskServices.ModuleService.requestPanel("appearance")
                        break
                    case "palette":
                        DeskServices.ModuleService.requestPanel("palette")
                        break
                    case "settings":
                        DeskServices.DeskDesktopService.settingsRequested()
                        break
                    case "open": {
                        const note = DeskServices.NotesService.noteFor(row)
                        DeskServices.NotesService.open(note ? note.key : "")
                        DeskServices.ModuleService.requestPanel("notes")
                        break
                    }
                    case "edit":
                        DeskServices.DeskDesktopService.edit(true)
                        DeskServices.DeskDesktopService.selected = menu.key
                        break
                    case "remove":
                        DeskServices.DeskDesktopService.remove(menu.key)
                        break
                    }
                }
            }
        }
    }

    Component {
        id: lattice

        Item {
            Repeater {
                model: DeskServices.DeskDesktopService.columns * DeskServices.DeskDesktopService.rows

                Squircle {
                    id: square

                    required property int index
                    readonly property int col: square.index % DeskServices.DeskDesktopService.columns
                    readonly property int row: Math.floor(square.index / DeskServices.DeskDesktopService.columns)

                    x: DeskServices.DeskDesktopService.offsetX(square.col)
                    y: DeskServices.DeskDesktopService.offsetY(square.row)
                    width: DeskServices.DeskDesktopService.offsetX(square.col + 1) - DeskServices.DeskTheme.desktopGutter - square.x
                    height: DeskServices.DeskDesktopService.offsetY(square.row + 1) - DeskServices.DeskTheme.desktopGutter - square.y
                    radius: DeskServices.DeskTheme.radiusSmall
                    color: "transparent"
                    borderColor: DeskServices.DeskTheme.hairline
                    borderWidth: 1
                }
            }
        }
    }
}
