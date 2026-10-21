// Simplified port of impasto's bar/island/BluetoothDetail.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// The Bluetooth device list, real data via the shell's own
// services/BluetoothService.qml. Tapping a device toggles its connection
// (toggleDeviceConnection handles pair/connect/disconnect on this shell's
// BlueZ backend already).

import QtQuick
import QtQuick.Layouts
import "../desktop/services" as Desk
import "../services" as Shell
import "components" as DashComponents

ColumnLayout {
    id: root

    property bool backable: true
    signal back()

    spacing: 8

    Component.onCompleted: Shell.BluetoothService.setDiscovering(true)
    Component.onDestruction: Shell.BluetoothService.setDiscovering(false)

    RowLayout {
        Layout.fillWidth: true

        Text {
            Layout.fillWidth: true
            text: "Bluetooth"
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: Desk.DeskTheme.fontSizeSmall
            font.weight: Font.DemiBold
            color: Desk.DeskTheme.text
        }

        DashComponents.QuickTile {
            Layout.preferredWidth: 90
            Layout.preferredHeight: 32
            label: Shell.BluetoothService.enabled ? "On" : "Off"
            active: Shell.BluetoothService.enabled
            onToggled: Shell.BluetoothService.toggleEnabled()
        }
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 4
        visible: Shell.BluetoothService.enabled
        model: Shell.BluetoothService.devices

        delegate: DashComponents.QuickTile {
            required property var modelData
            width: ListView.view ? ListView.view.width : 0
            height: 52
            icon: Shell.BluetoothService.deviceIcon(modelData)
            label: Shell.BluetoothService.deviceName(modelData)
            detail: modelData.connected ? "Connected" : (modelData.paired ? "Paired" : "Available")
            active: modelData.connected ?? false
            available: !Shell.BluetoothService.deviceBusy(modelData)
            onToggled: Shell.BluetoothService.toggleDeviceConnection(modelData)
        }
    }

    DashComponents.QuickTile {
        Layout.fillWidth: true
        Layout.preferredHeight: 36
        visible: root.backable
        label: "Back"
        icon: "󰅁"
        onToggled: root.back()
    }
}
