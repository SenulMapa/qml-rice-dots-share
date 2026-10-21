// ╭──────────────────────────────────────────────────────────────────────────╮
// │                                                                          │
// │   P O P   M E N U                                                        │
// │   context menu · opened at the click position                            │
// │                                                                          │
// │   github.com/andreumassanet/impasto                                      │
// │                                                                          │
// ╰──────────────────────────────────────────────────────────────────────────╯

import QtQuick
import QtQuick.Layouts
import "../services" as DeskServices
import "../../components"


// A small context menu with the dock menu's look (plate, row height, fixed
// width), so right-click menus on the wallpaper, widgets and dock match.
//
// Drawn inside the owning surface, not as a popup (see `DockMenu`). It never
// takes the keyboard: it closes on a click outside, a right click, or a
// choice.
//
//   rows   [{ id, label, icon, warn }] — `warn` reddens under the pointer,
//          for destructive actions
Item {
    id: root

    property var rows: []

    signal chosen(string id)

    implicitWidth: 230
    implicitHeight: column.implicitHeight + 10
    width: implicitWidth
    height: implicitHeight

    // macOS dark menu material (shared with the dock menu).
    MacMaterial {
        anchors.fill: parent
        radius: 10
        fill: Qt.rgba(0.16, 0.16, 0.17, 0.74)
    }

    ColumnLayout {
        id: column

        anchors.fill: parent
        anchors.margins: 5
        spacing: 0

        Repeater {
            model: root.rows

            Rectangle {
                id: row

                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 24
                radius: 5
                color: rowMouse.containsMouse ? "#0A84FF" : "transparent"

                Behavior on color { ColorAnimation { duration: DeskServices.DeskTheme.durationFast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        Layout.preferredWidth: 16
                        horizontalAlignment: Text.AlignHCenter
                        text: row.modelData.icon ?? ""
                        font.family: DeskServices.DeskTheme.fontMono
                        font.pixelSize: 12
                        color: rowMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.6)
                    }

                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.label
                        elide: Text.ElideRight
                        font.family: "system-ui"
                        font.pixelSize: 13
                        color: rowMouse.containsMouse ? "white" : Qt.rgba(1, 1, 1, 0.92)
                    }
                }

                MouseArea {
                    id: rowMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.chosen(row.modelData.id)
                }
            }
        }
    }
}
