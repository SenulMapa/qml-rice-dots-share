import QtQuick
import QtQuick.Layouts
import "../core"
import "../components"
import "../services"
import "MacFormat.js" as Fmt

/**
 * MacNotificationCard -- one notification in the Notification Center (spec 3.3,
 * owner spec 21 Oct). An ink squircle: app icon, a title line with the relative
 * time at its top right, and up to four lines of body. A close circle hangs off
 * the top-left corner on hover. The body click activates it, as in the banner.
 */
Item {
    id: root

    required property var entry
    // False on the top card of a collapsed stack: a tap there expands the stack.
    property bool activatable: true
    // Time the relative age is measured from.
    property real nowMs: Date.now()
    // Room the stack's group pills take over this card's top right. While set,
    // the title keeps clear of them and the relative time is hidden under them.
    property real headerInset: 0

    readonly property bool hasPrimary: NotificationService.canActivate(root.entry)
        || NotificationService.visibleActions(root.entry).length > 0
    // Actions other than "default" get a row of their own under the text. The
    // buttons are not built here; the row is only reserved.
    readonly property bool hasActionRow: NotificationService.visibleActions(root.entry)
        .some(action => action?.identifier !== "default")
    readonly property real actionRowHeight: hasActionRow ? MacTokens.s(MacTokens.ncCardActionRow) : 0
    readonly property real contentTop: Math.max(MacTokens.s(MacTokens.ncCardPadY),
        (root.height - root.actionRowHeight - content.implicitHeight) / 2)

    signal activated()

    implicitWidth: MacTokens.s(MacTokens.ncColumnWidth)
    height: implicitHeight
    implicitHeight: Math.max(MacTokens.s(MacTokens.ncCardMinHeight),
        content.implicitHeight + MacTokens.s(MacTokens.ncCardPadY) * 2 + root.actionRowHeight)

    HoverHandler { id: cardHover }

    TahoeSurface {
        anchors.fill: parent
        kind: "nc"
        tintAlpha: MacTokens.frostTintAlpha
        radius: MacTokens.s(MacTokens.ncCardRadius)
    }

    MacAvatar {
        id: avatar
        anchors.left: parent.left
        anchors.leftMargin: MacTokens.s(MacTokens.ncCardPadX)
        y: root.contentTop
        entry: root.entry
        size: MacTokens.s(MacTokens.ncCardIconSize)
        imageRadius: MacTokens.s(MacTokens.ncCardIconRadius)
        fallbackFill: MacTokens.ncCardIconFill
        fallbackText: Theme.t1
    }

    ColumnLayout {
        id: content
        anchors.left: avatar.right
        anchors.leftMargin: MacTokens.s(MacTokens.ncCardIconGap)
        anchors.right: parent.right
        anchors.rightMargin: MacTokens.s(MacTokens.ncCardPadX)
        y: root.contentTop
        spacing: MacTokens.s(MacTokens.ncCardTextGap)

        RowLayout {
            Layout.fillWidth: true
            spacing: MacTokens.s(MacTokens.ncCardTimeGap)

            Text {
                id: title
                Layout.fillWidth: true
                Layout.rightMargin: root.headerInset
                text: root.entry?.title || "Notification"
                textFormat: Text.PlainText   // notification text is untrusted: no markup, no remote <img>
                color: Theme.t1
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(MacTokens.ncCardTitleSize)
                font.weight: Font.DemiBold
            }

            Text {
                visible: root.headerInset === 0
                text: Fmt.ageText(root.entry?.timestamp ?? root.nowMs, root.nowMs)
                color: Theme.t3
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(MacTokens.ncCardTimeSize)
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
            maximumLineCount: MacTokens.ncCardBodyLines
            font.family: MacTokens.textFamily
            font.pixelSize: MacTokens.s(MacTokens.ncCardBodySize)
        }

        MacNotificationActions {
            id: actions
            Layout.topMargin: MacTokens.s(MacTokens.bannerTextGap)
            entry: root.entry
            onInvoked: index => NotificationService.invokeAction(root.entry, index)
        }
    }

    // Hover close: an 18 pt circle hung off the top-left corner, like macOS.
    Squircle {
        id: closeButton
        x: MacTokens.s(MacTokens.ncCardCloseOffset)
        y: MacTokens.s(MacTokens.ncCardCloseOffset)
        width: MacTokens.s(MacTokens.ncCardCloseSize)
        height: width
        radius: width / 2
        color: Theme.inkRaised2
        borderWidth: 1
        borderColor: MacTokens.ncCardCloseBorder
        visible: cardHover.hovered || closeHover.hovered
        z: 1

        Text {
            anchors.centerIn: parent
            text: "×"
            color: MacTokens.labelSecondary
            font.family: MacTokens.textFamily
            font.pixelSize: MacTokens.s(MacTokens.ncCardCloseGlyph)
        }

        HoverHandler { id: closeHover }
        TapHandler { onTapped: NotificationService.remove(root.entry) }
    }

    // The body click is the default action only. Other actions have buttons.
    TapHandler {
        enabled: root.activatable && NotificationService.canActivate(root.entry)
            && !closeHover.hovered && !actions.hovered
        onTapped: NotificationService.activate(root.entry)
    }
}
