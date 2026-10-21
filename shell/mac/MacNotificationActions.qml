import QtQuick
import "../core"
import "../components"
import "../services"

/**
 * MacNotificationActions -- a notification's action buttons as small ink pills
 * (iPhone ANCS Accept / Decline / Retry, or an app's own actions). Shown by
 * MacBanner and MacNotificationCard. The "default" action has no label, so
 * visibleActions() drops it: a body click stays the default action.
 *
 * `invoked(index)` gives the index into NotificationService.visibleActions(entry);
 * the owner calls NotificationService.invokeAction with it. `hovered` lets the
 * owner keep its body tap off while the pointer is on a button.
 */
Item {
    id: root

    property var entry: null
    readonly property var actions: NotificationService.visibleActions(root.entry)
    readonly property bool hovered: rowHover.hovered

    signal invoked(int index)

    visible: root.actions.length > 0
    // Explicit implicit sizes: a layout parent sizes this Item from them.
    implicitWidth: buttons.width
    implicitHeight: root.visible ? MacTokens.s(MacTokens.notifActionHeight) : 0
    width: implicitWidth
    height: implicitHeight

    HoverHandler { id: rowHover }

    Row {
        id: buttons
        spacing: MacTokens.s(MacTokens.notifActionGap)

        Repeater {
            model: root.actions

            delegate: Squircle {
                id: pill
                required property int index
                required property var modelData

                height: MacTokens.s(MacTokens.notifActionHeight)
                width: label.implicitWidth + 2 * MacTokens.s(MacTokens.notifActionPadX)
                radius: height / 2
                color: tap.pressed ? MacTokens.notifActionPressed : MacTokens.notifActionFill

                Text {
                    textFormat: Text.PlainText   // app action labels / contact names are untrusted
                    id: label
                    anchors.centerIn: parent
                    text: NotificationService.plainText(pill.modelData.text || "")
                    color: MacTokens.labelPrimary
                    font.family: MacTokens.textFamily
                    font.pixelSize: MacTokens.s(MacTokens.notifActionTextSize)
                    font.weight: Font.DemiBold
                }

                TapHandler {
                    id: tap
                    onTapped: root.invoked(pill.index)
                }
            }
        }
    }
}
