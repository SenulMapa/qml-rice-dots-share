import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"
import "../launcher"

/**
 * MacSpotlight -- Spotlight (spec 3.5): the centred search layer, mac style.
 *
 * Wired by mac/MacStyleRoot.qml only while uiStyle is "mac". The pill's
 * launcher page is routed here by IslandController.macRoute(), so the
 * launcher IPC toggle does not change. Results come from the existing
 * CommandPaletteService through MacSpotlightPanel, unchanged.
 *
 * Layer: `qml-rice:mac-spotlight`. A full-screen overlay catches outside
 * clicks (dismiss) and Esc closes from the field. Fade and a 0.97 to 1 scale,
 * 220 ms.
 */
Scope {
    id: root

    // The provider the palette searches. Overridable for renders and tests.
    property var provider: CommandPaletteService
    // Set while the surface is wanted on screen.
    property bool open: false
    // The window is built while open and through the fade-out (MacSpotlightWindow),
    // so each open takes the screen that has focus then.
    property bool mapped: false

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
        interval: MacTokens.spotlightMotionMs + 40
        onTriggered: if (!root.open) root.mapped = false
    }

    // Surface requests from island/IslandController.qml (macRoute): action is
    // "open", "close" or "toggle".
    function request(action: string): void {
        if (action === "open")
            open = true
        else if (action === "close")
            open = false
        else if (action === "toggle")
            open = !open
        if (open)
            Qt.callLater(() => { if (root.open && winLoader.item) winLoader.item.spotPanel.reset() })
    }

    function close(): void {
        open = false
    }

    // The layer window is built only with layer shell (see MacTokens.layerShell).
    // It lives in its own file so the offscreen harness never compiles it.
    Loader {
        id: winLoader
        active: MacTokens.layerShell && root.mapped
        onActiveChanged: if (active) setSource("MacSpotlightWindow.qml",
            { screen: MacScreen.choose() })
        onLoaded: item.owner = root
    }
}
