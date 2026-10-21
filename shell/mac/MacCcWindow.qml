import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../core"
import "../services"

/**
 * MacCcWindow -- the layer window behind MacControlCenter (spec 3.4). Loaded
 * by MacControlCenter only while the control centre is mapped (open, or in
 * its fade-out), so the PanelWindow type is never built offscreen or while
 * closed. Kept in its own file for that reason.
 *
 * `owner` is the MacControlCenter; `owner.open` drives the fade and the input
 * mask. One full-screen layer (namespace qml-rice:mac-controlcenter, which the
 * glass blur rules match). A click outside the modules or Esc closes it.
 */
PanelWindow {
    id: win

    // The MacControlCenter that loaded this window.
    required property var owner

    // Set after the first frame, so a freshly mapped window fades in.
    property bool armed: false
    // Height fit: the stack (top inset to the Edit pill) may use at most 90%
    // of the screen height. Only shrinks when the combined mac and display
    // scale would exceed that (1080p laptop at DisplayScale 1.36 x macScale).
    readonly property real stackHeight: MacTokens.s(MacTokens.ccInsetTop + MacTokens.ccEditY + MacTokens.ccEditHeight)
    readonly property real screenHeight: win.screen ? win.screen.height : 1080
    readonly property real fit: stackHeight > 0 ? Math.min(1, 0.9 * win.screenHeight / stackHeight) : 1
    Component.onCompleted: Qt.callLater(() => win.armed = true)

    // The primary monitor (the same one HyprlandService tracks), else the first.

    // Tight to the module stack (plus the screen margins): a full-output layer
    // gets frosted as one slab by the blur. Click-outside is a focus grab.
    anchors { top: true; right: true }
    margins.top: 0
    margins.right: 0
    implicitWidth: panel.width + MacTokens.s(MacTokens.ccInsetRight) + 2
    implicitHeight: MacTokens.s(MacTokens.ccInsetTop) + panel.height + 2
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qml-rice:mac-controlcenter"
    WlrLayershell.keyboardFocus: win.owner.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Input only on the modules while open. A click elsewhere clears the grab.
    mask: win.owner.open ? openMask : closedMask
    Region { id: openMask; item: panel }
    Region { id: closedMask }

    HyprlandFocusGrab {
        windows: [win]
        active: win.owner.open
        onCleared: win.owner.request("close")
    }

    // Esc closes. Focused while open.
    Item {
        id: keys
        anchors.fill: parent
        focus: win.owner.open
        Keys.onEscapePressed: win.owner.request("close")
    }

    Connections {
        target: win.owner
        function onOpenChanged(): void {
            if (win.owner.open)
                Qt.callLater(() => keys.forceActiveFocus())
        }
    }

    Item {
        id: panel
        width: content.width
        height: content.height
        x: win.width - MacTokens.s(MacTokens.ccInsetRight) - width - 1
        y: MacTokens.s(MacTokens.ccInsetTop)
        transformOrigin: Item.TopRight
        opacity: (win.owner.open && win.armed ? 1 : 0) * MacPresence.level
        scale: (win.owner.open && win.armed ? 1 : MacTokens.ccMotionFromScale) * win.fit

        Behavior on opacity { NumberAnimation { duration: win.owner.motionMs; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: win.owner.motionMs; easing.type: Easing.OutCubic } }

        MacCcPanel {
            id: content
            onDismissRequested: win.owner.request("close")
        }
    }
}
