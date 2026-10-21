import QtQuick
import QtQuick.Layouts
import "../core"
import "../components"
import "MacFormat.js" as Fmt

/**
 * MacCompose -- the New Message sheet at the top of the Notification Center.
 * Pick a contact (PhoneService.findContacts, the read-only BlueFerry cache) or
 * type a number, write the text and press Send. Nothing is sent without that
 * press. Send goes through PhoneService.send, the same path as the reply.
 *
 * `recipient` is {name, number}. The Spotlight "message <name>" result sets it
 * through setRecipient(); the owner calls reset() when the sheet opens fresh.
 */
Item {
    id: root

    // PhoneService, or a stand-in with findContacts(query, cb) and send(number, text, cb).
    property var phone: PhoneService
    property var recipient: null
    property string query: ""
    property var hits: []
    property string status: ""
    property bool sending: false
    // The message text (plain text). Exposed for tests and the owner.
    property alias draft: body.text
    readonly property real pad: MacTokens.s(MacTokens.bannerPad)
    readonly property bool canSend: !!root.recipient && !root.sending && body.text.trim().length > 0

    // Stale contact answers are dropped: only the newest search may fill hits.
    property int searchSeq: 0

    signal closeRequested()

    implicitWidth: MacTokens.s(MacTokens.ncColumnWidth)
    implicitHeight: card.height
    width: implicitWidth
    height: implicitHeight

    function setRecipient(target): void {
        root.recipient = { name: String(target?.name || ""), number: String(target?.number || "") }
        root.query = ""
        root.hits = []
        root.status = ""
    }

    function reset(): void {
        root.recipient = null
        root.query = ""
        root.hits = []
        root.status = ""
        root.sending = false
        body.text = ""
        field.text = ""
    }

    function pick(hit): void {
        root.setRecipient(hit)
        body.forceActiveFocus()
    }

    function search(): void {
        const text = root.query.trim()
        const seq = ++root.searchSeq
        if (text.length === 0) {
            root.hits = []
            return
        }
        root.phone.findContacts(text, result => {
            if (seq !== root.searchSeq)
                return
            if (!(result && result.ok === true)) {
                root.hits = Fmt.looksLikeNumber(text) ? [{ name: text, number: text }] : []
                root.status = (result && result.error) || "Contacts unavailable"
                return
            }
            const typed = Fmt.looksLikeNumber(text) ? [{ name: text, number: text }] : []
            root.hits = typed.concat(result.contacts || []).slice(0, 4)
        })
    }

    function send(): void {
        if (!root.canSend)
            return
        const text = body.text.trim()
        root.sending = true
        root.status = "Sending"
        root.phone.send(root.recipient.number, text, result => {
            root.sending = false
            if (result && result.ok === true) {
                body.text = ""
                root.status = "Sent"
            } else {
                root.status = (result && result.error) || "Message not sent"
            }
        })
    }

    Timer {
        id: searchDelay
        interval: 200
        repeat: false
        onTriggered: root.search()
    }

    onVisibleChanged: {
        if (visible && !root.recipient)
            Qt.callLater(() => field.forceActiveFocus())
    }

    Squircle {
        id: card
        width: parent.width
        height: content.implicitHeight + 2 * root.pad
        color: Theme.ink
        borderWidth: 1
        borderColor: Theme.inkRim
        radius: MacTokens.s(MacTokens.ncWidgetRadius)

        // Escape closes the sheet, not the whole Notification Center.
        Keys.onEscapePressed: event => {
            root.closeRequested()
            event.accepted = true
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: MacTokens.s(MacTokens.bannerTextGap) * 4

            RowLayout {
                Layout.fillWidth: true
                spacing: root.pad / 2

                Text {
                    textFormat: Text.PlainText   // app action labels / contact names are untrusted
                    Layout.fillWidth: true
                    text: "New Message"
                    color: MacTokens.labelPrimary
                    font.family: MacTokens.textFamily
                    font.pixelSize: MacTokens.s(MacTokens.bannerTitleSize)
                    font.weight: Font.DemiBold
                }

                Text {
                    textFormat: Text.PlainText   // app action labels / contact names are untrusted
                    text: "×"
                    color: closeHover.hovered ? MacTokens.labelPrimary : MacTokens.labelSecondary
                    font.family: MacTokens.textFamily
                    font.pixelSize: MacTokens.s(MacTokens.ncCloseGlyphSize)
                    HoverHandler { id: closeHover }
                    TapHandler { onTapped: root.closeRequested() }
                }
            }

            // To: a field while there is no recipient, the chosen contact after.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: MacTokens.s(28)
                radius: MacTokens.s(8)
                color: MacTokens.onSurface(0.08)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.pad / 2
                    anchors.rightMargin: root.pad / 2
                    spacing: root.pad / 2

                    Text {
                        textFormat: Text.PlainText   // app action labels / contact names are untrusted
                        text: "To"
                        color: MacTokens.labelSecondary
                        font.family: MacTokens.textFamily
                        font.pixelSize: MacTokens.s(MacTokens.ncGroupLabelSize)
                        font.weight: Font.Medium
                    }

                    TextInput {
                        id: field
                        Layout.fillWidth: true
                        visible: !root.recipient
                        color: MacTokens.labelPrimary
                        selectionColor: MacTokens.accentBlue
                        selectedTextColor: MacTokens.accentOn
                        clip: true
                        font.family: MacTokens.textFamily
                        font.pixelSize: MacTokens.s(MacTokens.bannerBodySize)
                        onTextChanged: {
                            root.query = text
                            searchDelay.restart()
                        }
                        Keys.onReturnPressed: event => {
                            if (root.hits.length > 0)
                                root.pick(root.hits[0])
                            event.accepted = true
                        }
                        Keys.onEscapePressed: event => {
                            root.closeRequested()
                            event.accepted = true
                        }

                        Text {
                            textFormat: Text.PlainText   // app action labels / contact names are untrusted
                            anchors.verticalCenter: parent.verticalCenter
                            visible: field.text.length === 0
                            text: "Name or number"
                            color: MacTokens.labelSecondary
                            font: field.font
                        }
                    }

                    Text {
                        textFormat: Text.PlainText   // app action labels / contact names are untrusted
                        Layout.fillWidth: true
                        visible: !!root.recipient
                        text: root.recipient ? root.recipient.name : ""
                        color: MacTokens.labelPrimary
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: MacTokens.textFamily
                        font.pixelSize: MacTokens.s(MacTokens.bannerBodySize)
                        font.weight: Font.DemiBold
                    }

                    Text {
                        textFormat: Text.PlainText   // app action labels / contact names are untrusted
                        visible: !!root.recipient
                        text: "×"
                        color: clearHover.hovered ? MacTokens.labelPrimary : MacTokens.labelSecondary
                        font.family: MacTokens.textFamily
                        font.pixelSize: MacTokens.s(MacTokens.ncCloseGlyphSize)
                        HoverHandler { id: clearHover }
                        TapHandler {
                            onTapped: {
                                root.recipient = null
                                Qt.callLater(() => field.forceActiveFocus())
                            }
                        }
                    }
                }
            }

            // Contact hits under the To field (newest search only).
            Repeater {
                model: root.recipient ? [] : root.hits

                delegate: Rectangle {
                    id: hitRow
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: MacTokens.s(MacTokens.notifActionHeight) + MacTokens.s(MacTokens.bannerTextGap) * 4
                    radius: MacTokens.s(8)
                    color: hitTap.pressed ? MacTokens.onSurface(0.18)
                        : hitHover.hovered ? MacTokens.onSurface(0.1) : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: root.pad / 2
                        anchors.rightMargin: root.pad / 2
                        spacing: root.pad / 2

                        Text {
                            textFormat: Text.PlainText   // app action labels / contact names are untrusted
                            Layout.fillWidth: true
                            text: hitRow.modelData.name
                            color: MacTokens.labelPrimary
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.family: MacTokens.textFamily
                            font.pixelSize: MacTokens.s(MacTokens.bannerBodySize)
                            font.weight: Font.Medium
                        }

                        Text {
                            textFormat: Text.PlainText   // app action labels / contact names are untrusted
                            text: hitRow.modelData.number
                            color: MacTokens.labelSecondary
                            elide: Text.ElideLeft
                            maximumLineCount: 1
                            font.family: MacTokens.textFamily
                            font.pixelSize: MacTokens.s(MacTokens.ncGroupLabelSize)
                        }
                    }

                    HoverHandler { id: hitHover }
                    TapHandler {
                        id: hitTap
                        onTapped: root.pick(hitRow.modelData)
                    }
                }
            }

            // The text. Plain text only; nothing here is rendered as rich text.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: MacTokens.s(56)
                radius: MacTokens.s(8)
                color: MacTokens.onSurface(0.08)

                TextEdit {
                    id: body
                    anchors.fill: parent
                    anchors.margins: root.pad / 2
                    color: MacTokens.labelPrimary
                    selectionColor: MacTokens.accentBlue
                    selectedTextColor: MacTokens.accentOn
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    clip: true
                    font.family: MacTokens.textFamily
                    font.pixelSize: MacTokens.s(MacTokens.bannerBodySize)
                    Keys.onEscapePressed: event => {
                        root.closeRequested()
                        event.accepted = true
                    }

                    Text {
                        textFormat: Text.PlainText   // app action labels / contact names are untrusted
                        visible: body.text.length === 0
                        text: "Message"
                        color: MacTokens.labelSecondary
                        font: body.font
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.pad / 2

                Text {
                    textFormat: Text.PlainText   // app action labels / contact names are untrusted
                    Layout.fillWidth: true
                    text: root.status
                    color: root.status === "Sent" ? MacTokens.labelSecondary : MacTokens.criticalFill
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: MacTokens.textFamily
                    font.pixelSize: MacTokens.s(MacTokens.ncGroupLabelSize)
                    font.weight: Font.Medium
                }

                // Send only ever runs on this press; nothing is sent automatically.
                Rectangle {
                    id: sendButton
                    Layout.preferredHeight: MacTokens.s(MacTokens.notifActionHeight) + MacTokens.s(4)
                    Layout.preferredWidth: sendLabel.implicitWidth + 2 * MacTokens.s(MacTokens.ncPillPadX) + MacTokens.s(8)
                    radius: height / 2
                    color: root.canSend ? MacTokens.accentBlue : MacTokens.onSurface(0.12)
                    opacity: root.canSend || root.sending ? 1 : 0.6

                    Text {
                        textFormat: Text.PlainText   // app action labels / contact names are untrusted
                        id: sendLabel
                        anchors.centerIn: parent
                        text: "Send"
                        color: root.canSend ? MacTokens.accentOn : MacTokens.labelSecondary
                        font.family: MacTokens.textFamily
                        font.pixelSize: MacTokens.s(MacTokens.notifActionTextSize)
                        font.weight: Font.DemiBold
                    }

                    TapHandler {
                        id: sendTap
                        enabled: root.canSend
                        onTapped: root.send()
                    }
                }
            }
        }
    }
}
