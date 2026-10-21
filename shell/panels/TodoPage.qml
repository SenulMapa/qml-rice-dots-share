import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../core"
import "../components"
import "../services"

/**
 * TodoPage — blob sub-page: task list with add/check/delete/reorder.
 * Uses existing TodoService for persistence.
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

    // Ink (Config.appearance.ink): Geist title with a "N of M done" caption,
    // 44px task rows with a fillOn check circle, and an inkRaised add field.
    // Old branches stay for ink off.
    readonly property bool ink: Config.appearance.ink
    readonly property int doneCount: TodoService.items.filter(item => item.done).length

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
                text: "Todo"
                color: root.ink ? Theme.t1 : AdaptiveColor.glassText
                font.family: root.ink ? Theme.fontUi : Config.appearance.handFontFamily
                font.pixelSize: root.ink ? 20 : Theme.dashTitle
                font.weight: root.ink ? Font.DemiBold : Font.Normal
                style: root.ink ? Text.Normal : Text.Outline
                styleColor: AdaptiveColor.glassText
            }

            Text {
                visible: root.ink
                text: root.doneCount + " of " + TodoService.items.length + " done"
                color: Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        // Task list
        ListView {
            id: todoList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: TodoService.items

            delegate: Item {
                id: todoRow
                width: todoList.width
                height: root.ink ? 44 : Theme.u(1)

                // Ink: the whole 44px row lights inkRaised on hover.
                Squircle {
                    anchors.fill: parent
                    visible: root.ink
                    radius: Theme.rCtl
                    color: todoRowHover.hovered ? Theme.inkRaised : "transparent"
                }
                HoverHandler { id: todoRowHover; enabled: root.ink }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: root.ink ? Theme.space2 : Theme.space1
                    spacing: root.ink ? Theme.space3 : Theme.space1

                    Squircle {
                        visible: !root.ink
                        Layout.preferredWidth: Theme.u(0.6)
                        Layout.preferredHeight: Theme.u(0.6)
                        radius: Theme.radiusSmall
                        color: AdaptiveColor.activeFill
                        opacity: modelData.done ? 0.3 : 0.1

                        Text {
                            anchors.centerIn: parent
                            text: modelData.done ? "󰄲" : "󰄱"
                            font.pixelSize: Theme.iconSmall
                            color: AdaptiveColor.activeFill
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: TodoService.toggleDone(modelData.id)
                        }
                    }

                    // Ink: a 20px circle, fillOn with a black check when done.
                    Rectangle {
                        visible: root.ink
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        radius: width / 2
                        color: modelData.done ? Theme.fillOn : Theme.inkRaised2

                        Text {
                            anchors.centerIn: parent
                            visible: modelData.done
                            text: "󰄲"
                            font.pixelSize: 12
                            color: Theme.glyphOn
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: TodoService.toggleDone(modelData.id)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: modelData.text
                        color: root.ink ? (modelData.done ? Theme.t3 : Theme.t1) : AdaptiveColor.glassText
                        opacity: root.ink ? 1 : modelData.done ? 0.5 : 1
                        elide: Text.ElideRight
                        font.family: root.ink ? Theme.fontUi : Config.appearance.fontFamily
                        font.pixelSize: root.ink ? 14 : Theme.dashBody
                        font.strikeout: modelData.done
                    }

                    Squircle {
                        visible: !root.ink
                        Layout.preferredWidth: Theme.u(0.6)
                        Layout.preferredHeight: Theme.u(0.6)
                        radius: Theme.radiusSmall
                        color: Theme.error
                        opacity: 0.1

                        Text {
                            anchors.centerIn: parent
                            text: "󰆴"
                            font.pixelSize: Theme.iconSmall
                            color: Theme.error
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: TodoService.removeTask(modelData.id)
                        }
                    }

                    // Ink: delete is a quiet ×, shown on hover.
                    Text {
                        visible: root.ink
                        Layout.preferredWidth: 16
                        horizontalAlignment: Text.AlignHCenter
                        text: "×"
                        color: removeHover.hovered ? Theme.t1 : Theme.t3
                        font.family: Theme.fontUi
                        font.pixelSize: 18
                        opacity: todoRowHover.hovered ? 1 : 0

                        HoverHandler { id: removeHover }
                        TapHandler { onTapped: TodoService.removeTask(modelData.id) }
                    }
                }
            }

            ScrollBar.vertical: ScrollBar {}
        }

        // Ink: one inkRaised field, "+" leading, Return or tap adds the task.
        Squircle {
            visible: root.ink
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: Theme.rCtl
            color: Theme.inkRaised

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space4
                spacing: Theme.space3

                Text {
                    text: "+"
                    color: Theme.t3
                    font.family: Theme.fontUi
                    font.pixelSize: 18
                    font.weight: Font.Medium

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        onClicked: {
                            if (inkTaskInput.text.trim().length > 0) {
                                TodoService.addTask(inkTaskInput.text)
                                inkTaskInput.text = ""
                            }
                        }
                    }
                }

                TextInput {
                    id: inkTaskInput
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.t1
                    selectionColor: Qt.alpha(Theme.t1, 0.24)
                    font.family: Theme.fontUi
                    font.pixelSize: 14
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true

                    Text {
                        visible: inkTaskInput.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Add a task"
                        color: Theme.t3
                        font: inkTaskInput.font
                    }

                    Keys.onReturnPressed: {
                        if (text.trim().length > 0) {
                            TodoService.addTask(text)
                            text = ""
                        }
                    }
                }
            }
        }

        // Input row
        RowLayout {
            visible: !root.ink
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.u(1)
            spacing: Theme.space1

            TextInput {
                id: newTaskInput
                Layout.fillWidth: true
                Layout.fillHeight: true
                text: ""
                color: AdaptiveColor.glassText
                selectionColor: Qt.alpha(AdaptiveColor.activeFill, 0.4)
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.dashBody
                verticalAlignment: TextInput.AlignVCenter

                Keys.onReturnPressed: {
                    if (text.trim().length > 0) {
                        TodoService.addTask(text)
                        text = ""
                    }
                }
            }

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
                    onClicked: {
                        if (newTaskInput.text.trim().length > 0) {
                            TodoService.addTask(newTaskInput.text)
                            newTaskInput.text = ""
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
