import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../core"

/**
 * MacQuickLookWindow -- the layer window that hosts the Quick Look preview
 * (namespace qml-rice:mac-quicklook). Sized to the panel and centred on the
 * screen, so the blur never frosts the whole output. Keyboard is exclusive
 * while open (Space and Esc close, arrows step). An outside click dismisses
 * through a focus grab, like the Spotlight. Its own file so offscreen
 * harnesses never compile a PanelWindow (see MacTokens.layerShell). `owner` is
 * the MacQuickLook that loads it.
 */
PanelWindow {
    id: win

    property var owner: null
    readonly property bool openNow: win.owner ? win.owner.open : false
    readonly property var preview: panel
    readonly property real panelWidth: MacTokens.s(MacTokens.quickLookWidth)
    readonly property real panelHeight: MacTokens.s(MacTokens.quickLookHeight)
    readonly property real screenHeight: win.screen ? win.screen.height : 1080
    readonly property real screenWidth: win.screen ? win.screen.width : 1920
    // Never taller than 90% of the screen: shrink with the display scale if needed.
    readonly property real fit: Math.min(1, 0.9 * win.screenHeight / panelHeight)

    visible: win.openNow || panel.opacity > 0.001
    color: "transparent"
    anchors { top: true; left: true }
    margins.left: Math.round((win.screenWidth - win.panelWidth) / 2)
    margins.top: Math.round((win.screenHeight - win.panelHeight * win.fit) / 2)
    implicitWidth: win.panelWidth
    implicitHeight: win.panelHeight
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qml-rice:mac-quicklook"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: win.openNow ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Outside click dismisses.
    HyprlandFocusGrab {
        windows: [win]
        active: win.openNow
        onCleared: if (win.owner) win.owner.close()
    }

    MacQuickLookPanel {
        id: panel
        width: win.panelWidth
        height: win.panelHeight
        path: win.owner ? win.owner.path : ""
        info: win.owner ? win.owner.info : null
        textPreview: win.owner ? win.owner.textPreview : ""
        textBinary: win.owner ? win.owner.textBinary : false
        pdfPng: win.owner ? win.owner.pdfPng : ""
        pdfError: win.owner ? win.owner.pdfError : ""
        position: win.owner ? Math.max(0, win.owner.siblings.indexOf(win.owner.name) + 1) : 0
        count: win.owner ? win.owner.siblings.length : 0
        opacity: (win.openNow ? 1 : 0) * MacPresence.level
        scale: (win.openNow ? 1 : 0.97) * win.fit
        transformOrigin: Item.Center
        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        onCloseRequested: if (win.owner) win.owner.close()
        onStepRequested: delta => { if (win.owner) win.owner.step(delta) }
        onOpenRequested: {
            if (win.owner && win.owner.path !== "")
                Quickshell.execDetached(["xdg-open", win.owner.path])
        }
    }
}
