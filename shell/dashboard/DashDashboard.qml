// Root of the impasto dashboard port -- hosts the control centre and its
// panels/module details inside the shell's OWN island/dashboard surface
// (island/IslandExpanded.qml's "overview" page). Not a 1:1 file from
// upstream: impasto's own island shell/morphing (bar/island/IslandState.qml,
// IslandSummary.qml, IslandRest.qml) was explicitly out of scope (see the
// brief and HANDOVER.md) -- this is new glue, written for this port, that
// switches between the ported panels (bar/island/ControlsPanel.qml,
// OverviewPanel.qml, BoardPanel.qml, AppearancePanel.qml, KeysPanel.qml,
// PackagesPanel.qml, StatsPanel.qml, PetPanel.qml, NotesPanel.qml,
// GamesPanel.qml, DetailFace.qml -- see each ported file's own header for
// its GPL-3.0/Andreu Massanet attribution) the way impasto's real island
// switched between ITS pages, minus the pieces this port skipped.
//
// Gated by DeskSettings.dashboardImpasto (default true) at the call site in
// island/IslandExpanded.qml, not here -- this file assumes it is already
// the chosen content.

import QtQuick
import "../desktop/services" as Desk
import "../components"

Item {
    id: root

    // "control-center" | "overview" | "board" | "appearance" | "keys" |
    // "packages" | "stats" | "pet" | "notes" | "games" | "detail"
    property string page: "control-center"
    property string detailModuleId: ""

    // The control centre's "settings" door doesn't open a page inside this
    // router -- it's the island's own top-level settings state (island/
    // IslandExpanded.qml's `page === "settings"`), owned above this file.
    signal settingsRequested()

    function openPanel(panel: string): void {
        if (panel === "")
            return
        root.page = panel
    }

    function openModule(moduleId: string): void {
        root.detailModuleId = moduleId
        root.page = "detail"
    }

    function backToControlCentre(): void {
        root.page = "control-center"
        root.detailModuleId = ""
    }

    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (root.page) {
            case "overview": return overviewComponent
            case "board": return boardComponent
            case "appearance": return appearanceComponent
            case "keys": return keysComponent
            case "packages": return packagesComponent
            case "stats": return statsComponent
            case "pet": return petComponent
            case "notes": return notesComponent
            case "games": return gamesComponent
            case "detail": return detailComponent
            default: return controlsComponent
            }
        }
    }

    Component {
        id: controlsComponent
        DashControlsPanel {
            onPanelRequested: panel => root.openPanel(panel)
            onModuleRequested: moduleId => root.openModule(moduleId)
            onSettingsRequested: root.settingsRequested()
        }
    }

    Component {
        id: overviewComponent
        DashOverviewPanel { onClosed: root.backToControlCentre() }
    }

    Component {
        id: boardComponent
        DashBoardPanel { onClosed: root.backToControlCentre() }
    }

    Component {
        id: appearanceComponent
        DashAppearancePanel { onClosed: root.backToControlCentre() }
    }

    Component {
        id: keysComponent
        DashKeysPanel { onClosed: root.backToControlCentre() }
    }

    Component {
        id: packagesComponent
        DashPackagesPanel { onClosed: root.backToControlCentre() }
    }

    Component {
        id: statsComponent
        DashStatsPanel { onClosed: root.backToControlCentre() }
    }

    Component {
        id: petComponent
        DashPetPanel { onClosed: root.backToControlCentre() }
    }

    Component {
        id: notesComponent
        DashNotesPanel { onClosed: root.backToControlCentre() }
    }

    Component {
        id: gamesComponent
        DashGamesPanel { onClosed: root.backToControlCentre() }
    }

    Component {
        id: detailComponent
        DashDetailFace {
            moduleId: root.detailModuleId
            onClosed: root.backToControlCentre()
            onPanelRequested: panel => root.openPanel(panel)
        }
    }

    // Back button, over every page except the control centre itself.
    Squircle {
        visible: root.page !== "control-center"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 4
        width: 28
        height: 28
        radius: Desk.DeskTheme.radiusSmall
        color: backMouse.containsMouse ? Desk.DeskTheme.islandSurfaceHover : Desk.DeskTheme.islandSurface
        z: 10

        Text {
            anchors.centerIn: parent
            text: "󰅁"
            font.family: Desk.DeskTheme.fontMono
            font.pixelSize: 13
            color: Desk.DeskTheme.text
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.backToControlCentre()
        }
    }
}
