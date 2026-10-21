// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   P   I   C   K   E   R                                                  │
// │   a picture off the disk, chosen on the desk                             │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtCore
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets

import "services" as DeskServices
import "components"
import "../components"


// A photo widget's picker, drawn on the desk in the inspector's place: the
// places down the side, the folder as thumbnails. A click on a folder goes
// into it and a click on a picture is the choice. Pointer only, since the desk
// has no keyboard, so there is no typed path and no search.
//
// Fills the surface, as the inspector does, so the card can sit beside the
// widget and clicks on it do not reach the background.
Item {
    id: root

    required property Item board

    readonly property string key: DeskServices.DeskDesktopService.picking
    readonly property var row: DeskServices.DeskDesktopService.entryOf(root.key)
    readonly property var box: DeskServices.DeskDesktopService.geometry(
        root.row ?? ({}), root.board.width, root.board.height)
    readonly property string current:
        root.row && typeof root.row.picture === "string" ? root.row.picture : ""

    readonly property int gap: 14
    readonly property int pad: 16
    readonly property int thumb: 108

    readonly property string home: Quickshell.env("HOME")

    function local(url: var): string {
        const text = String(url)
        return text.startsWith("file://") ? decodeURIComponent(text.slice(7)) : text
    }

    function parentOf(path: string): string {
        const cut = path.lastIndexOf("/")
        return cut <= 0 ? "/" : path.slice(0, cut)
    }

    function choose(path: string): void {
        DeskServices.DeskDesktopService.setPicture(root.key, path)
        DeskServices.DeskDesktopService.picking = ""
    }

    // A user folder goes by its name on disk, in the language of the machine
    // that made it. One that is the home itself is left out.
    readonly property var places: [
        { glyph: "󰋩", label: "",
          path: root.local(StandardPaths.writableLocation(StandardPaths.PicturesLocation)) },
        { glyph: "󰸉", label: "Wallpapers",
          path: `${Quickshell.env("XDG_DATA_HOME") || root.home + "/.local/share"}/wallpapers` },
        { glyph: "󰇚", label: "",
          path: root.local(StandardPaths.writableLocation(StandardPaths.DownloadLocation)) },
        { glyph: "󰍹", label: "",
          path: root.local(StandardPaths.writableLocation(StandardPaths.DesktopLocation)) },
        { glyph: "󰋜", label: "Home", path: root.home }
    ].filter(place => place.label !== "" || place.path !== root.home)

    // Opens on the current picture's folder, else the pictures folder.
    property string folder: root.current !== ""
        ? root.parentOf(root.current) : root.places[0].path

    // The place the folder is in: the longest path it starts with.
    readonly property int place: {
        let best = -1
        let length = -1
        root.places.forEach((place, index) => {
            const inside = root.folder === place.path || root.folder.startsWith(place.path + "/")
            if (inside && place.path.length > length) {
                best = index
                length = place.path.length
            }
        })
        return best
    }

    // The folder from the home down: ~ › Imágenes › Fondos.
    readonly property string trail: {
        const inside = root.folder === root.home || root.folder.startsWith(root.home + "/")
        const shown = inside ? "~" + root.folder.slice(root.home.length) : root.folder
        const parts = shown.split("/").filter(part => part !== "")
        return (inside ? parts : ["/"].concat(parts)).join(" › ")
    }

    Squircle {
        id: card

        // Beside the widget where there is room, else over the middle of the
        // board.
        readonly property bool rightFits:
            root.box.x + root.box.width + root.gap + card.width
                <= root.board.width - DeskServices.DeskTheme.desktopGutter
        readonly property bool leftFits:
            root.box.x - root.gap - card.width >= DeskServices.DeskTheme.desktopGutter

        width: Math.min(700, root.board.width - 2 * DeskServices.DeskTheme.desktopGutter)
        height: Math.min(560, root.board.height - 2 * DeskServices.DeskTheme.desktopGutter)
        x: card.rightFits ? root.box.x + root.box.width + root.gap
            : card.leftFits ? root.box.x - root.gap - card.width
            : (root.board.width - card.width) / 2
        y: Math.max(DeskServices.DeskTheme.desktopGutter, Math.min(
            root.board.height - DeskServices.DeskTheme.desktopGutter - card.height, root.box.y))
        radius: DeskServices.DeskTheme.radiusLarge
        color: DeskServices.DeskTheme.island
        borderColor: DeskServices.DeskTheme.islandBorder
        borderWidth: 1

        // Exclusive from the press; otherwise the background's tap handler also
        // fires and closes the card.
        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
        }

        // ── HEAD ────────────────────────────────────────────────────────────

        Item {
            id: head

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root.pad
            height: 30

            IconButton {
                id: back

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                icon: "󰁍"
                iconSize: 14
                enabled: root.folder !== "/"
                opacity: back.enabled ? 1 : 0.3
                onClicked: root.folder = root.parentOf(root.folder)
            }

            Text {
                id: title

                anchors.left: back.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Choose a picture"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeMedium
                font.weight: Font.DemiBold
                color: DeskServices.DeskTheme.text
            }

            Text {
                anchors.left: title.right
                anchors.right: cancel.left
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.trail
                elide: Text.ElideLeft
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                color: DeskServices.DeskTheme.textMuted
            }

            PillButton {
                id: cancel

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Cancel"
                implicitHeight: 26
                onClicked: DeskServices.DeskDesktopService.picking = ""
            }
        }

        Rectangle {
            id: rule

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: head.bottom
            anchors.topMargin: 12
            height: 1
            color: DeskServices.DeskTheme.hairline
        }

        // ── PLACES ──────────────────────────────────────────────────────────

        Column {
            id: side

            anchors.left: parent.left
            anchors.top: rule.bottom
            anchors.margins: 12
            width: 150
            spacing: 2

            Repeater {
                model: root.places

                Squircle {
                    id: placeRow

                    required property var modelData
                    required property int index

                    readonly property bool current: placeRow.index === root.place

                    width: side.width
                    height: 32
                    radius: DeskServices.DeskTheme.radiusSmall
                    color: placeRow.current || placeHover.hovered
                        ? DeskServices.DeskTheme.islandSurfaceHover : "transparent"

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: placeRow.modelData.glyph
                            font.family: DeskServices.DeskTheme.fontMono
                            font.pixelSize: 14
                            color: placeRow.current ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.textMuted
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 24
                            elide: Text.ElideRight
                            text: placeRow.modelData.label !== ""
                                ? placeRow.modelData.label
                                : placeRow.modelData.path.split("/").pop()
                            font.family: DeskServices.DeskTheme.fontFamily
                            font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                            color: placeRow.current ? DeskServices.DeskTheme.text : DeskServices.DeskTheme.textMuted
                        }
                    }

                    HoverHandler { id: placeHover; cursorShape: Qt.PointingHandCursor }

                    TapHandler {
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: root.folder = placeRow.modelData.path
                    }
                }
            }
        }

        Rectangle {
            id: divider

            anchors.left: side.right
            anchors.leftMargin: 12
            anchors.top: rule.bottom
            anchors.bottom: parent.bottom
            width: 1
            color: DeskServices.DeskTheme.hairline
        }

        // ── FOLDER ──────────────────────────────────────────────────────────

        FolderListModel {
            id: listing

            folder: DeskServices.DeskDesktopService.urlOf(root.folder)
            nameFilters: DeskServices.DeskDesktopService.pictureTypes.map(type => `*.${type}`)
            caseSensitive: false
            sortCaseSensitive: false
            showDirsFirst: true
            showHidden: false
        }

        GridView {
            id: grid

            anchors.left: divider.right
            anchors.right: parent.right
            anchors.top: rule.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 8
            anchors.topMargin: 12
            anchors.bottomMargin: 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cellWidth: grid.width / Math.max(1, Math.floor(grid.width / (root.thumb + 16)))
            cellHeight: root.thumb + 28
            model: listing

            delegate: Item {
                id: tile

                required property string fileName
                required property string filePath
                required property url fileUrl
                required property bool fileIsDir

                readonly property bool chosen: !tile.fileIsDir && tile.filePath === root.current
                readonly property bool lit: tileHover.hovered || tile.chosen

                width: grid.cellWidth
                height: grid.cellHeight

                ClippingRectangle {
                    id: picture

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.thumb
                    height: root.thumb
                    radius: width * DeskServices.DeskTheme.pictureCorner
                    color: DeskServices.DeskTheme.islandSurface
                    border.color: tile.lit ? DeskServices.DeskTheme.accent : "transparent"
                    border.width: 2
                    contentUnderBorder: true

                    Image {
                        anchors.fill: parent
                        visible: !tile.fileIsDir
                        source: tile.fileIsDir ? "" : tile.fileUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: root.thumb * 2
                        sourceSize.height: root.thumb * 2
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: tile.fileIsDir
                        text: "󰉋"
                        font.family: DeskServices.DeskTheme.fontMono
                        font.pixelSize: 34
                        color: tile.lit ? DeskServices.DeskTheme.accent : DeskServices.DeskTheme.textMuted
                    }
                }

                Text {
                    anchors.top: picture.bottom
                    anchors.topMargin: 5
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.thumb + 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: tile.fileName
                    font.family: DeskServices.DeskTheme.fontFamily
                    font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                    color: tile.lit ? DeskServices.DeskTheme.text : DeskServices.DeskTheme.textMuted
                }

                HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }

                TapHandler {
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: {
                        if (tile.fileIsDir)
                            root.folder = tile.filePath
                        else
                            root.choose(tile.filePath)
                    }
                }
            }
        }

        Text {
            anchors.centerIn: grid
            visible: listing.status === FolderListModel.Ready && listing.count === 0
            text: "No pictures here"
            font.family: DeskServices.DeskTheme.fontFamily
            font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
            color: DeskServices.DeskTheme.textMuted
        }
    }
}
