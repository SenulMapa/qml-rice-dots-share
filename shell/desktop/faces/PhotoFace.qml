// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   P   H   O   T   O       F   A   C   E                                  │
// │   a picture of your own on the wallpaper · modern                        │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import Quickshell.Widgets

import "../services" as DeskServices
import "../components"
import "../../components"


// A picture of your own, edge to edge, in any of the four families. The widget
// draws no capsule for it (`DeskServices.DeskDesktopService.styleOf`), so the picture is the
// widget and takes the widget's corner rather than `DeskServices.DeskTheme.pictureCorner`.
//
// Empty, it is the capsule the other widgets are drawn on, saying so. The
// picture is chosen on the inspector, while arranging, like the rest of a
// widget's own look; at rest a click opens it in imv.
Item {
    id: root

    property var ink: DeskServices.DeskDesktopService.inkFor(null)
    property var row: null
    property string family: "2x2"

    readonly property string source: DeskServices.DeskDesktopService.pictureOf(root.row)
    readonly property bool lost: picture.status === Image.Error
    readonly property bool empty: root.source === "" || root.lost

    // Decoded at the family's size rather than the animated one, so a resize
    // does not load the file again on every frame.
    readonly property var still: DeskServices.DeskDesktopService.sizeFor(root.family)

    ClippingRectangle {
        anchors.fill: parent
        visible: !root.empty
        radius: DeskServices.DeskTheme.desktopRadius
        color: root.ink.raised
        border.color: root.ink.border
        border.width: 1
        contentUnderBorder: true

        Image {
            id: picture

            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: root.still.width * 2
            sourceSize.height: root.still.height * 2
        }
    }

    // The capsule the other widgets are drawn on, at the desktop's opacity.
    Squircle {
        anchors.fill: parent
        visible: root.empty
        radius: DeskServices.DeskTheme.desktopRadius
        color: Qt.rgba(root.ink.ground.r, root.ink.ground.g, root.ink.ground.b,
                       DeskServices.DeskDesktopService.opacityOf(root.row) / 100)
        borderColor: root.ink.border
        borderWidth: 1

        Column {
            anchors.centerIn: parent
            width: parent.width - 24
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                bottomPadding: 4
                text: "󰋩"
                font.family: DeskServices.DeskTheme.fontMono
                font.pixelSize: root.family === "4x4" ? 30 : 22
                color: root.ink.text
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.lost ? "Picture not found" : "No picture"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
                font.weight: Font.DemiBold
                color: root.ink.text
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: root.lost ? "Edit it to choose another" : "Edit it to choose one"
                font.family: DeskServices.DeskTheme.fontFamily
                font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
                color: root.ink.muted
            }
        }
    }

    // Disabled while arranging, with the rest of the face.
    HoverHandler {
        enabled: root.row !== null && !root.empty
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: root.row !== null && !root.empty
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: DeskServices.DeskDesktopService.openPicture(root.row)
    }
}
