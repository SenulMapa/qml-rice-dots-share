// Visual harness for island/WorkspacePillRow.qml's ratio-based layout
// (core/BlobLayout.qml kSlot/kGap/kPad/kIcon/kText). Renders the row at a
// few pill heights with a mocked mixed icon/number workspace set and
// grabs each to a PNG -- no live Hyprland workspace switch needed (which
// would disrupt whoever is actually using the machine), and no on-screen
// capture of the real desktop.
import QtQuick
import Quickshell
import "core"
import "island"

ShellRoot {
    id: root

    Component.onCompleted: Qt.callLater(root.snapAll)

    function snapAll() {
        for (let i = 0; i < rows.length; ++i)
            rows[i].grabToImage(function (img) {
                img.saveToFile("/tmp/frames_hdmi/wsrow_" + i + ".png")
                console.log("SAVED /tmp/frames_hdmi/wsrow_" + i + ".png")
            })
        Qt.callLater(() => { Qt.callLater(() => Qt.quit()) })
    }

    property var rows: [row28, row44]

    PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 400
        implicitHeight: 200
        color: "black"

        Column {
            spacing: 20
            anchors.centerIn: parent

            Rectangle {
                width: row28.width + 20; height: row28.height + 16
                color: "#141414"; radius: 14
                WorkspacePillRow {
                    id: row28
                    anchors.centerIn: parent
                    pillHeight: 28
                    maxWorkspaces: 9
                }
            }
            Rectangle {
                width: row44.width + 20; height: row44.height + 16
                color: "#141414"; radius: 20
                WorkspacePillRow {
                    id: row44
                    anchors.centerIn: parent
                    pillHeight: 44
                    maxWorkspaces: 9
                }
            }
        }
    }
}
