// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   S T I C K Y                                                            │
// │   one note as paper · the title, the body in handwriting, the colour     │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import "../services" as DeskServices
import "../../components"


// A sticky note: pastel paper, a title and a handwritten body, used wherever
// a note appears (deck cards, desktop widget, edge tab, tray). The ink is a
// fixed dark (`DeskServices.DeskTheme.paper*`), not the palette's text colour.
Item {
    id: root

    property var note: null

    // What an empty deck says, on plain paper.
    property string placeholder: ""

    property int padding: 12
    property int titleSize: DeskServices.DeskTheme.fontSizeSmall
    property int bodySize: 16
    property bool showAge: true

    readonly property color paper: DeskServices.NotesService.paperOf(root.note ? root.note.tint : "yellow")
    readonly property bool titled: root.note && (root.note.title ?? "").trim() !== ""
    readonly property string title: root.note ? DeskServices.NotesService.titleOf(root.note) : ""
    readonly property string body: root.note ? DeskServices.NotesService.display(root.note.text) : root.placeholder

    Squircle {
        anchors.fill: parent
        radius: DeskServices.DeskTheme.paperRadius
        color: root.paper
    }

    Item {
        id: head

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        anchors.topMargin: root.padding - 2
        height: root.titleSize + 8

        Text {
            anchors.left: parent.left
            anchors.right: age.visible ? age.left : parent.right
            anchors.rightMargin: age.visible ? 8 : 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            elide: Text.ElideRight
            font.family: DeskServices.DeskTheme.fontFamily
            font.pixelSize: root.titleSize
            font.weight: Font.DemiBold
            color: root.titled ? DeskServices.DeskTheme.paperInk : DeskServices.DeskTheme.paperInkMuted
        }

        Text {
            id: age

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showAge && root.note !== null
            text: root.note ? DeskServices.NotesService.ageOf(root.note.edited) : ""
            font.family: DeskServices.DeskTheme.fontMono
            font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
            color: DeskServices.DeskTheme.paperInkMuted
        }
    }

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: head.bottom
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
        anchors.topMargin: 4
        anchors.bottomMargin: root.padding
        text: root.body
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        font.family: DeskServices.DeskTheme.fontHand
        font.pixelSize: root.bodySize
        lineHeight: 1.1
        color: root.note ? DeskServices.DeskTheme.paperInk : DeskServices.DeskTheme.paperInkMuted
    }
}
