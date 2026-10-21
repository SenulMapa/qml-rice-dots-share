// Desktop adapter over the shell's real services/BluetoothService.qml.
// Exposes impasto's BluetoothService-shaped API for faces/analogue/
// BluetoothFace.

pragma Singleton

import QtQuick
import Quickshell
import "../../services" as Shell

Singleton {
    id: root

    readonly property bool available: Shell.BluetoothService.available
    readonly property bool enabled: Shell.BluetoothService.enabled
    readonly property var connectedDevices: Shell.BluetoothService.connectedDevices
    readonly property string summary: Shell.BluetoothService.statusLabel
    readonly property string icon: {
        if (!root.enabled)
            return "󰂲"
        return Shell.BluetoothService.connected ? "󰂱" : "󰂯"
    }

    function toggleEnabled(): void {
        Shell.BluetoothService.toggleEnabled()
    }

    // impasto's BluetoothCard/island/cards/BluetoothCard.qml (bar/island/
    // BluetoothDetail.qml) needs impasto's own BluetoothService shape
    // beyond the summary fields above: a device list split into named/
    // unnamed, discovery control, and per-device connect. `_ref` keeps the
    // real Quickshell.Bluetooth device so deviceIcon()/connectDevice()
    // below can call the real service's own device-taking functions.
    // impasto's own BluetoothCard calls `BluetoothService.toggle()`, not
    // `toggleEnabled()` -- kept as a second name onto the same real call
    // rather than renaming every existing `toggleEnabled()` call site.
    function toggle(): void {
        Shell.BluetoothService.toggleEnabled()
    }
    readonly property bool discovering: Shell.BluetoothService.discovering

    function mapDevice(device) {
        return {
            name: Shell.BluetoothService.deviceName(device),
            address: device.address || "",
            connected: !!device.connected,
            paired: !!(device.paired || device.bonded),
            pairing: !!device.pairing,
            batteryAvailable: !!device.batteryAvailable,
            battery: device.batteryAvailable ? device.battery : 0,
            _ref: device
        }
    }

    // "Named" mirrors impasto's own BlueZ-Alias-vs-address distinction as
    // closely as this backend allows: a device with a real `name`/
    // `deviceName` property, not deviceName()'s "Bluetooth device"
    // fallback (which would otherwise call every device named).
    readonly property var devices: Shell.BluetoothService.discoverableDevices
        .filter(device => !!(device.name || device.deviceName))
        .map(root.mapDevice)
    readonly property var unnamedDevices: Shell.BluetoothService.discoverableDevices
        .filter(device => !(device.name || device.deviceName))
        .map(root.mapDevice)
    readonly property int unnamedCount: root.unnamedDevices.length

    function isNamed(mapped): bool {
        return !!(mapped._ref.name || mapped._ref.deviceName)
    }

    function deviceIcon(mapped): string {
        return Shell.BluetoothService.deviceIcon(mapped._ref)
    }

    function setDiscovering(value: bool): void {
        Shell.BluetoothService.setDiscovering(value)
    }

    function connectDevice(mapped): void {
        Shell.BluetoothService.toggleDeviceConnection(mapped._ref)
    }
}
