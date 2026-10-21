import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

/**
 * PhoneLivePill -- the "mirroring" / "camera" live indicators (priority 34):
 * a compact pill styled like PhoneCallPill, a small glyph and a label.
 * Mirroring wins over camera; when both are live the camera shows as a
 * second dot.
 */
Item {
    id: root

    property var service: PhoneService
    // "mirroring" | "camera"
    property string kind: "mirroring"

    readonly property bool audioOnly: service ? service.airplayState === "audio" : false
    readonly property bool cameraAlso: kind === "mirroring" && service && service.cameraActive === true
    readonly property string label: kind === "camera" ? "iPhone camera"
        : audioOnly ? "iPhone audio" : "iPhone screen"
    readonly property string glyph: kind === "camera" ? "camera"
        : audioOnly ? "volume-2" : "airplay"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        spacing: 10

        Icon {
            Layout.alignment: Qt.AlignVCenter
            name: root.glyph
            size: 16
            color: "#32d74b"
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

        Rectangle {
            visible: root.cameraAlso
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: 4
            color: "#32d74b"
        }
    }
}
