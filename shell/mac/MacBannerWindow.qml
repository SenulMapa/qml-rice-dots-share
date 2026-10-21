import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"

/**
 * MacBannerWindow -- one layer window per banner in the stack (namespace
 * qml-rice:mac-banner). Its own file so offscreen harnesses never compile a
 * PanelWindow (see MacTokens.layerShell). MacBanners loads it per row and
 * passes `owner`, `uid`, `index` and `leaving`.
 */
PanelWindow {
    id: window

    property var owner: null
    property int uid: 0
    property int index: 0
    property bool leaving: false
    readonly property var entry: window.owner ? (window.owner.live[window.uid] ?? null) : null

    anchors { top: true; right: true }
    // Only the front stack maps; the pile behind it stays unmapped until it moves up.
    visible: window.index < MacTokens.bannerMaxVisible
    margins.top: MacTokens.s(MacTokens.bannerInsetTop)
        + window.index * (MacTokens.s(MacTokens.bannerHeight) + MacTokens.s(MacTokens.bannerStackGap))
    // The inset sits in the margin, so the window is the card plus the shadow pad.
    margins.right: view.insetRight
    // Stack reflow: when a banner above leaves, the rest glide up instead of jumping.
    Behavior on margins.top {
        NumberAnimation { duration: MacTokens.bannerSlideOutMs; easing.type: Easing.OutCubic }
    }
    implicitWidth: view.implicitWidth
    implicitHeight: view.implicitHeight + (pileChip.visible ? pileChip.height + MacTokens.s(MacTokens.bannerStackGap) / 2 : 0)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qml-rice:mac-banner"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: view.bodyItem }

    onLeavingChanged: {
        if (window.leaving)
            view.leave()
    }

    // Crossfade (MacPresence) on the wrapper, so MacBanner stays usable on its
    // own (the render harnesses draw it outside the mac root).
    Item {
        anchors.fill: parent
        opacity: MacPresence.level

        MacBanner {
            id: view
            entry: window.entry

            onActivated: {
                NotificationService.activate(window.entry)
                view.leave()
            }
            onActionInvoked: index => {
                NotificationService.invokeAction(window.entry, index)
                view.leave()
            }
            // X or swipe: an iPhone notification is cleared at its source too.
            onDismissed: NotificationService.dismissBanner(window.entry)
            held: window.index >= MacTokens.bannerMaxVisible
            onExited: if (window.owner) window.owner.removeUid(window.uid)
        }

        // "+N" chip under the last front banner: the rest of the stack, waiting.
        Rectangle {
            id: pileChip
            visible: window.index === MacTokens.bannerMaxVisible - 1 && window.owner
                && window.owner.pileCount > 0
            x: view.pad + (view.bodyWidth - width) / 2
            y: view.bodyHeight + MacTokens.s(MacTokens.bannerStackGap) / 2
            width: MacTokens.s(44)
            height: MacTokens.s(18)
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.55)
            Text {
                anchors.centerIn: parent
                text: "+" + (window.owner ? window.owner.pileCount : 0)
                color: MacTokens.labelPrimary
                font.family: MacTokens.textFamily
                font.pixelSize: MacTokens.s(11)
                font.weight: Font.DemiBold
            }
        }
    }
}
