import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

/**
 * PhoneCallPill -- the active-call island state ("callActive", priority 35):
 * green dot + m:ss timer. Clicking grows it into mute / hang up controls
 * (`expanded`, owned by IslandController.callPillExpanded).
 */
Item {
    id: root

    property var service: PhoneService
    property var call: service ? service.call : null
    property bool expanded: false
    signal toggleRequested()
    // Testability seam: fixed "now" in epoch ms (0 = use the clock).
    property real nowOverride: 0
    property real now: Date.now()

    readonly property real startedAt: call && call.startedAt ? call.startedAt : now
    readonly property int elapsed: Math.max(0, Math.floor(
        ((nowOverride > 0 ? nowOverride : now) - startedAt) / 1000))
    readonly property string timerText: Math.floor(elapsed / 60) + ":"
        + (elapsed % 60 < 10 ? "0" : "") + (elapsed % 60)
    // Idle-but-unlocked machine: an incoming call is shown as this pill
    // instead of the full card (services/PhoneAttention.qml).
    readonly property bool ringing: call ? call.state === "incoming" : false
    readonly property bool muted: call ? call.muted === true : false
    readonly property string who: call ? (call.name || call.number || "") : ""

    Timer {
        interval: 1000
        repeat: true
        running: root.visible && root.call !== null
        onTriggered: root.now = Date.now()
    }

    TapHandler {
        enabled: !root.expanded && !root.ringing
        onTapped: root.toggleRequested()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: root.expanded ? 14 : 18
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 8
            Layout.preferredHeight: 8
            radius: 4
            color: root.ringing ? "#ff9f0a" : "#32d74b"
            SequentialAnimation on opacity {
                running: root.ringing && root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 520; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
            }
        }

        Text {

            textFormat: Text.PlainText
            Layout.alignment: Qt.AlignVCenter
            text: root.ringing ? "Ringing" : root.timerText
            color: Theme.t1
            font.family: Theme.fontUi
            font.pixelSize: 15
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
        }

        Text {

            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.expanded || root.ringing
            text: root.who
            color: Theme.t3
            elide: Text.ElideRight
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
        }
        Item { Layout.fillWidth: true; visible: !root.expanded && !root.ringing }

        Rectangle {
            visible: root.expanded
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            radius: 22
            color: root.muted ? Theme.fillOn : Theme.inkRaised2
            scale: muteTap.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Icon {
                anchors.centerIn: parent
                name: root.muted ? "mic-off" : "mic"
                size: 20
                color: root.muted ? Theme.glyphOn : Theme.t1
            }
            TapHandler { id: muteTap; onTapped: root.service?.setMuted(!root.muted) }
        }

        Rectangle {
            visible: root.expanded
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            radius: 22
            color: "#ff453a"
            scale: hangTap.pressed ? 0.92 : 1
            Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            Icon {
                anchors.centerIn: parent
                name: "phone"
                size: 20
                color: "#ffffff"
                rotation: 135
            }
            TapHandler { id: hangTap; onTapped: root.service?.hangup() }
        }
    }
}
