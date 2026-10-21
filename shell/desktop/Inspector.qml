// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   I   N   S   P   E   C   T   O   R                                      │
// │   widget inspector · per-widget appearance                               │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell.Widgets

import "services" as DeskServices
import "components"
import "../components"


// Per-widget settings on a card beside the widget: shape, style, ink, opacity
// and removal. The first tile of each row follows the desktop default.
//
// Fills the surface so the card can go to the right of, the left of or below
// the widget, and so clicks on the card do not reach the background.
Item {
    id: root

    required property Item board

    readonly property string key: DeskServices.DeskDesktopService.selected
    readonly property var row: DeskServices.DeskDesktopService.entryOf(root.key)
    readonly property string moduleId: root.row ? root.row.id : ""
    readonly property var entry: DeskServices.ModuleService.entry(root.moduleId)
    readonly property var box: DeskServices.DeskDesktopService.geometry(
        root.row ?? ({}), root.board.width, root.board.height)

    // A deck of notes on an edge rather than a widget on a cell: no shape, and
    // a list of notes.
    readonly property bool deck: DeskServices.DeskDesktopService.isDeck(root.row)
    readonly property bool onNote: root.moduleId === "notes"
    readonly property bool onPhoto: root.moduleId === "photo"

    // Notes and photos have no capsule to style and no opacity to set.
    readonly property bool styled: !root.onNote && !root.onPhoto

    // Only a print has a chin to write in.
    readonly property bool captioned: root.onPhoto
        && DeskServices.DeskDesktopService.themeOf(root.row) === "analogue"
        && DeskServices.DeskDesktopService.familyOf(root.row) !== "8x2"

    // The caption field lets go when the surface loses the keyboard.
    Connections {
        target: DeskServices.DeskDesktopService

        function onTypingChanged(): void {
            if (!DeskServices.DeskDesktopService.typing)
                caption.focus = false
        }
    }

    Component.onDestruction: DeskServices.DeskDesktopService.typing = false

    readonly property int cardWidth: 312
    readonly property int pad: 14
    readonly property int gap: 14

    // The widget's own overrides, empty when following the desktop.
    readonly property string ownTheme: root.row && root.row.theme ? root.row.theme : ""
    readonly property string ownStyle: root.row && root.row.style ? root.row.style : ""
    readonly property bool ownOpacity: root.row && typeof root.row.opacity === "number"

    // Colours for painting each style tile.
    function inkIn(style: string): var {
        return DeskServices.DeskDesktopService.inkFor({ id: root.moduleId, style: style })
    }

    Squircle {
        id: card

        // To the right of the widget, else the left, else below; kept on the
        // board.
        readonly property bool rightFits:
            root.box.x + root.box.width + root.gap + card.width
                <= root.board.width - DeskServices.DeskTheme.desktopGutter
        readonly property bool leftFits:
            root.box.x - root.gap - card.width >= DeskServices.DeskTheme.desktopGutter

        // A deck on the bottom edge has no side: the card goes above.
        readonly property bool above: root.deck && root.row.edge === "bottom"

        x: card.above ? Math.max(DeskServices.DeskTheme.desktopGutter, root.box.x + DeskServices.DeskTheme.desktopGutter)
            : card.rightFits ? root.box.x + root.box.width + root.gap
            : (card.leftFits ? root.box.x - root.gap - card.width
                : Math.max(DeskServices.DeskTheme.desktopGutter, Math.min(
                    root.board.width - DeskServices.DeskTheme.desktopGutter - card.width, root.box.x)))
        y: card.above ? root.box.y - root.gap - card.height
            : Math.max(DeskServices.DeskTheme.desktopGutter, Math.min(
                root.board.height - DeskServices.DeskTheme.desktopGutter - card.height,
                card.rightFits || card.leftFits
                    ? root.box.y : root.box.y + root.box.height + root.gap))

        width: root.cardWidth
        height: column.implicitHeight + 2 * root.pad
        radius: DeskServices.DeskTheme.radiusLarge
        color: DeskServices.DeskTheme.island
        borderColor: DeskServices.DeskTheme.islandBorder
        borderWidth: 1

        Behavior on x { NumberAnimation { duration: DeskServices.DeskTheme.durationMedium; easing.type: DeskServices.DeskTheme.easing } }
        Behavior on y { NumberAnimation { duration: DeskServices.DeskTheme.durationMedium; easing.type: DeskServices.DeskTheme.easing } }

        // Exclusive from the press; otherwise the background's tap handler also
        // fires and closes the card.
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

            // ── TITLE AND REMOVE ────────────────────────────────────────────

            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.entry
                        ? (root.deck ? `${root.entry.name} · ${"Notes on the edge"}` : root.entry.name)
                        : ""
                    font.family: DeskServices.DeskTheme.fontFamily
                    font.pixelSize: DeskServices.DeskTheme.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: DeskServices.DeskTheme.text
                }

                PillButton {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Remove"
                    implicitHeight: 26
                    onClicked: DeskServices.DeskDesktopService.remove(root.key)
                }
            }

            Rectangle { width: parent.width; height: 1; color: DeskServices.DeskTheme.hairline }

            // ── SHAPE ───────────────────────────────────────────────────────
            //
            // The families this module has a face for, as footprints in cells.
            // The same choice as dragging the corner handle.

            Text {
                visible: !root.deck
                text: "Shape"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.textMuted
            }

            Row {
                visible: !root.deck
                spacing: 8

                Repeater {
                    model: root.deck ? []
                        : DeskServices.DeskDesktopService.familiesFor(root.moduleId, DeskServices.DeskDesktopService.themeOf(root.row))

                    Squircle {
                        id: shapeTile

                        required property string modelData

                        readonly property var shape: DeskServices.DeskDesktopService.family(shapeTile.modelData)
                        readonly property bool current:
                            DeskServices.DeskDesktopService.familyOf(root.row) === shapeTile.modelData

                        width: shapeTile.shape.cols * 9 + 12
                        height: 48
                        radius: DeskServices.DeskTheme.radiusSmall
                        color: shapeTile.current ? DeskServices.DeskTheme.islandSurfaceHover : "transparent"
                        borderColor: shapeTile.current ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.hairline
                        borderWidth: 1

                        Rectangle {
                            anchors.centerIn: parent
                            width: shapeTile.shape.cols * 9
                            height: shapeTile.shape.rows * 9
                            radius: 3
                            color: shapeTile.current ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.textMuted
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: DeskServices.DeskDesktopService.setFamily(root.key, shapeTile.modelData)
                        }
                    }
                }
            }

            // ── WHERE ───────────────────────────────────────────────────────
            //
            // For a note: a grid cell or one of the three edges. Picking an
            // edge moves the note to that edge's deck; for a deck, it moves the
            // whole deck.

            Text {
                visible: root.onNote
                text: "Where"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.textMuted
            }

            Row {
                visible: root.onNote
                spacing: 8

                Repeater {
                    model: root.onNote ? [
                        { id: "grid", label: "Grid", icon: "󰕰" },
                        { id: "left", label: "Left", icon: "󰞕" },
                        { id: "right", label: "Right", icon: "󰞘" },
                        { id: "bottom", label: "Bottom", icon: "󰞖" }
                    ] : []

                    Squircle {
                        id: whereTile

                        required property var modelData

                        readonly property bool current: root.deck
                            ? root.row.edge === whereTile.modelData.id
                            : whereTile.modelData.id === "grid"

                        width: 64
                        height: 48
                        radius: DeskServices.DeskTheme.radiusSmall
                        color: whereTile.current ? DeskServices.DeskTheme.islandSurfaceHover : "transparent"
                        borderColor: whereTile.current ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.hairline
                        borderWidth: 1

                        Column {
                            anchors.centerIn: parent
                            spacing: 3

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: whereTile.modelData.icon
                                font.family: DeskServices.DeskTheme.fontMono
                                font.pixelSize: 14
                                color: whereTile.current ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.textMuted
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: whereTile.modelData.label
                                font.family: DeskServices.DeskTheme.fontFamily
                                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                                color: whereTile.current ? DeskServices.DeskTheme.text : DeskServices.DeskTheme.textMuted
                            }
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: {
                                const where = whereTile.modelData.id
                                if (whereTile.current)
                                    return
                                if (root.deck) {
                                    if (where === "grid")
                                        return
                                    DeskServices.DeskDesktopService.setDeckEdge(root.key, where)
                                    return
                                }
                                DeskServices.DeskDesktopService.noteToEdge(root.key, where)
                            }
                        }
                    }
                }
            }

            // ── ALIGNMENT ───────────────────────────────────────────────────
            //
            // For a deck: the start, centre or end of its edge. Finer placement
            // is the grip before the first tab.

            Text {
                visible: root.deck
                text: "Along the edge"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.textMuted
            }

            Row {
                visible: root.deck
                spacing: 8

                Repeater {
                    model: root.deck ? [
                        { value: 0, label: "Start" },
                        { value: 0.5, label: "Middle" },
                        { value: 1, label: "End" }
                    ] : []

                    Squircle {
                        id: alongTile

                        required property var modelData

                        readonly property bool current: root.deck
                            && Math.abs(DeskServices.DeskDesktopService.alongOf(root.row) - alongTile.modelData.value) < 0.01

                        width: 64
                        height: 30
                        radius: DeskServices.DeskTheme.radiusSmall
                        color: alongTile.current ? DeskServices.DeskTheme.islandSurfaceHover : "transparent"
                        borderColor: alongTile.current ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.hairline
                        borderWidth: 1

                        Text {
                            anchors.centerIn: parent
                            text: alongTile.modelData.label
                            font.family: DeskServices.DeskTheme.fontFamily
                            font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                            color: alongTile.current ? DeskServices.DeskTheme.text : DeskServices.DeskTheme.textMuted
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: DeskServices.DeskDesktopService.setDeckAlong(root.key, alongTile.modelData.value)
                        }
                    }
                }
            }

            // ── NOTES ───────────────────────────────────────────────────────
            //
            // For a deck: every note, ticked on or off this edge, in the order
            // ticked. Ticking a note here moves it from wherever it was.

            Text {
                visible: root.deck
                text: "Which notes"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.textMuted
            }

            Column {
                visible: root.deck
                width: parent.width
                spacing: 4

                Repeater {
                    model: root.deck ? DeskServices.NotesService.live : []

                    Squircle {
                        id: tickRow

                        required property var modelData

                        readonly property bool on: root.deck
                            && DeskServices.DeskDesktopService.deckNotes(root.row).indexOf(tickRow.modelData.key) >= 0
                        readonly property string elsewhere: {
                            const place = DeskServices.DeskDesktopService.placementOf(tickRow.modelData.key)
                            return tickRow.on || place === "" ? "" : place
                        }

                        width: parent.width
                        height: 26
                        radius: DeskServices.DeskTheme.radiusSmall
                        color: tickHover.hovered ? DeskServices.DeskTheme.islandSurfaceHover : "transparent"

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
                                color: tickRow.on ? DeskServices.DeskTheme.accent : "transparent"
                                border.color: tickRow.on ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.textMuted
                                border.width: 1.5

                                Text {
                                    anchors.centerIn: parent
                                    visible: tickRow.on
                                    text: "󰄬"
                                    font.family: DeskServices.DeskTheme.fontMono
                                    font.pixelSize: 9
                                    color: DeskServices.DeskTheme.accentText
                                }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                radius: 4
                                color: DeskServices.NotesService.tintColor(tickRow.modelData.tint)
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 30 - (elsewhereMark.visible ? elsewhereMark.width + 8 : 0)
                                text: DeskServices.NotesService.titleOf(tickRow.modelData)
                                elide: Text.ElideRight
                                font.family: DeskServices.DeskTheme.fontFamily
                                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                                color: tickRow.on ? DeskServices.DeskTheme.text : DeskServices.DeskTheme.textMuted
                            }

                            Text {
                                id: elsewhereMark

                                anchors.verticalCenter: parent.verticalCenter
                                visible: tickRow.elsewhere !== ""
                                text: tickRow.elsewhere === "grid" ? "󰕰" : "󰞘"
                                font.family: DeskServices.DeskTheme.fontMono
                                font.pixelSize: 10
                                color: DeskServices.DeskTheme.textMuted
                            }
                        }

                        HoverHandler { id: tickHover; cursorShape: Qt.PointingHandCursor }

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: DeskServices.DeskDesktopService.toggleDeckNote(root.key, tickRow.modelData.key)
                        }
                    }
                }
            }

            // ── NOTE ────────────────────────────────────────────────────────
            //
            // For a notes widget on a cell: the front of the deck (the default
            // when the row names none), then every note.

            Text {
                visible: root.onNote && !root.deck
                text: "Which note"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.textMuted
            }

            Flow {
                visible: root.onNote && !root.deck
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.onNote && !root.deck
                        ? [{ key: "", text: "The newest", tint: "" }].concat(DeskServices.NotesService.live)
                        : []

                    Rectangle {
                        id: noteTile

                        required property var modelData

                        readonly property string noteKey: noteTile.modelData.key
                        readonly property bool current:
                            (root.row && root.row.note ? root.row.note : "") === noteTile.noteKey
                        readonly property string line: noteTile.noteKey === ""
                            ? noteTile.modelData.text
                            : DeskServices.NotesService.titleOf(noteTile.modelData)

                        width: Math.min(tileLine.implicitWidth + 24 + (noteTile.noteKey === "" ? 0 : 12), 140)
                        height: 26
                        radius: DeskServices.DeskTheme.radiusPill
                        color: noteTile.current ? DeskServices.DeskTheme.islandSurfaceHover : "transparent"
                        border.color: noteTile.current ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.hairline
                        border.width: 1

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 6

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: noteTile.noteKey !== ""
                                width: 7
                                height: 7
                                radius: 3.5
                                color: DeskServices.NotesService.tintColor(noteTile.modelData.tint)
                            }

                            Text {
                                id: tileLine

                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, noteTile.width - 24 - (noteTile.noteKey === "" ? 0 : 12))
                                text: noteTile.line
                                elide: Text.ElideRight
                                font.family: DeskServices.DeskTheme.fontFamily
                                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                                color: noteTile.current ? DeskServices.DeskTheme.text : DeskServices.DeskTheme.textMuted
                            }
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: DeskServices.DeskDesktopService.update(root.key, { note: noteTile.noteKey || null })
                        }
                    }
                }
            }

            // ── PICTURE ─────────────────────────────────────────────────────
            //
            // For a photo: the picture, the picker (`Picker.qml`, in this
            // card's place) and a way to empty it. The only place a picture
            // is chosen.

            Text {
                visible: root.onPhoto
                text: "Picture"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.textMuted
            }

            Row {
                visible: root.onPhoto
                spacing: 10

                ClippingRectangle {
                    width: 48
                    height: 48
                    radius: width * DeskServices.DeskTheme.pictureCorner
                    color: DeskServices.DeskTheme.islandSurface

                    Image {
                        id: thumbnail

                        anchors.fill: parent
                        source: root.onPhoto ? DeskServices.DeskDesktopService.pictureOf(root.row) : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 96
                        sourceSize.height: 96
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: thumbnail.status !== Image.Ready
                        text: "󰋩"
                        font.family: DeskServices.DeskTheme.fontMono
                        font.pixelSize: 18
                        color: DeskServices.DeskTheme.textMuted
                    }
                }

                PillButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Choose…"
                    implicitHeight: 26
                    onClicked: DeskServices.DeskDesktopService.picking = root.key
                }

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.onPhoto && DeskServices.DeskDesktopService.pictureOf(root.row) !== ""
                    icon: "󰅖"
                    iconSize: 13
                    onClicked: DeskServices.DeskDesktopService.update(root.key, { picture: null })
                }
            }

            // ── CAPTION ─────────────────────────────────────────────────────
            //
            // Written in the print's chin. Typing holds the keyboard until
            // Enter, Escape or a click anywhere else.

            Text {
                visible: root.captioned
                text: "Caption"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.textMuted
            }

            Squircle {
                visible: root.captioned
                width: parent.width
                height: 34
                radius: DeskServices.DeskTheme.radiusSmall
                color: DeskServices.DeskTheme.islandSurface
                borderColor: caption.activeFocus ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.islandBorder
                borderWidth: 1

                Behavior on borderColor { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }

                TextInput {
                    id: caption

                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.row && typeof root.row.caption === "string" ? root.row.caption : ""
                    maximumLength: 40
                    font.family: DeskServices.DeskTheme.fontSignature
                    font.pixelSize: 19
                    color: DeskServices.DeskTheme.text
                    selectByMouse: true
                    selectionColor: DeskServices.DeskTheme.accent
                    selectedTextColor: DeskServices.DeskTheme.accentText
                    clip: true

                    onActiveFocusChanged: DeskServices.DeskDesktopService.typing = caption.activeFocus
                    onTextEdited: DeskServices.DeskDesktopService.update(root.key, { caption: caption.text === "" ? null : caption.text })
                    Keys.onReturnPressed: caption.focus = false
                    Keys.onEnterPressed: caption.focus = false
                    Keys.onEscapePressed: caption.focus = false

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: caption.text === "" && !caption.activeFocus
                        text: "Written under the picture"
                        font.family: DeskServices.DeskTheme.fontFamily
                        font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                        color: DeskServices.DeskTheme.textMuted
                    }
                }
            }

            // ── THEME ───────────────────────────────────────────────────────
            //
            // The default first (follows the settings), then each theme, drawn
            // as a live clock face.

            Text {
                visible: root.moduleId !== "notes"
                text: "Face"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.textMuted
            }

            Row {
                visible: root.moduleId !== "notes"
                spacing: 8

                Repeater {
                    model: [{ id: "", label: "Default" }].concat(DeskServices.DeskDesktopService.themes)

                    Squircle {
                        id: themeTile

                        required property var modelData

                        readonly property string themeId: themeTile.modelData.id
                        readonly property string shown:
                            themeTile.themeId !== "" ? themeTile.themeId : DeskServices.DeskSettings.desktopTheme
                        readonly property bool current: root.ownTheme === themeTile.themeId

                        width: 50
                        height: 48
                        radius: DeskServices.DeskTheme.radiusSmall
                        color: "transparent"
                        borderColor: themeTile.current ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.hairline
                        borderWidth: 1

                        ThemeSwatch {
                            anchors.centerIn: parent
                            theme: themeTile.shown
                            factor: 0.19
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 4
                            visible: themeTile.themeId === ""
                            width: 6
                            height: 6
                            radius: 3
                            color: DeskServices.DeskTheme.textMuted
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: DeskServices.DeskDesktopService.setTheme(root.key, themeTile.themeId)
                        }
                    }
                }
            }

            // ── STYLE ───────────────────────────────────────────────────────
            //
            // The default first, then the four styles, each tile painted as the
            // widget would be.

            // Not for notes or photos (`styled`).
            Text {
                visible: root.styled
                text: "Style"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.textMuted
            }

            Row {
                visible: root.styled
                spacing: 8

                Repeater {
                    model: [{ id: "", label: "Default" }].concat(DeskServices.DeskDesktopService.styles)

                    Squircle {
                        id: styleTile

                        required property var modelData

                        readonly property string styleId: styleTile.modelData.id
                        // The style this tile shows; for the default tile, the
                        // desktop's style.
                        readonly property string shown:
                            styleTile.styleId !== "" ? styleTile.styleId : DeskServices.DeskSettings.desktopStyle
                        readonly property var ink: root.inkIn(styleTile.shown)
                        readonly property bool current: root.ownStyle === styleTile.styleId

                        width: 50
                        height: 48
                        radius: DeskServices.DeskTheme.radiusSmall
                        color: "transparent"
                        borderColor: styleTile.current ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.hairline
                        borderWidth: 1

                        StyleSwatch {
                            anchors.centerIn: parent
                            style: styleTile.shown
                            ink: styleTile.ink
                        }

                        // A dot marks the default tile as "follow" rather than
                        // a fifth style.
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 4
                            visible: styleTile.styleId === ""
                            width: 6
                            height: 6
                            radius: 3
                            color: DeskServices.DeskTheme.textMuted
                        }

                        HoverHandler { cursorShape: Qt.PointingHandCursor }

                        TapHandler {
                            gesturePolicy: TapHandler.ReleaseWithinBounds
                            onTapped: DeskServices.DeskDesktopService.setStyle(root.key, styleTile.styleId)
                        }
                    }
                }
            }

            Text {
                visible: root.styled
                width: parent.width
                text: {
                    const theme = DeskServices.DeskDesktopService.themes.find(
                        entry => entry.id === DeskServices.DeskDesktopService.themeOf(root.row))
                    const style = DeskServices.DeskDesktopService.styles.find(
                        entry => entry.id === DeskServices.DeskDesktopService.styleOf(root.row))
                    const parts = [theme ? theme.label : "", style ? style.label : ""]
                    const own = root.ownTheme !== "" || root.ownStyle !== ""
                    return parts.filter(part => part !== "").join(" · ")
                        + (own ? "" : ` · ${"default"}`)
                }
                elide: Text.ElideRight
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                color: DeskServices.DeskTheme.textMuted
            }

            // ── OPACITY ─────────────────────────────────────────────────────

            Item {
                visible: root.styled
                width: parent.width
                height: 40

                SliderRow {
                    anchors.left: parent.left
                    anchors.right: reset.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    height: 40
                    icon: "󰊸"
                    value: DeskServices.DeskDesktopService.opacityOf(root.row)
                    from: 20
                    to: 100
                    onMoved: value => DeskServices.DeskDesktopService.setOpacity(root.key, Math.round(value))
                }

                IconButton {
                    id: reset

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "󰦛"
                    iconSize: 13
                    enabled: root.ownOpacity
                    opacity: root.ownOpacity ? 1 : 0.3
                    onClicked: DeskServices.DeskDesktopService.setOpacity(root.key, null)
                }
            }

        }
    }
}
