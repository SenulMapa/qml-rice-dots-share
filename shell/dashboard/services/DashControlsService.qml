// Control-centre adapter, ported from impasto's services/ControlsService.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// Upstream's ControlsService owns a freeform draggable/resizable block grid
// (per-cell geometry, a tray, drag-and-drop, an inspector). That whole
// arrange-mode editing system was NOT ported -- see HANDOVER.md's dashboard
// section: this run ships a fixed, real-data control centre instead of
// re-deriving pixel-perfect freeform drag/resize without ever being able to
// run it live (hard rule: never launch qs/quickshell). This singleton only
// keeps the piece every card actually needs: the quick-toggle tile model,
// bound to the shell's own real services -- no fake data.

pragma Singleton

import QtQuick
import Quickshell
import "../../services" as Shell

Singleton {
    id: root

    // ── QUICK TOGGLES ─────────────────────────────────────────────────────
    //
    // Each tile: { id, icon, label, detail, active, available, expandable,
    // panel, closes, activate() }. `expandable` tiles have a `panel` id
    // DashControlsPanel/DashDetailFace can navigate to; `closes` tiles
    // dismiss the panel once activated (matches upstream's tray-toggle
    // behaviour for wifi/bluetooth power switches).
    readonly property var tiles: [
        {
            id: "wifi",
            icon: Shell.NetworkService.icon || "󰤨",
            label: "Wi-Fi",
            detail: Shell.NetworkService.wifiEnabled
                ? (Shell.NetworkService.connectionName || "On") : "Off",
            active: Shell.NetworkService.wifiEnabled,
            available: Shell.NetworkService.available,
            expandable: true,
            panel: "network",
            closes: false,
            activate: () => Shell.NetworkService.toggleWifi()
        },
        {
            id: "bluetooth",
            icon: "󰂯",
            label: "Bluetooth",
            detail: Shell.BluetoothService.enabled
                ? (Shell.BluetoothService.statusLabel || "On") : "Off",
            active: Shell.BluetoothService.enabled,
            available: Shell.BluetoothService.available,
            expandable: true,
            panel: "bluetooth",
            closes: false,
            activate: () => Shell.BluetoothService.toggleEnabled()
        },
        {
            id: "dnd",
            icon: "󰂛",
            label: "Focus",
            detail: Shell.NotificationService.doNotDisturb ? "On" : "Off",
            active: Shell.NotificationService.doNotDisturb,
            available: true,
            expandable: false,
            panel: "",
            closes: false,
            activate: () => Shell.NotificationService.toggleDoNotDisturb()
        },
        {
            id: "nightlight",
            icon: "󰛨",
            label: "Night Light",
            detail: Shell.NightLightService.enabled ? "On" : "Off",
            active: Shell.NightLightService.enabled,
            available: Shell.NightLightService.available,
            expandable: false,
            panel: "",
            closes: false,
            activate: () => Shell.NightLightService.toggle()
        },
        {
            id: "mute",
            icon: Shell.AudioService.muted ? "󰝟" : "󰕾",
            label: "Sound",
            detail: Shell.AudioService.muted ? "Muted" : (Shell.AudioService.volumePercent + "%"),
            active: Shell.AudioService.muted,
            available: Shell.AudioService.available,
            expandable: false,
            panel: "",
            closes: false,
            activate: () => Shell.AudioService.toggleMute()
        },
        {
            id: "mic",
            icon: Shell.AudioService.microphoneMuted ? "󰍭" : "󰍬",
            label: "Microphone",
            detail: Shell.AudioService.microphoneMuted ? "Muted" : "Live",
            active: Shell.AudioService.microphoneMuted,
            available: Shell.AudioService.microphoneAvailable,
            expandable: false,
            panel: "",
            closes: false,
            activate: () => Shell.AudioService.toggleMicrophoneMute()
        }
    ]

    // ── POWER ROW (session actions) ──────────────────────────────────────
    //
    // Mirrors controls/PowerRow.qml's tile set. panels/SessionPage.qml
    // already owns the shell's real session confirmation flow (this port
    // does not duplicate it -- see the brief's "do not port ... session").
    // Activating a tile here just forwards to the same SessionService the
    // rest of the shell uses.
    readonly property var powerActions: [
        { id: "lock", icon: "󰌾", label: "Lock", available: Shell.SessionService.lockAvailable },
        { id: "suspend", icon: "󰤄", label: "Suspend", available: Shell.SessionService.suspendAvailable },
        { id: "logout", icon: "󰍃", label: "Log Out", available: Shell.SessionService.logoutAvailable },
        { id: "reboot", icon: "󰑐", label: "Restart", available: Shell.SessionService.rebootAvailable },
        { id: "shutdown", icon: "󰐥", label: "Shut Down", available: Shell.SessionService.shutdownAvailable }
    ]

    function runPower(id: string): void {
        Shell.SessionService.schedule(id)
    }
}
