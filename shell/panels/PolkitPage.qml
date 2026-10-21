import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"
import "../components"

/**
 * PolkitPage -- the polkit authentication dialog. Hosted once in
 * island/IslandExpanded.qml as page "polkit", exactly like every other page.
 *
 * `controller` is whichever of PolkitService (real) / PolkitPreviewService
 * (QMLRICE_POLKIT_PREVIEW=1 only) currently has a live/staged request -- both
 * expose the identical surface this file reads, so nothing below branches on
 * which one is active. Preview takes priority only because it is the only
 * one that can be "active" on a machine with no live pkexec request; the two
 * are mutually exclusive in practice (see services/PolkitPreviewService.qml).
 *
 * FAIL CLOSED is enforced one level up: island/Island.qml calls
 * controller.cancel() whenever the island dismisses while this page is open
 * (Escape, click-away/focus-grab-cleared, or any other dismiss path all go
 * through IslandController.dismiss()), and closes this page automatically
 * when `controller.active` goes false (flow completed or cancelled
 * externally).
 */
Item {
    id: root

    // Plain (not readonly): overridable at instantiation, which is how
    // test-polkit.qml drives this page against a mock controller instead of
    // the real services.
    property var controller:
        PolkitPreviewService.previewing ? PolkitPreviewService : PolkitService
    readonly property alias contentHeight: mainColumn.implicitHeight
    readonly property bool hasIdentityChoice: controller.identities.length > 1
    readonly property bool canAuthenticate:
        !controller.busy && passwordField.text.length > 0

    // Testability seams for test-polkit.qml only -- panels/PolkitPage.qml
    // has no other externally-visible way to inspect or drive the password
    // field, since it is a private id.
    property alias fieldText: passwordField.text
    readonly property alias fieldEnabled: passwordField.enabled
    readonly property alias fieldEchoMode: passwordField.echoMode

    function clearField(): void {
        passwordField.text = ""
    }

    function trySubmit(): void {
        if (!root.canAuthenticate)
            return
        const text = passwordField.text
        clearField()
        controller.submit(text)
    }

    function doCancel(): void {
        clearField()
        controller.cancel()
    }

    // A stable comparison key rather than `===`: a plain-JS-array model (as
    // services/PolkitPreviewService.qml uses) hands each delegate a COPY of
    // its object through Repeater's model marshalling, not the original
    // reference -- confirmed empirically (a Repeater over a literal JS array
    // never satisfies `modelData === array[i]` for the SAME logical entry).
    // AuthFlow's real `identities` are QObject pointers, which DO survive
    // that marshalling intact, so this key-based compare is a superset that
    // works for both rather than something papering over a real-flow-only bug.
    function identityKey(identity): string {
        return identity ? (identity.displayName || identity.string || "") : ""
    }

    onVisibleChanged: {
        if (visible) {
            clearField()
            Qt.callLater(() => passwordField.forceActiveFocus())
        } else {
            clearField()
        }
    }

    // Local, direct handling in addition to the island-level FAIL CLOSED net
    // (island/Island.qml cancels through IslandController.dismiss() for
    // click-away etc.): catches Escape immediately whenever this page's own
    // field has focus, without waiting for that dismiss() round-trip.
    // Calling controller.cancel() twice (this, then the island's own net) is
    // safe -- both PolkitService.cancel() and PolkitPreviewService.cancel()
    // are no-ops/idempotent once there is nothing left to cancel.
    Keys.onEscapePressed: root.doCancel()

    // Re-enable and refocus the field the moment a failed attempt clears
    // `busy` -- covers "wrong password: ... re-enable input and refocus the
    // field" without duplicating the busy->false transition logic here.
    Connections {
        target: root.controller
        function onBusyChanged(): void {
            if (!root.controller.busy && root.visible)
                Qt.callLater(() => passwordField.forceActiveFocus())
        }
    }

    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        // Same Phase A remainder-padding convention as panels/ControlCenter.qml:
        // IslandExpanded's outer ColumnLayout already insets every page by
        // Theme.space4; this tops that up to Theme.u(0.555) on the sides.
        anchors.leftMargin: Math.max(0, Theme.u(0.555) - Theme.space4)
        anchors.rightMargin: Math.max(0, Theme.u(0.555) - Theme.space4)
        spacing: Theme.u(0.28)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.u(0.3)

            // A bare glyph -- no filled circle behind it.
            Text {
                Layout.alignment: Qt.AlignTop
                text: "󰌾"
                color: (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText)
                font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                font.pixelSize: Theme.u(0.44)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.u(0.06)

                // A short serif HEADLINE, not the polkit message itself --
                // a long message used to make the whole thing a two-line
                // serif wall of text.
                Text {
                    Layout.fillWidth: true
                    text: "Authentication required"
                    color: (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText)
                    font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.displayFontFamily
                    font.pixelSize: Config.appearance.ink ? 20 : Theme.u(0.46)
                    font.weight: Config.appearance.ink ? Font.DemiBold : Font.Normal
                }
                Text {
                    Layout.fillWidth: true
                    text: root.controller.message
                    color: (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText)
                    font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                    font.pixelSize: Config.appearance.ink ? 13 : Theme.textBody
                    font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }
        }

        // Anti-spoofing information: which polkit action is asking for
        // authorization. Always shown, never hidden behind a details toggle.
        TextInput {
            Layout.fillWidth: true
            text: root.controller.actionId
            readOnly: true
            selectByMouse: true
            color: Config.appearance.ink ? Theme.t3 : Theme.outline
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: Theme.u(0.22)
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.hasIdentityChoice
            spacing: Theme.u(0.12)

            Repeater {
                model: root.controller.identities
                delegate: Squircle {
                    id: identityRow
                    required property var modelData
                    readonly property bool isSelected:
                        root.identityKey(modelData)
                            === root.identityKey(root.controller.selectedIdentity)
                    Layout.fillWidth: true
                    implicitHeight: identityLabel.implicitHeight + Theme.u(0.16) * 2
                    radius: Config.appearance.ink ? Theme.rCtl : Theme.u(0.24)
                    color: isSelected ? (Config.appearance.ink ? Theme.fillOn : AdaptiveColor.activeFill)
                        : (Config.appearance.ink ? Theme.inkRaised : Theme.surfaceContainer)

                    Text {
                        id: identityLabel
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.u(0.3)
                        anchors.rightMargin: Theme.u(0.3)
                        text: identityRow.modelData.displayName
                            || identityRow.modelData.string || "Identity"
                        elide: Text.ElideRight
                        color: identityRow.isSelected
                            ? (Config.appearance.ink ? Theme.glyphOn : Theme.accentFillText) : (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText)
                        font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                        font.pixelSize: Theme.u(0.28)
                    }

                    HoverHandler { id: identityHover }
                    TapHandler {
                        onTapped: root.controller.selectIdentity(identityRow.modelData)
                    }
                }
            }
        }

        // Borderless -- only the underline carries this field now: a
        // hairline at rest, the accent colour when focused.
        Item {
            id: passwordFieldBg
            Layout.fillWidth: true
            Layout.preferredHeight: Config.appearance.ink ? 44 : Theme.u(1.0)

            Squircle {
                anchors.fill: parent
                visible: Config.appearance.ink
                radius: Theme.rCtl
                color: Theme.inkRaised
            }

            TextInput {
                id: passwordField
                anchors.fill: parent
                anchors.leftMargin: Config.appearance.ink ? 14 : Theme.u(0.3)
                anchors.rightMargin: Config.appearance.ink ? 14 : Theme.u(0.3)
                verticalAlignment: TextInput.AlignVCenter
                enabled: !root.controller.busy
                color: (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText)
                selectionColor: (Config.appearance.ink ? Theme.fillOn : AdaptiveColor.activeFill)
                selectedTextColor: (Config.appearance.ink ? Theme.glyphOn : AdaptiveColor.activeFillText)
                echoMode: root.controller.echoResponse
                    ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                font.pixelSize: Config.appearance.ink ? 14 : Theme.u(0.3)

                Keys.onReturnPressed: root.trySubmit()
                Keys.onEnterPressed: root.trySubmit()

                Text {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: passwordField.text.length === 0
                    text: root.controller.prompt
                    color: (Config.appearance.ink ? Theme.t3 : AdaptiveColor.glassTextDim)
                    font: passwordField.font
                }
            }

            Rectangle {
                visible: !Config.appearance.ink
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: passwordField.activeFocus ? 2 : 1
                color: passwordField.activeFocus ? (Config.appearance.ink ? Theme.fillOn : AdaptiveColor.activeFill) : Theme.hairline

                Behavior on color { ColorAnimation { duration: Animations.fast } }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.controller.errorText.length > 0
            text: root.controller.errorText
            color: root.controller.errorIsError ? Theme.error : (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
            font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
            font.pixelSize: Theme.u(0.26)
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.u(0.4)

            Item { Layout.fillWidth: true }

            Text {
                text: "Cancel"
                color: cancelHover.hovered ? (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText) : (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
                font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                font.pixelSize: Config.appearance.ink ? 13 : Theme.u(0.3)
                font.weight: Config.appearance.ink ? Font.DemiBold : Font.Medium

                HoverHandler { id: cancelHover }
                TapHandler { onTapped: root.doCancel() }
            }

            Rectangle {
                Layout.preferredWidth: authenticateLabel.implicitWidth + (Config.appearance.ink ? 40 : Theme.u(0.7))
                Layout.preferredHeight: Config.appearance.ink ? 36 : Theme.u(0.8)
                radius: height / 2
                opacity: root.canAuthenticate ? 1 : 0.42
                color: (Config.appearance.ink ? Theme.fillOn : AdaptiveColor.activeFill)

                Text {
                    id: authenticateLabel
                    anchors.centerIn: parent
                    text: "Authenticate"
                    color: (Config.appearance.ink ? Theme.glyphOn : Theme.accentFillText)
                    font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                    font.pixelSize: Config.appearance.ink ? 13 : Theme.u(0.3)
                    font.weight: Font.DemiBold
                }

                TapHandler {
                    enabled: root.canAuthenticate
                    onTapped: root.trySubmit()
                }
            }
        }
    }
}
