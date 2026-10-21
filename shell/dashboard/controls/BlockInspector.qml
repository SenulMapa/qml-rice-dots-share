// Ported from impasto's bar/island/controls/BlockInspector.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// Opens beside a block clicked while the grid is being arranged: the sizes
// the block offers, drawn as cell footprints, and for the toggles block
// which switches it carries.
//
// Adaptation only: ControlsService -> DashServices.DashBlocksService;
// Theme -> Desk.DeskTheme; PillButton -> DeskComponents.PillButton
// (already shipped); Tr.t(...) dropped -- this shell has no localisation
// layer (see every other ported card), plain strings throughout.

import QtQuick

import "../../desktop/services" as Desk
import "../../desktop/components" as DeskComponents
import "../services" as DashServices
import "../../components"

Item {
    id: root

    required property Item board

    readonly property string key: DashServices.DashBlocksService.selected
    readonly property var block: DashServices.DashBlocksService.entryOf(root.key)
    readonly property string blockId: root.block ? root.block.id : ""
    readonly property var entry: DashServices.DashBlocksService.entry(root.blockId)
    readonly property var box: root.block
        ? DashServices.DashBlocksService.geometry(root.block) : ({ x: 0, y: 0, width: 0, height: 0 })

    readonly property bool onToggles: root.blockId === "toggles"

    readonly property int cardWidth: 268
    readonly property int pad: 14
    readonly property int gap: 14

    Squircle {
        id: card

        readonly property bool rightFits:
            root.box.x + root.box.width + root.gap + card.width <= root.board.width
        readonly property bool leftFits:
            root.box.x - root.gap - card.width >= 0

        x: card.rightFits ? root.box.x + root.box.width + root.gap
            : (card.leftFits ? root.box.x - root.gap - card.width
                : Math.max(0, Math.min(root.board.width - card.width, root.box.x)))
        y: Math.max(0, Math.min(root.board.height - card.height,
            card.rightFits || card.leftFits
                ? root.box.y : root.box.y + root.box.height + root.gap))

        width: root.cardWidth
        height: column.implicitHeight + 2 * root.pad
        radius: Desk.DeskTheme.radiusLarge
        color: Desk.DeskTheme.island
        borderColor: Desk.DeskTheme.islandBorder
        borderWidth: 1

        Behavior on x { NumberAnimation { duration: Desk.DeskTheme.durationMedium; easing.type: Desk.DeskTheme.easing } }
        Behavior on y { NumberAnimation { duration: Desk.DeskTheme.durationMedium; easing.type: Desk.DeskTheme.easing } }

        // Exclusive from the press, or the ground's tap underneath would
        // close the inspector.
        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
        }

        Column {
            id: column

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.pad
            spacing: 12

            // ── NAME ────────────────────────────────────────────────────────

            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.entry ? root.entry.name : ""
                    font.family: Desk.DeskTheme.fontFamily
                    font.pixelSize: Desk.DeskTheme.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: Desk.DeskTheme.text
                }

                DeskComponents.PillButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Remove"
                    implicitHeight: 26
                    onClicked: DashServices.DashBlocksService.remove(root.key)
                }
            }

            Rectangle { width: parent.width; height: 1; color: Desk.DeskTheme.hairline }

            // ── SIZE ────────────────────────────────────────────────────────
            //
            // Every size the block offers, as its footprint in cells. The
            // corner handle and the wheel do the same.

            Text {
                text: "Size"
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeLabel
                font.weight: Font.DemiBold
                color: Desk.DeskTheme.textMuted
            }

            Flow {
                width: parent.width
                spacing: 8

                Repeater {
                    model: DashServices.DashBlocksService.sizesFor(root.blockId)

                    Squircle {
                        id: sizeTile

                        required property string modelData

                        readonly property var shape: DashServices.DashBlocksService.parse(sizeTile.modelData)
                        readonly property bool current:
                            DashServices.DashBlocksService.sizeOf(root.block) === sizeTile.modelData

                        width: Math.max(48, sizeTile.shape.cols * 11 + 16)
                        height: 58
                        radius: Desk.DeskTheme.radiusSmall
                        color: sizeTile.current ? Desk.DeskTheme.islandSurfaceHover : "transparent"
                        borderColor: sizeTile.current ? Desk.DeskTheme.accent : Desk.DeskTheme.hairline
                        borderWidth: 1

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: sizeLabel.top
                            anchors.bottomMargin: 6
                            width: sizeTile.shape.cols * 11
                            height: sizeTile.shape.rows * 4
                            radius: 2
                            color: sizeTile.current ? Desk.DeskTheme.accent : Desk.DeskTheme.textMuted
                        }

                        Text {
                            id: sizeLabel

                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            text: DashServices.DashBlocksService.label(sizeTile.modelData)
                            font.family: Desk.DeskTheme.fontMono
                            font.pixelSize: Desk.DeskTheme.fontSizeLabel
                            color: sizeTile.current ? Desk.DeskTheme.text : Desk.DeskTheme.textMuted
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: DashServices.DashBlocksService.setSize(root.key, sizeTile.modelData)
                        }
                    }
                }
            }

            // ── TILES ───────────────────────────────────────────────────────
            //
            // Toggles block only: every switch in the catalogue, ticked when
            // it is on this block. A newly ticked tile goes to the end; the
            // arrows reorder.

            Text {
                visible: root.onToggles
                text: "Toggles"
                font.family: Desk.DeskTheme.fontFamily
                font.pixelSize: Desk.DeskTheme.fontSizeLabel
                font.weight: Font.DemiBold
                color: Desk.DeskTheme.textMuted
            }

            Column {
                visible: root.onToggles
                width: parent.width
                spacing: 2

                Repeater {
                    model: root.onToggles ? DashServices.DashBlocksService.tileRowsOf(root.key) : []

                    Squircle {
                        id: tickRow

                        required property var modelData

                        readonly property bool on:
                            DashServices.DashBlocksService.showsTileIn(root.key, tickRow.modelData.id)
                        readonly property var order: DashServices.DashBlocksService.toggleKeysOf(root.key)
                        readonly property int at: tickRow.order.indexOf(tickRow.modelData.id)

                        width: parent.width
                        height: 24
                        radius: Desk.DeskTheme.radiusSmall
                        color: tickHover.hovered ? Desk.DeskTheme.islandSurfaceHover : "transparent"

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 6
                            anchors.rightMargin: 6
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 14
                                height: 14
                                radius: 4
                                color: tickRow.on ? Desk.DeskTheme.accent : "transparent"
                                border.color: tickRow.on ? Desk.DeskTheme.accent : Desk.DeskTheme.textMuted
                                border.width: 1.5

                                Text {
                                    anchors.centerIn: parent
                                    visible: tickRow.on
                                    text: "󰄬"
                                    font.family: Desk.DeskTheme.fontMono
                                    font.pixelSize: 9
                                    color: Desk.DeskTheme.accentText
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16
                                horizontalAlignment: Text.AlignHCenter
                                text: tickRow.modelData.icon
                                font.family: Desk.DeskTheme.fontMono
                                font.pixelSize: 12
                                color: tickRow.on ? Desk.DeskTheme.accent : Desk.DeskTheme.textMuted
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 46 - (tickRow.on ? 44 : 0)
                                text: tickRow.modelData.label
                                elide: Text.ElideRight
                                font.family: Desk.DeskTheme.fontFamily
                                font.pixelSize: Desk.DeskTheme.fontSizeLabel
                                color: tickRow.on ? Desk.DeskTheme.text : Desk.DeskTheme.textMuted
                            }
                        }

                        HoverHandler { id: tickHover; cursorShape: Qt.PointingHandCursor }

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: DashServices.DashBlocksService.toggleTileIn(root.key, tickRow.modelData.id)
                        }

                        // Declared after the row's tap so a press on an
                        // arrow goes to the arrow.
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            visible: tickRow.on
                            spacing: 2

                            Repeater {
                                model: [{ glyph: "󰅃", delta: -1 }, { glyph: "󰅀", delta: 1 }]

                                Rectangle {
                                    id: arrow

                                    required property var modelData

                                    readonly property bool usable: arrow.modelData.delta < 0
                                        ? tickRow.at > 0 : tickRow.at < tickRow.order.length - 1

                                    width: 20
                                    height: 20
                                    radius: Desk.DeskTheme.radiusSmall
                                    color: arrowHover.hovered && arrow.usable
                                        ? Desk.DeskTheme.islandSurface : "transparent"
                                    opacity: arrow.usable ? 1 : 0.3

                                    Text {
                                        anchors.centerIn: parent
                                        text: arrow.modelData.glyph
                                        font.family: Desk.DeskTheme.fontMono
                                        font.pixelSize: 11
                                        color: Desk.DeskTheme.text
                                    }

                                    HoverHandler { id: arrowHover }

                                    // Always takes the press, even when
                                    // disabled, so a tap doesn't fall
                                    // through to the row and untick the
                                    // tile.
                                    TapHandler {
                                        gesturePolicy: TapHandler.ReleaseWithinBounds
                                        onTapped: {
                                            if (arrow.usable)
                                                DashServices.DashBlocksService.moveTileIn(root.key,
                                                    tickRow.modelData.id, arrow.modelData.delta)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
