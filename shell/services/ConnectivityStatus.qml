pragma Singleton
import QtQuick
import "." as Services

/**
 * ConnectivityStatus -- the numbers behind components/StatusOrb.qml, derived
 * from the existing NetworkService and BluetoothService. Read-only.
 *
 * btSignal: BlueZ only reports RSSI while discovering, so connected devices
 * usually have none; a connected device with no reading counts as full
 * strength so the ring still says "connected".
 */
QtObject {
    readonly property real wifiStrength: Services.NetworkService.wifiConnected
        ? Math.round(Services.NetworkService.signalPercent / 5) / 20
        : -1
    readonly property bool ethernet: Services.NetworkService.ethernetConnected

    readonly property bool btEnabled: Services.BluetoothService.enabled
    readonly property int btDevices: Math.min(4, Services.BluetoothService.connectedCount)
    readonly property real btSignal: {
        const devices = Services.BluetoothService.connectedDevices;
        if (devices.length === 0)
            return 0;
        let best = 0;
        for (const d of devices) {
            const rssi = d.rssi;
            // Unknown RSSI -> treat as a solid link; else -90..-40 dBm -> 0..1.
            const v = (typeof rssi !== "number" || rssi === 0) ? 1 : (rssi + 90) / 50;
            best = Math.max(best, Math.max(0, Math.min(1, v)));
        }
        return best;
    }
}
