// Desktop adapter over the shell's real services/NetworkService.qml.
// Exposes impasto's NetworkService-shaped API for faces/analogue/NetworkFace.

pragma Singleton

import QtQuick
import Quickshell
import "../../services" as Shell

Singleton {
    id: root

    readonly property bool available: Shell.NetworkService.available
    readonly property bool online: Shell.NetworkService.connected
    readonly property bool wifiConnected: Shell.NetworkService.wifiConnected
    readonly property bool wiredConnected: Shell.NetworkService.ethernetConnected
    readonly property string connectionName: Shell.NetworkService.connectionName
    readonly property string stateLine: Shell.NetworkService.statusLabel
    readonly property string icon: Shell.NetworkService.icon
    // 0-100; wired reads as a full-strength connection.
    readonly property int strength: root.wiredConnected
        ? 100 : Shell.NetworkService.signalPercent

    // impasto's WifiCard/island/cards/WifiCard.qml (bar/island/
    // NetworkDetail.qml) needs impasto's own NetworkService shape beyond
    // the summary fields above: a scannable network list, radio state, and
    // connect/disconnect. All real, via Quickshell.Networking's WifiNetwork
    // objects (services/NetworkService.qml's `wifiNetworks`) -- `_ref`
    // keeps the real object so connect()/disconnect() below can call its
    // actual connect()/connectWithPsk()/disconnect() rather than
    // re-deriving them from the plain ssid string.
    readonly property bool radioOn: Shell.NetworkService.wifiEnabled
    readonly property bool scanning: Shell.NetworkService.scanning
    readonly property var networks: Shell.NetworkService.wifiNetworks.map(network => ({
        ssid: network.name,
        signal: Math.round((network.signalStrength || 0) * 100),
        secure: Shell.NetworkService.isSecured(network),
        known: !!network.known,
        active: !!network.connected,
        _ref: network
    }))
    // The network whose connect/disconnect is currently in flight --
    // Quickshell.Networking's own `stateChanging` per network, not a flag
    // this adapter tracks itself.
    readonly property string busySsid: {
        const changing = Shell.NetworkService.wifiNetworks.find(
            network => network.stateChanging)
        return changing ? changing.name : ""
    }

    function strengthIcon(percent: real): string {
        return Shell.NetworkService.strengthIcon(percent)
    }

    function setWifi(value: bool): void {
        Shell.NetworkService.setWifiEnabled(value)
    }

    // impasto's own `scan(force)` distinguishes "make sure scanning is on"
    // from "force an immediate rescan"; the real backend only exposes an
    // enabled/disabled scanner (services/NetworkService.qml's
    // `setScanning`), so both branches just ensure it's on -- a real,
    // disclosed capability gap, not a fabricated forced-rescan.
    function scan(force: bool): void {
        Shell.NetworkService.setScanning(true)
    }

    function findNetwork(ssid: string): var {
        return Shell.NetworkService.wifiNetworks.find(network => network.name === ssid) || null
    }

    function connect(ssid: string, password = ""): void {
        const network = root.findNetwork(ssid)
        if (network)
            Shell.NetworkService.selectWifiNetwork(network, password)
    }

    function disconnect(ssid: string): void {
        const network = root.findNetwork(ssid)
        if (network)
            Shell.NetworkService.disconnectWifiNetwork(network)
    }
}
