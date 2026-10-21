import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../core"

/**
 * MacNotificationCenter -- the Notification Center window (spec 3.3). STUB
 * replaced: a right-side layer window (namespace qml-rice:mac-nc) that
 * slides in from the right. Opened by request() from MacStyleRoot, which
 * forwards the pill's notifications page. Closes on Esc, on a click outside
 * (HyprlandFocusGrab) and on the heading's close button.
 *
 * Only the column is on the layer. Its mask limits input to the column, so
 * the rest of the screen stays clickable while the NC is open.
 */
Item {
    id: root

    // Requested state. `present` keeps the window mapped while the close slide runs.
    property bool open: false
    property bool present: false
    // Slide position, 0 (hidden) to 1 (shown). Lives here so the window below
    // can be built only with layer shell.
    property real shown: 0
    // Screen for the next open, set by requestOn(). Null means the focused one.
    property var targetScreen: null
    // Screen both layer windows were built on. Set when opening, read by the loaders.
    property var _screen: null

    visible: false
    width: 0
    height: 0

    // Surface requests from IslandController.macRoute(): "open", "close" or
    // "toggle".
    function request(action: string): void {
        if (action === "open")
            root.open = true
        else if (action === "close")
            root.open = false
        else if (action === "toggle")
            root.open = !root.open
    }

    // Same as request(), but the window opens on `screen` (the top-right hot
    // corner passes the monitor it was clicked on).
    function requestOn(action: string, screen: var): void {
        root.targetScreen = screen
        root.request(action)
    }

    onOpenChanged: {
        if (root.open) {
            root._screen = root.targetScreen || MacScreen.choose()
            root.targetScreen = null
            root.present = true
        }
        slide.from = root.shown
        slide.to = root.open ? 1 : 0
        slide.easing.type = root.open ? Easing.OutCubic : Easing.InCubic
        slide.restart()
    }

    NumberAnimation {
        id: slide
        target: root
        property: "shown"
        duration: MacTokens.ncSlideMs
        onFinished: {
            if (!root.open)
                root.present = false
        }
    }

    // The layer windows are built only with layer shell (see MacTokens.layerShell).
    // They live in their own files so the offscreen harness never compiles them.
    // The backdrop loader is declared first so its window maps under the NC.
    Loader {
        id: backdropLoader
        active: MacTokens.layerShell && root.present
        onActiveChanged: if (active) setSource("MacNcBackdropWindow.qml",
            { screen: root._screen })
        onLoaded: item.owner = root
    }

    Loader {
        id: winLoader
        // Built while presented (open, and through the close slide) so every
        // open takes the screen that has focus then.
        active: MacTokens.layerShell && root.present
        onActiveChanged: if (active) setSource("MacNcWindow.qml",
            { screen: root._screen })
        onLoaded: item.owner = root
    }
}
