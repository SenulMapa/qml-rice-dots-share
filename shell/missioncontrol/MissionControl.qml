import QtQuick
import "../core"
import "../services"

/**
 * MissionControl -- open/close state for the Mission Control overlay.
 *
 * One instance, owned by shell.qml. It is opened by the `quickshell:
 * missionControlToggle` global shortcut (core/ShellCompatShortcuts.qml ->
 * ShellActions.missionControlToggleRequested) and only ever shows on the
 * monitor that had focus when it opened (monitorId). The per-screen
 * windows in MissionControlWindow.qml read `open` and `monitorId`.
 */
QtObject {
    id: root

    property bool open: false
    property int monitorId: -1

    function toggle(): void {
        if (root.open)
            root.close()
        else
            root.show()
    }

    function show(): void {
        const monitor = HyprlandService.focusedMonitor
        if (!monitor)
            return
        root.monitorId = monitor.id
        root.open = true
    }

    function close(): void {
        root.open = false
    }

    property Connections toggleLink: Connections {
        target: ShellActions
        function onMissionControlToggleRequested(): void { root.toggle() }
    }
}
