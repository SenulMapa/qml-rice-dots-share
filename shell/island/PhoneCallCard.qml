import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

/**
 * PhoneCallCard -- the incoming-call island state ("call", priority 48):
 * initial avatar, name or number, "iPhone" caption, round decline / answer
 * buttons. `service` is overridable so render-phone.qml and the tests can
 * drive it with a stub.
 */
Item {
    id: root

    property var service: PhoneService
    property var call: service ? service.call : null
    // Retained so the card keeps its content while it fades out.
    property var shown: null
    onCallChanged: if (call) shown = call

    readonly property string title: shown ? (shown.name || shown.number || "Unknown") : ""
    // A failed answer/decline is shown here for a moment (PhoneService.callError).
    readonly property string error: service && service.callError ? String(service.callError) : ""
    readonly property string initial: title.length > 0 ? title.charAt(0).toUpperCase() : "?"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 22
        anchors.rightMargin: 22
        spacing: 16

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 56
            Layout.preferredHeight: 56
            radius: 28
            color: Theme.inkRaised2
            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.initial
                color: Theme.t1
                font.family: Theme.fontSerif
                font.pixelSize: 30
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.title
                color: Theme.t1
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.fontUi
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.error !== "" ? root.error : "iPhone"
                color: root.error !== "" ? Theme.error : Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }
        }

        Rectangle {
            id: decline
            objectName: "decline"
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 52
            Layout.preferredHeight: 52
            radius: 26
            color: "#ff453a"
            scale: declineTap.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Icon {
                anchors.centerIn: parent
                name: "phone"
                size: 22
                color: "#ffffff"
                rotation: 135
            }
            TapHandler { id: declineTap; onTapped: root.service?.decline() }
        }

        Rectangle {
            id: answer
            objectName: "answer"
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 52
            Layout.preferredHeight: 52
            radius: 26
            color: "#32d74b"
            scale: answerTap.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Icon {
                anchors.centerIn: parent
                name: "phone"
                size: 22
                color: "#ffffff"
            }
            TapHandler { id: answerTap; onTapped: root.service?.answer() }
        }
    }
}
