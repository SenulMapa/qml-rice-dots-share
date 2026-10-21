import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"

/**
 * TimerDoneToast -- the "Focus done" / "Break over" pill shown when the
 * pomodoro or `timer start` countdown ends (priority 45, see
 * island/IslandController.qml's showTimerDone). Same look as PhoneLivePill:
 * a glyph and one label, no card.
 */
Item {
    id: root

    property string label: "Focus done"
    property bool breakOver: false

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        spacing: 10

        Icon {
            Layout.alignment: Qt.AlignVCenter
            name: root.breakOver ? "coffee" : "check"
            size: 16
            color: Theme.success
        }

        Text {
            textFormat: Text.PlainText
            Layout.alignment: Qt.AlignVCenter
            text: root.label
            color: Theme.t1
            font.family: Theme.fontUi
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }

        Item { Layout.fillWidth: true }
    }
}
