import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../services"

/**
 * MacControlCenter -- Control Center (Tahoe) (spec 3.4).
 *
 * Wired by mac/MacStyleRoot.qml only while Config.appearance.uiStyle is "mac".
 * Routed from island/IslandController.qml (macRoute, page "overview"): the
 * controlCenterToggle shortcut and the `control-center` IPC open it here.
 *
 * The overlay window exists only while the control centre is open or fading
 * out (`mapped`). It is one full-screen layer (namespace
 * qml-rice:mac-controlcenter, which the glass blur rules match) holding the
 * modules. A click outside the modules or Esc closes it. It fades in and
 * scales from 0.96 at the top right. While closed nothing is mapped and no
 * input is taken. The Loader keeps offscreen harnesses free of layer shell.
 */
Item {
    id: root

    // True while the control centre is requested open.
    property bool open: false

    // Last action received from macRoute, for the harness tests.
    property string lastAction: ""

    readonly property int motionMs: Config.appearance.reducedMotion ? 0 : MacTokens.ccMotionMs

    // The window is mapped while open and through the fade-out.
    property bool mapped: false

    // Surface requests from island/IslandController.qml (macRoute): action is
    // "open", "close" or "toggle".
    function request(action: string): void {
        root.lastAction = action
        if (action === "open")
            root.open = true
        else if (action === "close")
            root.open = false
        else if (action === "toggle")
            root.open = !root.open
    }

    onOpenChanged: {
        if (open) {
            hideTimer.stop()
            root.mapped = true
        } else {
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: root.motionMs + 20
        onTriggered: root.mapped = false
    }

    // The window is built only while mapped; `owner` is passed at creation
    // (the window's owner property is required).
    Loader {
        active: root.mapped
        onActiveChanged: if (active) setSource("MacCcWindow.qml",
            { owner: root, screen: MacScreen.choose() })
    }
}
