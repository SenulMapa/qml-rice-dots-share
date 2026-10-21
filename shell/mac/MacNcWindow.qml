import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * MacNcWindow -- the layer window of the Notification Center (namespace
 * qml-rice:mac-nc). Its own file so that offscreen harnesses never compile a
 * PanelWindow (see MacTokens.layerShell). `owner` is the MacNotificationCenter
 * that loads it.
 */
PanelWindow {
    id: win

    property var owner: null

    visible: win.owner ? win.owner.present : false
    anchors { top: true; bottom: true; right: true }
    margins.right: 0
    implicitWidth: column.windowWidth
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qml-rice:mac-nc"
    WlrLayershell.keyboardFocus: win.owner && win.owner.open
        ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: column.region }

    HyprlandFocusGrab {
        windows: [win]
        active: win.owner ? win.owner.open : false
        onCleared: if (win.owner) win.owner.request("close")
    }

    MacNotificationColumn {
        id: column
        anchors.fill: parent
        focus: win.owner ? win.owner.open : false
        shown: win.owner ? win.owner.shown : 0
        opacity: MacPresence.level
        onCloseRequested: if (win.owner) win.owner.request("close")
    }
}
