import QtQuick
import QtQuick.Layouts
import Quickshell
import "../core"
import "../components"
import "../services"

/**
 * NotificationCard - shared by the control-centre mini list (latest 3) and
 * the full NotificationCenter page, so restyling it once reaches both.
 * Letter avatar (or the app icon, when one loads), uppercase app name, a
 * Geist Mono app id, and a top-right dismiss glyph -- no border, matching
 * the prototype's card. Critical urgency and the primary/named actions
 * dropped by the restyle are restored below without reintroducing a border:
 * critical notifications get an error-filled avatar and app-name line, and
 * the card body itself carries the primary action (same as before this
 * restyle), with named non-default actions as a row of text links.
 */
Squircle {
    id: root

    required property var entry
    readonly property bool critical: entry?.critical ?? false
    readonly property bool hasBody: (entry?.body || "").length > 0
    readonly property var visibleActions: NotificationService.visibleActions(entry)
    // canActivate() only covers a live window-focus origin or a true
    // freedesktop "default" action; a notification with only NAMED actions
    // (no "default") used to still get a primary tap target -- the old
    // card's dedicated button, calling invokeAction(entry, 0). Restoring
    // that as a fallback on the body tap keeps both paths reachable without
    // a bordered button the new card has no room for.
    readonly property bool hasPrimaryAction: NotificationService.canActivate(entry)
        || root.visibleActions.length > 0

    implicitHeight: Math.max(Theme.u(1.64), contentColumn.implicitHeight + Theme.u(0.36))
    radius: Theme.u(0.34)
    color: cardHover.hovered && root.hasPrimaryAction
        ? Theme.surfaceContainerHigh : Theme.surfaceContainer

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.u(0.26)
        spacing: Theme.u(0.24)

        NotificationAvatar {
            Layout.alignment: Qt.AlignTop
            entry: root.entry
            size: Theme.u(0.52)
        }

        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: (root.entry?.appName || "Application").toUpperCase()
                color: root.critical ? Theme.error : Theme.outline
                elide: Text.ElideRight
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.u(0.2)
                font.letterSpacing: Theme.u(0.2) * 0.1
            }
            Text {
                Layout.fillWidth: true
                text: root.entry?.title || "Notification"
                textFormat: Text.PlainText   // notification text is untrusted: no markup, no remote <img>
                color: AdaptiveColor.glassText
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.u(0.26)
                font.weight: Font.DemiBold
            }
            Text {
                Layout.fillWidth: true
                visible: root.hasBody
                text: root.entry?.body || ""
                textFormat: Text.PlainText   // notification text is untrusted: no markup, no remote <img>
                color: AdaptiveColor.glassTextDim
                elide: Text.ElideRight
                maximumLineCount: 1
                font.family: Config.appearance.fontFamily
                font.pixelSize: Theme.u(0.24)
            }
            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.entry?.desktopEntry || ""
                color: Theme.outline
                elide: Text.ElideRight
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Theme.u(0.2)
            }

            // Named actions beyond a plain click -- shown as small text
            // links rather than the old card's bordered button, matching
            // "Clear all" above in the control-centre mini list.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: root.visibleActions.length > 0
                spacing: Theme.u(0.3)

                Repeater {
                    model: root.visibleActions
                    delegate: Text {
                        required property var modelData
                        required property int index
                        text: NotificationService.plainText(modelData?.text || "")
                        color: actionLinkHover.hovered ? AdaptiveColor.glassText : AdaptiveColor.activeFill
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Theme.u(0.26)
                        font.weight: Font.Medium

                        HoverHandler { id: actionLinkHover }
                        TapHandler { onTapped: NotificationService.invokeAction(root.entry, index) }
                    }
                }

                Item { Layout.fillWidth: true }
            }
        }

        Text {
            Layout.alignment: Qt.AlignTop
            text: "×"
            color: dismissHover.hovered ? AdaptiveColor.glassText : Theme.outline
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.u(0.34)

            HoverHandler { id: dismissHover }
            TapHandler { onTapped: NotificationService.remove(root.entry) }
        }
    }

    HoverHandler { id: cardHover }
    TapHandler {
        enabled: root.hasPrimaryAction
        onTapped: {
            if (NotificationService.canActivate(root.entry))
                NotificationService.activate(root.entry)
            else
                NotificationService.invokeAction(root.entry, 0)
        }
    }

    Behavior on color { ColorAnimation { duration: Animations.fast } }
}
