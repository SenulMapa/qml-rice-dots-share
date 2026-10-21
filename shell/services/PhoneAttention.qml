pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../core"

// Attention gate for the iPhone continuity UI (spec "Round 3", item 5).
// `active` means this machine had user input within the last `idleSeconds`
// AND the session is not locked. With the phone used from two machines at
// once, only the machine you are actually at interrupts you; the other keeps
// PhoneService state up to date silently.
//
// Idle detection is Quickshell.Wayland's IdleMonitor (ext-idle-notify-v1),
// the same protocol services/IdleService.qml uses for its lock/dpms timers.
QtObject {
    id: root

    readonly property int idleSeconds: 120

    // Testability seams: null = use the real signal, true/false = force.
    property var idleOverride: null
    property var lockedOverride: null

    readonly property bool idle: idleOverride !== null ? idleOverride === true : monitor.isIdle
    readonly property bool locked: lockedOverride !== null ? lockedOverride === true
        : !!(LockService.lockScreen && LockService.lockScreen.locked)
    readonly property bool active: !idle && !locked

    // Phone text (message bodies, sender, reply UI) may only render while this
    // is true: never while the session is locked.
    readonly property bool textAllowed: !locked

    property IdleMonitor monitor: IdleMonitor {
        enabled: Config.phone.enabled
        timeout: root.idleSeconds
        respectInhibitors: false
    }

    // kind: "message" | "call" | "pin" | "live"
    // returns "show" | "quiet" | "pill"
    function decide(kind: string, idle: bool, locked: bool): string {
        if (kind === "live")
            return locked ? "quiet" : "show"
        if (locked)
            return "quiet"
        if (kind === "call")
            return idle ? "pill" : "show"
        if (kind === "message" || kind === "pin")
            return idle ? "quiet" : "show"
        return "quiet"
    }

    function decideNow(kind: string): string {
        return decide(kind, idle, locked)
    }
}
