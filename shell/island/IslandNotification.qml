import QtQuick
import QtQuick.Layouts
import Quickshell
import "../components"
import "../core"
import "../services"

/**
 * IslandNotification -- the transient notification popup. Shares
 * components/NotificationAvatar.qml with panels/NotificationCard.qml so the
 * two cannot drift, and carries its own countdown: a single NumberAnimation
 * on `progress` is the ONE source of truth for when the popup expires (see
 * island/IslandController.qml's requestTransient(), which deliberately does
 * NOT restart its own transientTimer for the "notification" kind any more,
 * so nothing else races this to a second, possibly-earlier dismissal).
 *
 * `service` and `controller` are both overridable at instantiation -- same
 * pattern as panels/PolkitPage.qml's `controller` -- so test-notification-
 * countdown.qml can drive this against mocks without ever touching the real
 * NotificationService singleton (which would otherwise try to register a
 * live D-Bus notification server) or a real IslandController.
 */
Item {
    id: root

    property var service: NotificationService
    // The hosting island/IslandController.qml instance -- only used for
    // expireTransientNotification()/visualState/notification, never for
    // notification content.
    property var controller: null
    // Testability seam only, mirroring panels/PolkitPage.qml's documented
    // seams: fakes "hovered" for test-notification-countdown.qml without a
    // real pointer event.
    property bool testHovered: false

    readonly property var currentEntry: (root.service ? root.service.current : null)
        || (PreviewService.enabled && PreviewService.notificationPreviewing
            ? PreviewService.notificationEntry : null)
    // The service clears `current` before it announces a natural timeout.
    // Keep the last displayed entry only for the shared closing fade so every
    // exit looks like the reverse of the established arrival animation.
    property var retainedEntry: null
    readonly property var entry: currentEntry || retainedEntry
    readonly property bool critical: root.entry?.critical ?? false
    readonly property var visibleActions: root.service && root.entry
        ? root.service.visibleActions(root.entry) : []
    readonly property string primaryActionText: visibleActions.length > 0
        ? root.service.plainText(visibleActions[0].text) : ""

    // Tied to the SAME condition that makes the wrapping Item in
    // island/Island.qml visible/enabled, so the countdown starts exactly
    // when the popup appears and stops exactly when it stops being shown --
    // for ANY reason: natural timeout, a click, or being pre-empted by a
    // higher-priority transient.
    readonly property bool showing: root.controller
        ? root.controller.visualState === root.controller.notification : false
    readonly property int fullDuration: root.critical
        ? Config.notifications.criticalTimeout : Config.notifications.timeout
    property real progress: 1

    function restartCountdown(): void {
        progress = 1
        countdown.restart()
    }

    onCurrentEntryChanged: {
        if (currentEntry) {
            retainedEntry = currentEntry
            restartCountdown()
        }
    }
    onShowingChanged: {
        if (showing)
            restartCountdown()
        else
            countdown.stop()
    }

    NumberAnimation {
        id: countdown
        target: root
        property: "progress"
        from: 1
        to: 0
        duration: root.fullDuration
        // QML's `paused` resumes an animation from where it stopped --
        // never restart on hover exit.
        paused: running && (popupHover.hovered || root.testHovered)
        onFinished: root.controller?.expireTransientNotification()
    }

    HoverHandler { id: popupHover }
    TapHandler {
        enabled: root.currentEntry !== null
        onTapped: {
            if (!root.service?.activate(root.entry))
                root.service?.dismissTransient()
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.u(0.26)
        // Ink: the showcase toast pads 18px left and 20px right, no vertical pad.
        anchors.leftMargin: Config.appearance.ink ? 18 : Theme.u(0.26)
        anchors.rightMargin: Config.appearance.ink ? 20 : Theme.u(0.26)
        anchors.topMargin: Config.appearance.ink ? 0 : Theme.u(0.26)
        anchors.bottomMargin: Config.appearance.ink ? 0 : Theme.u(0.26)
        spacing: Config.appearance.ink ? 14 : Theme.u(0.24)

        NotificationAvatar {
            Layout.alignment: Config.appearance.ink ? Qt.AlignVCenter : Qt.AlignTop
            entry: root.entry
            size: Config.appearance.ink ? 40 : Theme.u(0.78)
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                // Ink: the app name as written, 12px Medium in t3 (showcase .app).
                text: Config.appearance.ink
                    ? (root.entry?.appName || "Application")
                    : (root.entry?.appName || "Application").toUpperCase()
                color: Config.appearance.ink ? Theme.t3
                    : (root.critical ? Theme.error : Theme.outline)
                elide: Text.ElideRight
                font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.monoFontFamily
                // DisplayScale.primary: bare literal alongside otherwise
                // Theme-token-driven sizing elsewhere in this file.
                font.pixelSize: Config.appearance.ink ? 12 : Math.round(10 * DisplayScale.primary)
                font.weight: Config.appearance.ink ? Font.Medium : Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: root.entry?.title || "Notification"
                textFormat: Text.PlainText   // notification text is untrusted: no markup, no remote <img>
                color: Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                font.pixelSize: Config.appearance.ink ? 15 : Theme.textBody
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.entry?.body || ""
                textFormat: Text.PlainText   // notification text is untrusted: no markup, no remote <img>
                color: Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                font.pixelSize: Config.appearance.ink ? 13 : Theme.textSmall
                font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
            }

            // The primary action is a text link, as in panels/NotificationCard.qml.
            Text {
                Layout.fillWidth: true
                visible: root.primaryActionText.length > 0
                text: root.primaryActionText
                color: Config.appearance.ink
                    ? (actionHover.hovered ? Theme.t2 : Theme.t1)
                    : (actionHover.hovered ? AdaptiveColor.glassText : AdaptiveColor.activeFill)
                elide: Text.ElideRight
                font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily
                font.pixelSize: Config.appearance.ink ? 13 : Theme.textSmall
                font.weight: Font.DemiBold

                HoverHandler { id: actionHover }
                TapHandler { onTapped: root.service?.invokeAction(root.entry, 0) }
            }

            Item { Layout.fillHeight: true }

            // Countdown bar -- inset to this text column (starts at the
            // text's x, ends at the popup's right padding) by simply being a
            // fillWidth sibling inside it, no manual x math needed.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 3
                radius: 1.5
                color: Config.appearance.ink ? Theme.inkRaised2 : Theme.surfaceContainerHigh

                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.progress))
                    height: parent.height
                    radius: parent.radius
                    color: Config.appearance.ink ? Theme.fillOn
                        : (root.critical ? Theme.error : AdaptiveColor.activeFill)
                }
            }
        }
    }
}
