import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../core"

/**
 * MacSpotlightWindow -- the layer window that hosts the Spotlight panel
 * (namespace qml-rice:mac-spotlight). Sized to the panel and centred by margin,
 * so the blur never frosts the whole output. Outside click is a focus grab. Its own file so offscreen
 * harnesses never compile a PanelWindow (see MacTokens.layerShell). `owner` is
 * the MacSpotlight that loads it.
 */
PanelWindow {
    id: win

    property var owner: null
    readonly property bool openNow: win.owner ? win.owner.open : false
    // Read by MacSpotlight.request(): the panel lives inside this window.
    readonly property var spotPanel: panel
    // The panel (top inset plus height) may use at most 90% of the screen
    // height; shrinks only when mac and display scale together would overflow.
    readonly property real stackHeight: MacTokens.s(MacTokens.spotlightTop + MacTokens.spotlightHeight)
    readonly property real screenHeight: win.screen ? win.screen.height : 1080
    readonly property real screenWidth: win.screen ? win.screen.width : 1920
    readonly property real fit: stackHeight > 0 ? Math.min(1, 0.9 * win.screenHeight / stackHeight) : 1

    visible: win.openNow || panel.opacity > 0.001
    color: "transparent"
    anchors { top: true; left: true }
    margins.top: 0
    margins.left: Math.round((win.screenWidth - panel.width) / 2)
    implicitWidth: panel.width
    implicitHeight: MacTokens.s(MacTokens.spotlightTop) + panel.height + 2
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qml-rice:mac-spotlight"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: win.openNow ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Outside click dismisses (focus grab, like the Control Center).
    HyprlandFocusGrab {
        windows: [win]
        active: win.openNow
        onCleared: if (win.owner) win.owner.close()
    }

    MacSpotlightPanel {
        id: panel
        provider: win.owner ? win.owner.provider : null
        x: 0
        y: MacTokens.s(MacTokens.spotlightTop)
        opacity: (win.openNow ? 1 : 0) * MacPresence.level
        scale: (win.openNow ? 1 : MacTokens.spotlightMotionFromScale) * win.fit
        transformOrigin: Item.Top
        Behavior on opacity {
            NumberAnimation { duration: MacTokens.spotlightMotionMs; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: MacTokens.spotlightMotionMs; easing.type: Easing.OutCubic }
        }
        onDismissRequested: if (win.owner) win.owner.close()
        onPageRequested: page => {
            // Same routing the pill would do; MacStyleRoot picks the surface.
            if (win.owner) win.owner.close()
            ShellActions.macSurfaceRequested(page, "open")
        }
    }
}
