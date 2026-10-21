// Simplified port of impasto's bar/island/NotesPanel.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// A grid of sticky notes, drawn with desktop/components/Sticky.qml (already
// shipped by the desktop port for the desktop deck -- read-only paper/title/
// body rendering). Tap a note to open it for editing below the grid; the
// "+" tile creates a new one. Real persistence throughout
// (services/NotesService.qml's notes.json), the same store the desktop
// Deck writes to.

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../desktop/services" as Desk
import "../desktop/components" as DeskComponents
import "components" as DashComponents

ColumnLayout {
    id: root

    signal closed()

    spacing: 10

    property string editingKey: ""
    readonly property var editingNote: Desk.NotesService.entry(root.editingKey)

    GridView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        cellWidth: 150
        cellHeight: 150
        model: Desk.NotesService.live

        delegate: Item {
            required property var modelData
            width: GridView.view.cellWidth - 8
            height: GridView.view.cellHeight - 8

            DeskComponents.Sticky {
                anchors.fill: parent
                note: modelData
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.editingKey = modelData.key
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        DashComponents.QuickTile {
            Layout.preferredWidth: 140
            Layout.preferredHeight: 40
            label: "New note"
            icon: "󰐕"
            onToggled: root.editingKey = Desk.NotesService.create()
        }

        DashComponents.QuickTile {
            Layout.preferredWidth: 100
            Layout.preferredHeight: 40
            visible: root.editingKey !== ""
            label: "Delete"
            icon: "󰆴"
            onToggled: {
                Desk.NotesService.remove(root.editingKey)
                root.editingKey = ""
            }
        }
    }

    DashComponents.Card {
        Layout.fillWidth: true
        Layout.preferredHeight: 130
        visible: root.editingKey !== ""
        padding: 8

        TextArea {
            anchors.fill: parent
            text: root.editingNote ? root.editingNote.title + "\n" + root.editingNote.text : ""
            wrapMode: TextArea.Wrap
            font.family: Desk.DeskTheme.fontFamily
            color: Desk.DeskTheme.text
            background: null
            onEditingFinished: {
                if (root.editingKey === "")
                    return
                const lines = text.split("\n")
                Desk.NotesService.update(root.editingKey, {
                    title: lines[0] ?? "",
                    text: lines.slice(1).join("\n")
                })
            }
        }
    }
}
