import QtQuick
import QtQuick.Layouts
import "../components"
import "../core"
import "../services"

/**
 * MessagesPage -- the island "messages" page. Left: threads (name, elided last
 * line, relative time, unread dot). Right: bubbles (incoming on a raised
 * surface, outgoing on the active fill) and a composer (Enter sends,
 * Shift+Enter newline). `service` is overridable for render-phone.qml and tests.
 */
Item {
    id: root

    property var service: PhoneService
    property string threadId: ""
    property bool active: true
    property var threads: []
    property var messages: []
    property string sendError: ""
    // Fixed "now" (epoch ms) for deterministic renders; 0 = the clock.
    property real nowOverride: 0
    signal back()

    readonly property bool connected: service ? service.connected === true : false
    readonly property var currentThread: {
        for (const t of threads)
            if (t.id === threadId)
                return t
        return null
    }

    function relTime(ts: real): string {
        const now = nowOverride > 0 ? nowOverride : Date.now()
        const s = Math.max(0, Math.floor((now - ts) / 1000))
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    function clock(ts: real): string {
        const d = new Date(ts)
        return d.getHours() + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes()
    }

    function refresh(): void {
        if (!service || !active)
            return
        service.threads(function(result) {
            if (!result || result.ok !== true)
                return
            root.threads = result.threads || []
            if (root.threadId === "" && root.threads.length > 0)
                root.threadId = root.threads[0].id
            else
                root.loadThread()
        })
    }

    function loadThread(): void {
        if (!service || threadId === "")
            return
        const wanted = threadId
        service.thread(wanted, function(result) {
            if (wanted !== root.threadId)
                return
            root.messages = result && result.ok === true ? (result.messages || []) : []
            bubbles.stickToEnd = true
            Qt.callLater(() => bubbles.positionViewAtEnd())
        })
    }

    onThreadIdChanged: loadThread()
    onActiveChanged: if (active) refresh()
    Component.onCompleted: refresh()

    Connections {
        target: root.service
        ignoreUnknownSignals: true
        function onMessageReceived(msg): void {
            root.refresh()
        }
    }

    function sendMessage(): void {
        const text = composer.text
        if (text.trim().length === 0 || threadId === "" || !service)
            return
        sendError = ""
        service.reply(threadId, text, function(result) {
            if (result && result.ok === true) {
                composer.text = ""
                root.loadThread()
            } else {
                root.sendError = (result && result.error) || "Couldn't send"
            }
        })
    }

    // ---- empty states -----------------------------------------------------
    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        visible: !root.connected
        text: "iPhone not connected"
        color: Theme.t3
        font.family: Theme.fontUi
        font.pixelSize: 15
        font.weight: Font.Medium
    }
    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        visible: root.connected && root.threads.length === 0
        text: "No messages yet"
        color: Theme.t3
        font.family: Theme.fontUi
        font.pixelSize: 15
        font.weight: Font.Medium
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 12
        visible: root.connected && root.threads.length > 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 22

            // ---- threads --------------------------------------------------
            ColumnLayout {
                Layout.preferredWidth: 250
                Layout.minimumWidth: 250
                Layout.maximumWidth: 250
                Layout.fillHeight: true
                spacing: 8

                Text {

                    textFormat: Text.PlainText
                    text: "Messages"
                    color: Theme.t1
                    font.family: Theme.fontUi
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.3
                }

                ListView {
                    id: threadList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.threads
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Squircle {
                        id: row
                        required property var modelData
                        readonly property bool current: modelData.id === root.threadId
                        width: threadList.width
                        height: 56
                        radius: Theme.rCtl
                        color: current ? Theme.inkRaised : "transparent"
                        scale: rowTap.pressed ? 0.98 : 1
                        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: row.modelData.name || "Unknown"
                                    color: Theme.t1
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: Theme.fontUi
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: row.modelData.last
                                        ? String(row.modelData.last.text || "").replace(/\s*\n\s*/g, " ") : ""
                                    color: Theme.t3
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.family: Theme.fontUi
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                            }
                            ColumnLayout {
                                spacing: 4
                                Layout.alignment: Qt.AlignVCenter
                                Text {
                                    textFormat: Text.PlainText
                                    Layout.alignment: Qt.AlignRight
                                    text: row.modelData.last ? root.relTime(row.modelData.last.ts) : ""
                                    color: Theme.t3
                                    font.family: Theme.fontUi
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                                Rectangle {
                                    Layout.alignment: Qt.AlignRight
                                    visible: (row.modelData.unread || 0) > 0
                                    Layout.preferredWidth: 8
                                    Layout.preferredHeight: 8
                                    radius: 4
                                    color: Theme.fillOn
                                }
                            }
                        }
                        TapHandler {
                            id: rowTap
                            onTapped: root.threadId = row.modelData.id
                        }
                    }
                }
            }

            // ---- conversation ---------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Text {

                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    text: root.currentThread ? (root.currentThread.name || "Unknown") : ""
                    color: Theme.t1
                    elide: Text.ElideRight
                    font.family: Theme.fontUi
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.3
                }

                ListView {
                    id: bubbles
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    model: root.messages
                    boundsBehavior: Flickable.StopAtBounds
                    // Variable-height bubbles measure after positionViewAtEnd() runs, so keep
                    // following the bottom until the user scrolls away from it.
                    property bool stickToEnd: true
                    onMovementEnded: stickToEnd = atYEnd
                    onContentHeightChanged: if (stickToEnd) positionViewAtEnd()

                    delegate: Item {
                        id: bubbleRow
                        required property var modelData
                        required property int index
                        readonly property bool outgoing: modelData.outgoing === true
                        readonly property var prev: index > 0 ? root.messages[index - 1] : null
                        readonly property bool stamp: !prev || modelData.ts - prev.ts > 15 * 60 * 1000
                        readonly property bool showSender: !outgoing && !!modelData.group
                            && (!prev || prev.outgoing || (prev.from && modelData.from
                                && prev.from.name !== modelData.from.name))
                        width: bubbles.width
                        height: col.implicitHeight

                        Column {
                            id: col
                            width: parent.width
                            spacing: 3
                            Text {
                                textFormat: Text.PlainText
                                visible: bubbleRow.stamp
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                topPadding: bubbleRow.index > 0 ? 6 : 0
                                text: root.clock(bubbleRow.modelData.ts)
                                color: Theme.t3
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                            Text {
                                textFormat: Text.PlainText
                                visible: bubbleRow.showSender
                                x: 4
                                text: bubbleRow.modelData.from ? (bubbleRow.modelData.from.name || "") : ""
                                color: Theme.t3
                                font.family: Theme.fontUi
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                            Item {
                                width: parent.width
                                height: bubble.height
                                Squircle {
                                    id: bubble
                                    x: bubbleRow.outgoing ? parent.width - width : 0
                                    width: Math.min(bubbles.width * 0.78, label.implicitWidth + 28)
                                    height: label.implicitHeight + 16
                                    radius: 17
                                    color: bubbleRow.outgoing ? Theme.fillOn : Theme.inkRaised2
                                    Text {
                                        textFormat: Text.PlainText
                                        id: label
                                        anchors.centerIn: parent
                                        width: bubble.width - 28
                                        text: bubbleRow.modelData.text || ""
                                        wrapMode: Text.Wrap
                                        color: bubbleRow.outgoing ? Theme.glyphOn : Theme.t1
                                        font.family: Theme.fontUi
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }
                    }
                }

                Text {

                    textFormat: Text.PlainText
                    Layout.fillWidth: true
                    visible: root.sendError.length > 0
                    text: root.sendError
                    elide: Text.ElideRight
                    color: Qt.rgba(1, 0.271, 0.227, 0.8)
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                }

                Squircle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(96, Math.max(36, composer.implicitHeight + 16))
                    radius: 18
                    color: Theme.inkRaised

                    TextEdit {
                        id: composer
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        wrapMode: TextEdit.Wrap
                        color: Theme.t1
                        selectionColor: Theme.fillOn
                        selectedTextColor: Theme.glyphOn
                        font.family: Theme.fontUi
                        font.pixelSize: 14
                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    && !(event.modifiers & Qt.ShiftModifier)) {
                                event.accepted = true
                                root.sendMessage()
                            }
                        }
                    }
                    Text {
                        textFormat: Text.PlainText
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        visible: composer.text.length === 0
                        text: "Message"
                        color: Theme.t3
                        font.family: Theme.fontUi
                        font.pixelSize: 14
                    }
                }
            }
        }

        Text {

            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: "Shows messages received while your iPhone is nearby."
            color: Theme.t3
            font.family: Theme.fontUi
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }
}
