import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"

/**
 * MacCallBanner -- the Tahoe call banner for an INCOMING call (spec 3.6).
 *
 * Wired by mac/MacStyleRoot.qml only while uiStyle is "mac". In this mode
 * IslandController.syncPhoneCall leaves the ringing card out of the pill, so
 * this surface owns it. An answered call (state "active") stays in the pill.
 *
 * Shown while PhoneService.call is "incoming" and PhoneAttention lets a call
 * through. decide() returns "pill" when this machine is idle: the pill does
 * not take a ringing call in mac style either, so the banner shows for both
 * "show" and "pill". Only "quiet" (locked) hides it.
 *
 * Top right, under the banner inset. Layer `qml-rice:mac-call`.
 */
Scope {
    id: root

    property var service: PhoneService
    readonly property var call: service ? service.call : null
    readonly property bool wanted: !!call && call.state === "incoming"
        && PhoneAttention.decide("call", PhoneAttention.idle, PhoneAttention.locked) !== "quiet"

    // Keeps the last ringing call while the card slides out.
    property var shown: null
    onCallChanged: if (call) shown = call

    // Built while a call is wanted and through the slide-out, so each ringing
    // call takes the screen that has focus then.
    property bool mapped: false
    Component.onCompleted: if (wanted) mapped = true
    onWantedChanged: {
        if (wanted) {
            hideTimer.stop()
            mapped = true
        } else {
            hideTimer.restart()
        }
    }
    Timer {
        id: hideTimer
        interval: MacTokens.callSlideMs + 40
        onTriggered: if (!root.wanted) root.mapped = false
    }

    // The layer window is built only with layer shell (see MacTokens.layerShell).
    // It lives in its own file so the offscreen harness never compiles it.
    Loader {
        id: winLoader
        active: MacTokens.layerShell && root.mapped
        onActiveChanged: if (active) setSource("MacCallWindow.qml",
            { screen: MacScreen.choose() })
        onLoaded: item.owner = root
    }
}
