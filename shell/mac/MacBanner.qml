import QtQuick
import QtQuick.Layouts
import "../core"
import "../components"
import "../services"
import "MacFormat.js" as Fmt

/**
 * MacBanner -- one Tahoe notification banner (spec 3.1). Presentation and
 * motion only. MacBanners owns the stack, the service calls and the window.
 *
 * Geometry: the item is the window content. The glass sits at x = pad, and
 * `pad` leaves room for the TahoeGlass shadow inside the layer surface.
 *
 * Signals: activated() on a body click; exited() once the exit motion has
 * finished (the parent then removes the row). Close (X) and swipe only hide
 * the banner. The notification stays in NotificationService.history.
 */
Item {
    id: root

    property var entry: null
    readonly property bool critical: root.entry?.critical ?? false
    property real nowMs: Date.now()

    // Room for the QML shadow only. Under the compositor glass plugin there is
    // no QML shadow, so the window is exactly the card.
    readonly property real pad: MacTokens.compositorGlass ? 0
        : Math.ceil(MacTokens.s(MacTokens.surfaceShadowBlur)
            + Math.abs(MacTokens.s(MacTokens.surfaceShadowY)) + 2)
    readonly property real bodyWidth: MacTokens.s(MacTokens.bannerWidth)
    readonly property real bodyHeight: MacTokens.s(MacTokens.bannerHeight)
    readonly property real insetRight: MacTokens.s(MacTokens.bannerInsetRight)
    // The right inset is the layer margin (MacBannerWindow), not window width.
    readonly property real slide: root.bodyWidth + root.pad
    readonly property alias bodyItem: body

    // 0 = off the right edge, 1 = resting.
    property real shown: 0
    property real dragX: 0
    property bool leaving: false
    property real remainingMs: Config.notifications.timeout
    // A banner held behind the front stack keeps its time until it comes forward.
    property bool held: false
    readonly property bool paused: hover.hovered || swipe.active || root.held

    implicitWidth: root.pad + root.bodyWidth
    implicitHeight: root.bodyHeight + root.pad
    width: implicitWidth
    height: implicitHeight

    signal activated()
    // The user closed the banner (X or swipe). Timeouts do not emit it.
    signal dismissed()
    // A notification action button (index into NotificationService.visibleActions).
    signal actionInvoked(int index)
    signal exited()

    function enter(): void {
        root.leaving = false
        motion.from = root.shown
        motion.to = 1
        motion.restart()
    }

    function leave(): void {
        if (root.leaving)
            return
        root.leaving = true
        motion.from = root.shown
        motion.to = 0
        motion.restart()
    }

    NumberAnimation {
        id: motion
        target: root
        property: "shown"
        duration: root.leaving ? MacTokens.bannerSlideOutMs : MacTokens.bannerSlideInMs
        easing.type: root.leaving ? Easing.InCubic : Easing.OutCubic
        onFinished: {
            if (root.leaving)
                root.exited()
        }
    }

    NumberAnimation {
        id: snapBack
        target: root
        property: "dragX"
        to: 0
        duration: MacTokens.bannerSlideOutMs
        easing.type: Easing.OutCubic
    }

    Component.onCompleted: root.enter()

    // Relative time refreshes while the banner is up.
    Timer {
        interval: 30000
        running: !root.leaving
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    // Timeout: pauses while the pointer is over the banner or it is swiped.
    Timer {
        interval: MacTokens.bannerTimeoutTick
        repeat: true
        running: !root.leaving && !root.critical && !root.paused && root.shown >= 1
        onTriggered: {
            root.remainingMs -= interval
            if (root.remainingMs <= 0)
                root.leave()
        }
    }

    Item {
        id: body
        x: root.pad + (1 - root.shown) * root.slide + root.dragX
        y: 0
        width: root.bodyWidth
        height: root.bodyHeight
        opacity: root.shown

        // Opaque ink, like the island and control centre (owner, 21 Oct: the
        // frosted glass banner read cheap, muddy and aliased over dark windows).
        Squircle {
            anchors.fill: parent
            color: Theme.ink
            borderWidth: 1
            borderColor: Theme.inkRim
            radius: MacTokens.s(MacTokens.bannerRadius)
        }

        MacAvatar {
            id: avatar
            anchors.left: parent.left
            anchors.leftMargin: MacTokens.s(MacTokens.bannerPad)
            anchors.verticalCenter: parent.verticalCenter
            entry: root.entry
            size: MacTokens.s(MacTokens.bannerIconSize)
        }

        ColumnLayout {
            anchors.left: avatar.right
            anchors.leftMargin: MacTokens.s(MacTokens.bannerPad)
            anchors.right: parent.right
            anchors.rightMargin: MacTokens.s(MacTokens.bannerPad)
            anchors.verticalCenter: parent.verticalCenter
            spacing: MacTokens.s(MacTokens.bannerTextGap)

            RowLayout {
                Layout.fillWidth: true
                spacing: MacTokens.s(MacTokens.bannerPad) / 2

                Text {
                    Layout.fillWidth: true
                    text: root.entry?.title || "Notification"
                    textFormat: Text.PlainText   // notification text is untrusted: no markup, no remote <img>
                    color: Theme.t1
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: MacTokens.textFamily
                    font.pixelSize: MacTokens.s(MacTokens.bannerTitleSize)
                    font.weight: Font.DemiBold
                }

                Text {
                    opacity: hover.hovered ? 0 : 1
                    text: Fmt.ageText(root.entry?.timestamp ?? root.nowMs, root.nowMs)
                    color: Theme.t3
                    font.family: MacTokens.textFamily
                    font.pixelSize: MacTokens.s(MacTokens.bannerTimeSize)
                    font.weight: Font.Medium
                }
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.entry?.body || ""
                textFormat: Text.PlainText   // notification text is untrusted: no markup, no remote <img>
                color: Theme.t2
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                // One line when the action buttons take the bottom row.
                maximumLineCount: actions.visible ? 1 : 2
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(MacTokens.bannerBodySize)
            }

            MacNotificationActions {
                id: actions
                Layout.topMargin: MacTokens.s(MacTokens.bannerTextGap)
                entry: root.entry
                onInvoked: index => root.actionInvoked(index)
            }
        }

        Text {
            id: closeGlyph
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: MacTokens.s(MacTokens.bannerPad) / 2
            anchors.rightMargin: MacTokens.s(MacTokens.bannerPad) / 2
            // Tahoe shows the close control on hover only.
            opacity: hover.hovered ? 1 : 0
            text: "×"
            color: closeHover.hovered ? Theme.t1 : Theme.t3
            font.family: MacTokens.textFamily
            font.pixelSize: MacTokens.s(MacTokens.ncCloseGlyphSize)

            HoverHandler { id: closeHover }
            TapHandler {
                onTapped: {
                    root.dismissed()
                    root.leave()
                }
            }
        }

        HoverHandler { id: hover }

        DragHandler {
            id: swipe
            target: null
            xAxis.enabled: true
            yAxis.enabled: false
            onTranslationChanged: root.dragX = Math.max(0, translation.x)
            onActiveChanged: {
                if (active)
                    return
                if (root.dragX > root.bodyWidth * MacTokens.bannerSwipeFraction) {
                    root.dismissed()
                    root.leave()
                } else {
                    snapBack.restart()
                }
            }
        }

        // The body click is the default action. Buttons take their own taps.
        TapHandler {
            enabled: !root.leaving && !closeHover.hovered && !actions.hovered
            onTapped: root.activated()
        }
    }
}
