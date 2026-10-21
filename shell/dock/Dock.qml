import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../core"
import "../services"
import "model.js" as M

/**
 * Dock -- the per-monitor layer surface around DockSurface.
 *
 * Namespace qml-rice:dock (hypr/hyprland/glass.lua adds the blur rule).
 * One transparent, click-through surface along the bottom edge; the input
 * mask is only the dock itself, a thin edge-trigger strip while hidden, and
 * the open context menu. The surface is tall enough for fully magnified icons
 * and the menu; it never reserves space unless `dock.autohide` is false.
 *
 * Autohide (default): hovering the bottom edge for DockMetrics.revealDelay
 * slides the dock in; leaving it for hideDelay slides it out. The dock only
 * lives on the monitor Hyprland considers focused (the one under the pointer),
 * like macOS -- the other monitors keep just their trigger strip, and hovering
 * it makes that monitor the host. In always-visible mode every monitor shows
 * the dock, because a reserved zone that moved between monitors would reflow
 * every window each time the pointer crossed over.
 */
PanelWindow {
    id: win

    property var dockModel                         // shared DockModel
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property bool autohide: SettingsStore.boolValue("dock", "autohide", false)
    readonly property bool host: HyprlandService.monitorIsFocused(monitor)
    readonly property real dockScale: (Theme.u(1) / 44) * SettingsStore.numberValue("dock", "scale", 1, 0.6, 1.6)

    property bool revealed: false
    property bool interacting: false
    readonly property bool shown: autohide ? (revealed && (host || interacting)) : true

    color: "transparent"
    WlrLayershell.namespace: "qml-rice:dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { bottom: true; left: true; right: true }
    implicitHeight: Math.ceil(420 * dockScale)
    exclusionMode: autohide ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: autohide ? 0 : Math.ceil(surface.shelfH + (DockMetrics.bottomMargin + 2) * dockScale)

    mask: Region {
        item: surface.hit
        Region { item: trigger; intersection: Intersection.Combine }
        Region { item: surface.menuBox; intersection: Intersection.Combine }
        Region { item: surface.scrim; intersection: Intersection.Combine }
    }

    onShownChanged: { if (shown) hideTimer.stop() }
    onInteractingChanged: {
        if (interacting) { hideTimer.stop() }
        else if (autohide && revealed) hideTimer.restart()
    }
    // Another monitor became the host: this one lets go.
    onHostChanged: if (!host && autohide && !interacting) hideTimer.restart()

    Timer {
        id: revealTimer
        interval: DockMetrics.revealDelay * 1000
        onTriggered: { win.revealed = true; hideTimer.restart() }
    }
    Timer {
        id: hideTimer
        interval: DockMetrics.hideDelay * 1000
        onTriggered: if (!win.interacting) win.revealed = false
    }
    Timer { running: true; interval: 1500; onTriggered: surface.animateAppear = true }

    // Bottom-edge hover strip: the autohide trigger.
    Item {
        id: trigger
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: win.autohide && !win.shown ? Math.max(1, DockMetrics.edgeTrigger) : 0
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: revealTimer.restart()
            onExited: revealTimer.stop()
        }
    }

    DockSurface {
        id: surface
        anchors.fill: parent
        items: win.dockModel ? win.dockModel.items : []
        dockScale: win.dockScale
        slide: win.shown ? 1 : 0
        Behavior on slide {
            NumberAnimation {
                duration: DockMetrics.slideDuration * 1000
                easing.type: Easing.InOutCubic
            }
        }
        onInteracting: active => win.interacting = active

        onActivated: (item, button) => {
            if (button === Qt.MiddleButton) win.dockModel.newInstance(item)
            else win.dockModel.activate(item)
        }
        onReordered: ids => win.dockModel.reorder(ids)
        onUnpinned: item => win.dockModel.unpin(item)
        onMenuAction: (action, item, arg) => {
            const m = win.dockModel
            switch (action) {
            case "focusWindow": m.focusWindow(arg); break
            case "restore": m.restore(arg || item.address); break
            case "closeWindow": m.dispatch(M.closeCmd(item.address)); break
            case "open": m.launch(item); break
            case "pin": m.pin(item); break
            case "unpin": m.unpin(item); break
            case "showAll": if (item.addresses.length > 0) m.focusWindow(item.addresses[0]); break
            case "quit": m.quit(item); break
            }
        }
    }
}
