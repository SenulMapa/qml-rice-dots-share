import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

/**
 * PhoneAirplayPin -- the "airplayPin" island transient (priority 47): an
 * iPhone is trying to AirPlay and needs the password. The island shows the
 * device only, never a secret (the event's `pin` is always null); the password
 * is revealed on request in the phone satellite. It leaves when
 * PhoneService.airplayState changes (IslandController.syncPhoneLive).
 */
Item {
    id: root

    property var service: PhoneService
    readonly property string device: service && service.airplayDevice ? service.airplayDevice : "iPhone"

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        Text {
            textFormat: Text.PlainText
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.width - 40
            text: root.device + " wants to AirPlay"
            elide: Text.ElideRight
            color: Theme.t1
            font.family: Theme.fontUi
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }

        Text {
            textFormat: Text.PlainText
            Layout.alignment: Qt.AlignHCenter
            text: "Enter the AirPlay password \u00b7 Show it from the iPhone menu"
            color: Theme.t3
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }
}
