import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

/**
 * PhoneMessageToast -- the "phoneMessage" island state (priority 45): initial
 * avatar, sender, a 2-line elided preview and an inline reply field. Focus is
 * armed ~250 ms after the toast opens (the focus grab clears on the opening
 * click otherwise). The countdown pauses while the field has focus or the
 * pointer is over the toast. A failed reply keeps the typed text and shows the
 * error under the field.
 */
Item {
    id: root

    property var service: PhoneService
    property var controller: null
    property var entry: null
    // Retained so the content survives the closing fade.
    property var shown: null
    // A newer message must never retarget a reply that is being typed.
    onEntryChanged: if (entry && field.text.length === 0 && !field.activeFocus) shown = entry
    property bool showing: controller
        ? controller.visualState === controller.phoneMessage : false
    property int timeoutMs: Config.notifications.timeout
    property alias replyText: field.text
    property alias errorText: errorLabel.text
    readonly property bool errorVisible: errorLabel.visible
    readonly property bool fieldFocused: field.activeFocus

    signal openThread(string threadId)

    // Locked = no phone text anywhere (services/PhoneAttention.qml).
    readonly property bool textAllowed: PhoneAttention.textAllowed
    readonly property string sender: !textAllowed ? "iPhone" : shown && shown.from
        ? (shown.from.name || shown.from.number || "iPhone") : "iPhone"
    readonly property string initial: sender.length > 0 ? sender.charAt(0).toUpperCase() : "?"
    readonly property string preview: shown && textAllowed ? (shown.text || "") : ""

    function sendReply(): void {
        const text = field.text
        if (text.trim().length === 0 || !root.shown || !root.service)
            return
        errorLabel.text = ""
        const threadId = root.shown.threadId
        root.service.reply(threadId, text, function(result) {
            if (result && result.ok === true) {
                field.text = ""
                if (root.controller)
                    root.controller.clearTransient()
            } else {
                errorLabel.text = (result && result.error) || "Couldn't send"
            }
        })
    }

    onShowingChanged: {
        if (showing) {
            errorLabel.text = ""
            field.text = ""
            progress = 1
            countdown.restart()
            focusTimer.restart()
        } else {
            countdown.stop()
            focusTimer.stop()
            field.focus = false
        }
    }

    property real progress: 1
    NumberAnimation {
        id: countdown
        target: root
        property: "progress"
        from: 1
        to: 0
        duration: root.timeoutMs
        paused: running && (field.activeFocus || toastHover.hovered || field.text.length > 0)
        onFinished: root.controller?.clearTransient()
    }

    Timer {
        id: focusTimer
        interval: 250
        onTriggered: field.forceActiveFocus()
    }

    HoverHandler { id: toastHover }
    TapHandler {
        onTapped: root.openThread(root.shown ? root.shown.threadId : "")
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 20
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        spacing: 14

        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: 40
            Layout.preferredHeight: 40
            radius: 20
            color: Theme.inkRaised2
            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.initial
                color: Theme.t1
                font.family: Theme.fontSerif
                font.pixelSize: 22
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2

            Text {

                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.sender
                color: Theme.t1
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Theme.fontUi
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {

                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: root.preview.replace(/\s*\n\s*/g, " ")
                color: Theme.t2
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                radius: 15
                color: Theme.inkRaised

                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    color: Theme.t1
                    selectionColor: Theme.fillOn
                    selectedTextColor: Theme.glyphOn
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    onAccepted: root.sendReply()
                    Keys.onEscapePressed: root.controller?.clearTransient()
                }
                Text {
                    textFormat: Text.PlainText
                    anchors.fill: field
                    verticalAlignment: Text.AlignVCenter
                    visible: field.text.length === 0
                    text: "Reply"
                    color: Theme.t3
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                }
            }

            Text {

                textFormat: Text.PlainText
                id: errorLabel
                Layout.fillWidth: true
                visible: text.length > 0
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Qt.rgba(1, 0.271, 0.227, 0.8)
                font.family: Theme.fontUi
                font.pixelSize: 12
            }
        }
    }
}
