import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../core"
import "../components"
import "../services"
import "../desktop/services" as DeskServices

/**
 * NotesPage — blob sub-page: list + plain-text editor.
 * Uses desktop/services/NotesService for persistence (shared with desktop deck).
 * Esc/back() morphs back to dashboard.
 */
Item {
    id: root

    signal back()

    property real availableWidth: 400
    property real availableHeight: 400

    readonly property real pageWidth: Math.min(Theme.u(16), availableWidth - Theme.u(2))
    readonly property real pageHeight: Math.min(Theme.u(10), availableHeight * 0.7)

    Keys.onEscapePressed: root.back()

    // Ink (Config.appearance.ink): Geist title with text actions, sentence
    // note titles in 15/600, an inkRaised selected row, Geist body text.
    // Old branches stay for ink off.
    readonly property bool ink: Config.appearance.ink

    // Track currently-selected note
    property int selectedIndex: -1

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space2
        spacing: Theme.space2

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            Text {
                Layout.fillWidth: true
                text: "Notes"
                color: root.ink ? Theme.t1 : AdaptiveColor.glassText
                font.family: root.ink ? Theme.fontUi : Config.appearance.handFontFamily
                font.pixelSize: root.ink ? 20 : Theme.dashTitle
                font.weight: root.ink ? Font.DemiBold : Font.Normal
                style: root.ink ? Text.Normal : Text.Outline
                styleColor: AdaptiveColor.glassText
            }

            // Ink: text actions replace the green/red buttons below.
            Text {
                visible: root.ink
                text: "New note"
                color: newNoteHover.hovered ? Theme.t2 : Theme.t1
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.DemiBold

                HoverHandler { id: newNoteHover }
                TapHandler { onTapped: DeskServices.NotesService.add("", "", "yellow") }
            }

            Text {
                visible: root.ink && root.selectedIndex >= 0
                text: "Delete"
                color: deleteNoteHover.hovered ? Theme.t2 : Theme.t1
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.DemiBold

                HoverHandler { id: deleteNoteHover }
                TapHandler {
                    onTapped: {
                        if (root.selectedIndex >= 0 && root.selectedIndex < DeskServices.NotesService.live.length) {
                            DeskServices.NotesService.remove(
                                DeskServices.NotesService.live[root.selectedIndex].key)
                            root.selectedIndex = -1
                        }
                    }
                }
            }
        }

        // Content: notes list on left, editor on right
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.space2

            // Notes list
            ListView {
                id: notesList
                Layout.preferredWidth: root.ink ? 170 : 100
                Layout.fillHeight: true
                clip: true
                model: DeskServices.NotesService.live

                delegate: Item {
                    width: notesList.width
                    height: root.ink ? 44 : Theme.u(1)

                    Squircle {
                        anchors.fill: parent
                        radius: root.ink ? Theme.rCtl : Theme.radiusSmall
                        color: root.ink
                            ? (root.selectedIndex === index ? Theme.inkRaised : "transparent")
                            : root.selectedIndex === index ? AdaptiveColor.activeFill : "transparent"
                        opacity: root.ink ? 1 : 0.15

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selectedIndex = index
                        }
                    }

                    Text {
                        anchors.fill: parent
                        anchors.margins: root.ink ? 12 : Theme.space1
                        text: DeskServices.NotesService.titleOf(modelData)
                        elide: Text.ElideRight
                        color: root.ink
                            ? (root.selectedIndex === index ? Theme.t1 : Theme.t2)
                            : AdaptiveColor.glassText
                        // Ink only: leaves the default family untouched when off.
                        Binding on font.family {
                            when: root.ink
                            value: Theme.fontUi
                        }
                        font.pixelSize: root.ink ? 15 : Theme.dashCaption
                        font.weight: root.ink ? Font.DemiBold : Font.Normal
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                ScrollBar.vertical: ScrollBar {}
            }

            // Editor
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.space1

                TextEdit {
                    id: noteEditor
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    text: root.selectedIndex >= 0 && root.selectedIndex < DeskServices.NotesService.live.length
                        ? DeskServices.NotesService.live[root.selectedIndex].text : ""
                    color: root.ink ? Theme.t1 : AdaptiveColor.glassText
                    selectionColor: Qt.alpha(AdaptiveColor.activeFill, 0.4)
                    font.family: root.ink ? Theme.fontUi : Config.appearance.fontFamily
                    font.pixelSize: root.ink ? 14 : Theme.dashBody
                    wrapMode: TextEdit.Wrap

                    onTextChanged: {
                        saveDebounce.restart()
                    }

                    Timer {
                        id: saveDebounce
                        interval: 600
                        onTriggered: {
                            if (root.selectedIndex >= 0 && root.selectedIndex < DeskServices.NotesService.live.length) {
                                const note = DeskServices.NotesService.live[root.selectedIndex]
                                DeskServices.NotesService.update(note.key, { text: noteEditor.text })
                            }
                        }
                    }
                }

                // Buttons: new, delete (ink uses the header text actions)
                RowLayout {
                    visible: !root.ink
                    Layout.fillWidth: true
                    spacing: Theme.space1

                    Item { Layout.fillWidth: true }

                    Squircle {
                        Layout.preferredWidth: Theme.u(0.8)
                        Layout.preferredHeight: Theme.u(0.8)
                        radius: Theme.radiusSmall
                        color: Theme.success
                        opacity: 0.2

                        Text {
                            anchors.centerIn: parent
                            text: "󰐕"
                            font.pixelSize: Theme.iconSmall
                            color: Theme.success
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: DeskServices.NotesService.add("", "", "yellow")
                        }
                    }

                    Squircle {
                        Layout.preferredWidth: Theme.u(0.8)
                        Layout.preferredHeight: Theme.u(0.8)
                        radius: Theme.radiusSmall
                        color: Theme.error
                        opacity: 0.2
                        enabled: root.selectedIndex >= 0

                        Text {
                            anchors.centerIn: parent
                            text: "󰆴"
                            font.pixelSize: Theme.iconSmall
                            color: Theme.error
                            opacity: enabled ? 1 : 0.4
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (root.selectedIndex >= 0 && root.selectedIndex < DeskServices.NotesService.live.length) {
                                    DeskServices.NotesService.remove(
                                        DeskServices.NotesService.live[root.selectedIndex].key)
                                    root.selectedIndex = -1
                                }
                            }
                        }
                    }
                }
            }
        }

        GlassPillButton {
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: 32
            icon: "arrow_back"
            text: "Back"
            onClicked: root.back()
        }
    }
}
