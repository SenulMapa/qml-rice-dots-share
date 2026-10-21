// Ported from impasto's bar/island/DetailFace.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// A module's expanded view, opened by clicking it in the control centre.
// The island draws this for every module without knowing which ones have
// their own list/menu -- network and bluetooth get one, calendar reuses the
// control centre's month, everything else gets its card.
//
// Adaptation: upstream's "card" fallback is `bar/modules/Module.qml`'s own
// non-compact per-module rendering -- the bar, out of scope for this port
// (see HANDOVER.md). Re-deriving 18 modules' full-size "card" layouts from
// scratch would duplicate real bindings the desktop port ALREADY built and
// wired to this shell's real services, module by module, in
// desktop/faces/Wides.qml, which has a dedicated face for every module id
// this catalogue lists. This dispatches to that instead: real data, no
// duplicated service wiring, at the cost of the island-details.jpg
// screenshot's exact large-card layout (Wides' faces are sized for the
// desktop's 4x2 widget cell, not a bespoke detail panel).
//
// `backable: false` on the wifi/bluetooth menus (kept verbatim from
// upstream, a prior round had these at `true`): DashDashboard.qml already
// draws its own generic back button over every non-control-centre page,
// so a second one embedded in the list would duplicate it -- same reason
// upstream hides its own. `onPanelRequested: panel =>
// root.panelRequested(panel)` on the bare calendar restored too (dropped
// by that same prior round): impasto's own calendar card can request the
// notifications panel from inside a detail view, and DashDashboard.qml's
// router already knows how to open any panel by name.

import QtQuick
import "../desktop/services" as Desk
import "../desktop/faces" as DeskFaces
import "controls" as DashControls
import "components" as DashComponents

Item {
    id: root

    property string moduleId: ""

    signal closed()
    signal panelRequested(string panel)

    readonly property string menu: root.moduleId === "network" ? "wifi"
        : (root.moduleId === "bluetooth" ? "bluetooth" : "")
    readonly property bool month: root.moduleId === "calendar"

    Loader {
        anchors.fill: parent
        anchors.margins: root.menu !== "" ? Desk.DeskTheme.panelPadding - 4 : 0
        sourceComponent: root.menu === "wifi" ? wifi
            : root.menu === "bluetooth" ? bluetooth
            : root.month ? calendar : card
    }

    Component {
        id: calendar

        // Bare: this Loader's parent (island/IslandExpanded.qml's detail
        // slot) is the card.
        DashControls.CalendarCard {
            bare: true
            padding: 12
            onPanelRequested: panel => root.panelRequested(panel)
        }
    }

    Component {
        id: wifi

        DashNetworkDetail {
            backable: false
            onBack: root.closed()
        }
    }

    Component {
        id: bluetooth

        DashBluetoothDetail {
            backable: false
            onBack: root.closed()
        }
    }

    Component {
        id: card

        DashComponents.Card {
            padding: 16

            DeskFaces.Wides {
                anchors.fill: parent
                moduleId: root.moduleId
            }
        }
    }
}
