// Ported from impasto's bar/island/ControlsPanel.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// The control centre: a top row of panel-navigation buttons over
// impasto's own freeform, draggable/resizable block grid
// (dashboard/services/DashBlocksService.qml + dashboard/controls/{Block,
// BlockFace,BlockInspector,ControlsTray}.qml -- all ported verbatim, see
// each file's own header), gated by DeskSettings.dashboardBlockGrid
// (default true). Set "dashboardBlockGrid": false in
// ~/.local/state/qml-rice/desktop.json to fall back to the earlier fixed,
// scrolling column with no rebuild -- both paths stay in this file.
//
// Adaptation: ControlsService -> DashServices.DashBlocksService;
// Theme -> Desk.DeskTheme. Upstream's tray lived on the bar's surface,
// outside the panel, so a dragged block could cross from the bar onto the
// island in one gesture; this shell's control centre is a page inside the
// island, not the bar, so the tray/ghost host is this file's own root Item
// instead (see ControlsTray.qml's header) -- the grid math itself (cells,
// collisions, drag/resize/snap, the inspector) is unchanged.
//
// Top row: real `DashBlocksService.shownDoors` (impasto's own settings-
// configurable button list, ported into that file this round -- a prior
// round had shipped a hardcoded 9-id array here instead) through
// `DeskComponents.IconButton` (not `QuickTile`, which is upstream's quick-
// toggle tile, not its door button); row height/gap read from
// `DashBlocksService.rowHeight`/`rowGap` rather than a hardcoded 10/12.
// `settingsRequested()` restored for the "settings" door (panel === ""),
// bubbled to island/IslandExpanded.qml's own `page` the same way
// core/ShellActions.qml's settingsOpenRequested IPC already does.

import QtQuick
import QtQuick.Layouts
import "../desktop/services" as Desk
import "../desktop/components" as DeskComponents
import "services" as DashServices
import "controls" as DashControls
import "../components"

Item {
    id: root

    signal panelRequested(string panel)
    signal moduleRequested(string moduleId)
    // Settings is a window this panel does not own; the request is passed
    // up (island/IslandExpanded.qml owns `page`, the "settings" island
    // state itself is out of this file's scope, same as upstream's own
    // note).
    signal settingsRequested()
    signal closed()

    readonly property bool gridMode: Desk.DeskSettings.dashboardBlockGrid
    readonly property bool editing: root.gridMode && DashServices.DashBlocksService.editing

    // Escape leaves arranging first; otherwise it reaches the island, which
    // closes.
    Component.onCompleted: root.forceActiveFocus()

    Keys.onEscapePressed: event => {
        if (!root.editing) {
            event.accepted = false
            return
        }
        DashServices.DashBlocksService.edit(false)
    }

    // Closing the panel ends arranging too, so it never reopens still in
    // that mode, swallowing clicks.
    Component.onDestruction: {
        if (!root.gridMode)
            return
        DashServices.DashBlocksService.edit(false)
        DashServices.DashBlocksService.board = null
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: DashServices.DashBlocksService.rowGap

        // ── TOP ROW: session actions + panel doors ──────────────────────────

        RowLayout {
            Layout.fillWidth: true
            // A Layout nested in a Layout fills by default; without this
            // it takes the grid's height.
            Layout.fillHeight: false
            Layout.preferredHeight: DashServices.DashBlocksService.rowHeight
            spacing: 12

            DashControls.PowerRow { onRan: root.closed() }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            // Panel buttons, in the order settings keeps them (impasto's
            // own `shownDoors`, ported into DashBlocksService.qml). Settings
            // sends its own request; the rest are panel names.
            Repeater {
                model: DashServices.DashBlocksService.shownDoors

                DeskComponents.IconButton {
                    required property var modelData

                    icon: modelData.icon
                    iconSize: 14
                    onClicked: {
                        if (modelData.panel === "")
                            root.settingsRequested()
                        else
                            root.panelRequested(modelData.panel)
                    }
                }
            }
        }

        // ── BODY: the block grid, or the fixed column fallback ──────────────

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: root.gridMode ? gridSurface : fixedColumn
        }
    }

    // ── GRID (impasto's freeform board, ported verbatim) ────────────────────

    Component {
        id: gridSurface

        Item {
            id: surface

            // Published for the tray, which maps the pointer into these
            // cells.
            Binding {
                target: DashServices.DashBlocksService
                property: "board"
                value: surface
            }

            // Right-click on the background toggles arranging. Declared
            // first, beneath everything: blocks take the left button and
            // the right one falls through.
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: DashServices.DashBlocksService.edit(!DashServices.DashBlocksService.editing)
            }

            // Left-click on the background closes the inspector.
            TapHandler {
                enabled: root.editing
                acceptedButtons: Qt.LeftButton
                onTapped: DashServices.DashBlocksService.selected = ""
            }

            // The cells, only while arranging.
            Loader {
                anchors.fill: parent
                active: root.editing
                sourceComponent: lattice
            }

            // The drop target, lit on the grid before the drop.
            Rectangle {
                id: landing

                readonly property var spot: DashServices.DashBlocksService.landing
                property bool showing: false

                visible: root.editing && landing.showing
                radius: Desk.DeskTheme.radiusMedium
                color: Qt.rgba(Desk.DeskTheme.accent.r, Desk.DeskTheme.accent.g, Desk.DeskTheme.accent.b, 0.14)
                border.color: Desk.DeskTheme.accent
                border.width: 2

                onSpotChanged: {
                    if (!landing.spot) {
                        landing.showing = false
                        return
                    }
                    const box = DashServices.DashBlocksService.pixels(landing.spot.size)
                    slide.enabled = landing.showing
                    landing.x = DashServices.DashBlocksService.offsetX(landing.spot.col)
                    landing.y = DashServices.DashBlocksService.offsetY(landing.spot.row)
                    landing.width = box.width
                    landing.height = box.height
                    slide.enabled = true
                    landing.showing = true
                }

                Behavior on x { id: slide; NumberAnimation { duration: Desk.DeskTheme.durationFast; easing.type: Desk.DeskTheme.easing } }
                Behavior on y { enabled: slide.enabled; NumberAnimation { duration: Desk.DeskTheme.durationFast; easing.type: Desk.DeskTheme.easing } }
                Behavior on width { enabled: slide.enabled; NumberAnimation { duration: Desk.DeskTheme.durationFast; easing.type: Desk.DeskTheme.easing } }
                Behavior on height { enabled: slide.enabled; NumberAnimation { duration: Desk.DeskTheme.durationFast; easing.type: Desk.DeskTheme.easing } }
            }

            // Keyed on block ids rather than rows.
            Repeater {
                model: DashServices.DashBlocksService.keys

                DashControls.Block {
                    board: surface
                    onPanelRequested: panel => root.panelRequested(panel)
                    onDismissed: root.closed()
                }
            }

            // The selected block's options, on a card beside it.
            Loader {
                anchors.fill: parent
                z: 5
                active: root.editing && DashServices.DashBlocksService.selected !== ""
                sourceComponent: inspectorComponent
            }

            Component {
                id: inspectorComponent
                DashControls.BlockInspector { board: surface }
            }
        }
    }

    Component {
        id: lattice

        Item {
            Repeater {
                model: DashServices.DashBlocksService.columns * DashServices.DashBlocksService.rows

                Squircle {
                    required property int index

                    x: DashServices.DashBlocksService.offsetX(index % DashServices.DashBlocksService.columns)
                    y: DashServices.DashBlocksService.offsetY(Math.floor(index / DashServices.DashBlocksService.columns))
                    width: Desk.DeskTheme.centreCellWidth
                    height: Desk.DeskTheme.centreCellHeight
                    radius: Desk.DeskTheme.radiusSmall
                    color: "transparent"
                    borderColor: Desk.DeskTheme.hairline
                    borderWidth: 1
                }
            }
        }
    }

    // The tray, over everything, only while arranging.
    Loader {
        anchors.fill: parent
        z: 50
        active: root.editing
        sourceComponent: trayComponent
    }

    Component {
        id: trayComponent
        DashControls.ControlsTray {
            host: root
            homeTop: 40
        }
    }

    // ── FIXED COLUMN (fallback, DeskSettings.dashboardBlockGrid: false) ─────

    Component {
        id: fixedColumn

        Flickable {
            clip: true
            contentWidth: width
            contentHeight: grid.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: grid
                width: parent.width
                spacing: 10

                DashControls.ClockBlock {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                }

                DashControls.TogglesBlock {
                    Layout.fillWidth: true
                    onPanelRequested: panel => root.moduleRequested(panel)
                }

                DashControls.MediaCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                }

                DashControls.WeatherCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                }

                DashControls.CalendarCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 260
                    onPanelRequested: panel => root.panelRequested(panel)
                }

                DashControls.TasksBlock {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                }

                DashControls.NotificationList {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                }

                DashControls.AppearanceCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                }

                DashControls.PetBlock {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 130
                    onPanelRequested: panel => root.panelRequested(panel)
                }
            }
        }
    }
}
