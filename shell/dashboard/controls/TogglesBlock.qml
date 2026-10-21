// Simplified port of impasto's bar/island/controls/TogglesBlock.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// Upstream pages tiles that don't fit a fixed block size (wheel/drag/dot
// paging). This port drops the paging and just lays the block's own tile
// set out in a GridLayout instead -- 2 columns, so the default 2x3 toggles
// block (6 tiles) fills exactly. Tile data/behaviour is unchanged: each
// tile still comes straight from a real shell service via
// DashControlsService.tiles.
//
// `blockKey` selects which subset/order to draw, via
// DashServices.DashBlocksService.tilesOf(blockKey) -- the freeform grid
// port's own per-block toggle set, edited from BlockInspector.qml. Empty
// (the fixed-column fallback path, gated by DeskSettings.dashboardBlockGrid)
// draws every tile, as before.
// `cols`/`rows` are accepted for BlockFace's uniform call signature but a
// GridLayout has no size-dependent paging to key off, matching the earlier
// scope decision this header already documented.

import QtQuick
import QtQuick.Layouts
import "../services" as DashServices
import "../components" as DashComponents

Item {
    id: root

    property string blockKey: ""
    property int cols: 2
    property int rows: 3

    signal panelRequested(string panel)
    signal dismissed()

    // A plain Item wraps the GridLayout (rather than being one) because
    // GridLayout already has its own `rows` property -- BlockFace's
    // `rows: root.shape.rows` binding would silently shadow it instead of
    // reaching this block's own size, exactly the way upstream's own
    // TogglesBlock.qml is an Item wrapping its tile grid too.
    GridLayout {
        anchors.fill: parent
        columns: 2
        rowSpacing: 8
        columnSpacing: 8

        Repeater {
            model: root.blockKey !== ""
                ? DashServices.DashBlocksService.tilesOf(root.blockKey)
                : DashServices.DashControlsService.tiles

            DashComponents.QuickTile {
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 62

                icon: modelData.icon
                label: modelData.label
                detail: modelData.detail
                active: modelData.active
                available: modelData.available
                expandable: modelData.expandable

                onToggled: {
                    modelData.activate()
                    if (modelData.closes)
                        root.dismissed()
                }
                onExpanded: root.panelRequested(modelData.panel)
            }
        }
    }
}
