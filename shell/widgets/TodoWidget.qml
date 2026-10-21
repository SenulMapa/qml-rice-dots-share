// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

/**
 * TodoWidget -- add/check-off/remove task list, ported from end4-ii's
 * sidebarRight/todo/{TodoWidget,TaskList}.qml against a new, much smaller
 * services/TodoService.qml (see its header for what was dropped from ii's
 * services/Todo.qml). UI-wise this also drops ii's separate
 * Unfinished/Done SwipeView tabs -- done items just sink to the bottom
 * with strikethrough, which fits in the widget's fixed footprint without
 * a tab bar eating vertical space.
 */
Item {
    id: root

    readonly property var sortedItems: TodoService.items.slice()
        .sort((a, b) => (a.done ? 1 : 0) - (b.done ? 1 : 0))

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.space3
        spacing: Theme.space2

        Text {
            Layout.fillWidth: true
            text: "To-do"
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textBody
            font.weight: Font.DemiBold
            color: Theme.surfaceText
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Theme.space1
            model: root.sortedItems

            delegate: RowLayout {
                width: ListView.view.width
                required property var modelData
                spacing: Theme.space2

                Text {
                    text: modelData.done ? "☑" : "☐"
                    font.pixelSize: Theme.textBody
                    color: modelData.done ? Theme.primary : Theme.surfaceVariantText
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Theme.space1
                        onClicked: TodoService.toggleDone(modelData.id)
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: modelData.text
                    elide: Text.ElideRight
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.textSmall
                    font.strikeout: modelData.done
                    color: modelData.done ? Theme.surfaceVariantText : Theme.surfaceText
                }
                Text {
                    text: "×"
                    font.pixelSize: Theme.textBody
                    color: Theme.surfaceVariantText
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -Theme.space1
                        onClicked: TodoService.removeTask(modelData.id)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.sortedItems.length === 0
                text: "Nothing here yet"
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textSmall
                color: Theme.surfaceVariantText
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space2

            TextInput {
                id: newTaskInput
                Layout.fillWidth: true
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.textSmall
                color: Theme.surfaceText
                clip: true

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: newTaskInput.text.length === 0
                    text: "Add a task…"
                    font: newTaskInput.font
                    color: Theme.surfaceVariantText
                }

                Keys.onReturnPressed: {
                    TodoService.addTask(newTaskInput.text)
                    newTaskInput.text = ""
                }
            }
            Text {
                text: "+"
                font.pixelSize: Theme.textTitle
                color: Theme.primary
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Theme.space1
                    onClicked: {
                        TodoService.addTask(newTaskInput.text)
                        newTaskInput.text = ""
                    }
                }
            }
        }
    }
}
