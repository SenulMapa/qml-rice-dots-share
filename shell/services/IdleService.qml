pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../core"

// Real idle enforcement, added for the impasto-settings-full Session
// section (punch list item 6): two Quickshell.Wayland IdleMonitor
// instances (ext-idle-notify-v1, a real compositor protocol) that fire
// dpms-off and LockService.engage() after Config.idle's configurable
// timeouts. This shell does not own a hypridle config file (see
// HANDOVER.md's "impasto desktop port" section -- packaged hypridle was
// deliberately dropped), so this is the shell's own idle daemon, not a
// generated config for someone else's.
QtObject {
    id: root

    property bool inhibited: false

    readonly property string statusLabel: inhibited ? "Keep awake is active"
        : "Idle timing follows the system's own configuration"

    signal inhibitionChanged(bool inhibited)

    property IpcHandler idleIpc: IpcHandler {
        target: "idle"

        function toggle(): string {
            root.toggleInhibition()
            return root.inhibited ? "IDLE_INHIBITED" : "IDLE_NORMAL"
        }

        function status(): string {
            return root.inhibited ? "INHIBITED" : "NORMAL"
        }
    }

    function toggleInhibition(): void {
        inhibited = !inhibited
        inhibitionChanged(inhibited)
    }

    // 0 means "never" -- both monitors disable themselves in that case
    // rather than firing with a zero-second timeout.
    property IdleMonitor screenOffMonitor: IdleMonitor {
        enabled: !root.inhibited && Config.idle.screenOffTimeoutMinutes > 0
        timeout: Config.idle.screenOffTimeoutMinutes * 60
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle)
                Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "off"])
            else
                Quickshell.execDetached(["hyprctl", "dispatch", "dpms", "on"])
        }
    }

    property IdleMonitor lockMonitor: IdleMonitor {
        enabled: !root.inhibited && Config.idle.lockTimeoutMinutes > 0
        timeout: Config.idle.lockTimeoutMinutes * 60
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle)
                LockService.engage()
        }
    }

    // Always locks first (LockService.engage(), same as the lock monitor
    // above) before scheduling the suspend, matching upstream's own
    // documented policy ("suspend always locks first").
    property IdleMonitor suspendMonitor: IdleMonitor {
        enabled: !root.inhibited && Config.idle.suspendTimeoutMinutes > 0
        timeout: Config.idle.suspendTimeoutMinutes * 60
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle) {
                LockService.engage()
                SessionService.schedule("suspend")
            }
        }
    }
}
