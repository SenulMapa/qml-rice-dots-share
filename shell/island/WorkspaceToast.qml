import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../core"
import "../services"

/**
 * WorkspaceToast -- one per screen (see shell.qml's Variants, modelled
 * directly on widgets/WidgetLayer.qml's own per-screen PanelWindow), showing
 * a "Workspace N" OSD bottom-centre of a screen for exactly 5s whenever the
 * launcher opens there (island/Island.qml's launcherPageActive watcher
 * fires ShellActions.launcherOpened(monitor) on the real open edge -- see
 * core/ShellActions.qml).
 *
 * Its own layer, click-through, no reserved space: this is a transient
 * status readout, never an input surface, and must never budge any other
 * layer's geometry.
 */
PanelWindow {
    id: window

    readonly property var monitor: Hyprland.monitorFor(screen)

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qml-rice:workspace-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Empty region -- contributes zero input area, so the toast never
    // intercepts a click/hover meant for whatever is underneath it (same
    // "unconditional Combine of zero-area items" pattern Island.qml's own
    // mask relies on, taken to its limit of no items at all).
    mask: Region {}

    anchors { bottom: true; left: true; right: true }
    implicitHeight: Theme.u(2.4)

    Loader {
        id: cardLoader
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.u(0.9)
        active: false
        sourceComponent: WorkspaceToastCard {
            workspaceId: HyprlandService.activeWorkspaceId
            onFinished: cardLoader.active = false
        }
    }

    /** Shows (or, if already showing, cleanly restarts) the toast. Only
     *  called for the monitor the launcher actually opened on. */
    function present(): void {
        if (cardLoader.active && cardLoader.item)
            cardLoader.item.restart()
        else
            cardLoader.active = true
    }

    Connections {
        target: ShellActions
        function onLauncherOpened(monitor): void {
            if (monitor === window.monitor)
                window.present()
        }
    }
}
