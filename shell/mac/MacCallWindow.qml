import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

/**
 * MacCallWindow -- the top-right layer window of the incoming-call card
 * (namespace qml-rice:mac-call). Its own file so offscreen harnesses never
 * compile a PanelWindow (see MacTokens.layerShell). `owner` is the
 * MacCallBanner that loads it.
 */
PanelWindow {
    id: win

    property var owner: null

    visible: (win.owner ? win.owner.wanted : false) || card.opacity > 0.001
    color: "transparent"
    anchors { top: true; right: true }
    margins {
        top: MacTokens.s(MacTokens.bannerInsetTop)
        right: MacTokens.s(MacTokens.bannerInsetRight)
    }
    implicitWidth: MacTokens.s(MacTokens.callWidth)
    implicitHeight: MacTokens.s(MacTokens.callBannerHeight)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qml-rice:mac-call"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Crossfade (MacPresence). The card's own opacity follows `live`, so the
    // level goes on this wrapper.
    Item {
        anchors.fill: parent
        opacity: MacPresence.level

        MacCallCard {
            id: card
            anchors.fill: parent
            call: win.owner ? win.owner.shown : null
            error: win.owner && win.owner.service ? String(win.owner.service.callError || "") : ""
            live: win.owner ? win.owner.wanted : false
            onAnswerRequested: win.owner.service.answer()
            onDeclineRequested: win.owner.service.decline()
        }
    }
}
