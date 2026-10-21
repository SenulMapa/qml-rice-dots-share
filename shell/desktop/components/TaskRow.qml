// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   T A S K   R O W                                                        │
// │   one task on one line · the tick, the words, the day                    │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import "../services" as DeskServices
import "../../components"


// A task outside the board (module detail, control centre, calendar day).
// The tick toggles done / back to the first lane and takes the press; the
// rest of the row emits `opened`. Colours come in as an ink so desktop faces
// can pass their own.
Item {
    id: root

    property var task: null
    property var ink: ({
        text: DeskServices.DeskTheme.text, muted: DeskServices.DeskTheme.textMuted, accent: DeskServices.DeskTheme.accent,
        accentText: DeskServices.DeskTheme.accentText, raised: DeskServices.DeskTheme.islandSurfaceHover, red: DeskServices.DeskTheme.red
    })

    // Whether the day is written at the end of the line.
    property bool dated: true

    signal opened()

    readonly property bool done: root.task ? root.task.state === "done" : false
    readonly property bool late: DeskServices.DeskTasksService.isOverdue(root.task)

    implicitHeight: 24

    Squircle {
        anchors.fill: parent
        radius: DeskServices.DeskTheme.radiusSmall
        color: rowHover.hovered ? root.ink.raised : "transparent"

        Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 4
        anchors.rightMargin: 6
        spacing: 8

        Item {
            id: tick

            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18

            Rectangle {
                anchors.centerIn: parent
                width: 14
                height: 14
                radius: 7
                color: root.done ? root.ink.accent : "transparent"
                border.color: root.done ? root.ink.accent : root.ink.muted
                border.width: 1.5

                Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }

                Text {
                    anchors.centerIn: parent
                    visible: root.done
                    text: "󰄬"
                    font.family: DeskServices.DeskTheme.fontMono
                    font.pixelSize: 8
                    color: root.ink.accentText
                }
            }

            HoverHandler { cursorShape: Qt.PointingHandCursor }

            // Exclusive grab on press, so the row's own handler underneath
            // does not fire as well.
            TapHandler {
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: {
                    if (root.task)
                        DeskServices.DeskTasksService.toggle(root.task.key)
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - tick.width - 8 - (day.visible ? day.width + 8 : 0)
            text: root.task ? root.task.text : ""
            elide: Text.ElideRight
            font.family: DeskServices.DeskTheme.fontFamily
            font.pixelSize: DeskServices.DeskTheme.fontSizeSmall
            font.strikeout: root.done
            color: root.done ? root.ink.muted : root.ink.text
        }

        Text {
            id: day

            anchors.verticalCenter: parent.verticalCenter
            visible: root.dated && root.task && root.task.due !== ""
            text: root.task ? DeskServices.DeskTasksService.dueLabel(root.task.due) : ""
            font.family: DeskServices.DeskTheme.fontMono
            font.pixelSize: DeskServices.DeskTheme.fontSizeLabel
            color: root.late ? root.ink.red : root.ink.muted
        }
    }

    HoverHandler {
        id: rowHover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.opened()
    }
}
