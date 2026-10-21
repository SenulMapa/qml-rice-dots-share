// Simplified port of impasto's bar/island/NetworkDetail.qml
// (github.com/andreumassanet/impasto, GPL-3.0, Andreu Massanet).
//
// The Wi-Fi list, real scan data via the shell's own
// services/NetworkService.qml (NetworkManager). Tapping an open network
// connects immediately; a secured one that needs a password is flagged
// rather than given its own credential-entry flow here -- the shell's
// existing satellite (panels/ControlCenter.qml's wifi satellite) already
// owns that flow end to end and this port does not duplicate it (per the
// brief: reuse real services, don't re-derive what the shell already has).

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

    Component.onCompleted: Shell.NetworkService.setScanning(true)
    Component.onDestruction: Shell.NetworkService.setScanning(false)

    RowLayout {
        Layout.fillWidth: true

        Text {
            Layout.fillWidth: true
            text: "Wi-Fi"
            font.family: Desk.DeskTheme.fontFamily
            font.pixelSize: Desk.DeskTheme.fontSizeSmall
            font.weight: Font.DemiBold
            color: Desk.DeskTheme.text
        }

        DashComponents.QuickTile {
            Layout.preferredWidth: 90
            Layout.preferredHeight: 32
            label: Shell.NetworkService.wifiEnabled ? "On" : "Off"
            active: Shell.NetworkService.wifiEnabled
            onToggled: Shell.NetworkService.toggleWifi()
        }
    }

    ListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 4
        visible: Shell.NetworkService.wifiEnabled
        model: Shell.NetworkService.wifiNetworks

        delegate: DashComponents.QuickTile {
            required property var modelData
            width: ListView.view ? ListView.view.width : 0
            height: 52
            icon: Shell.NetworkService.strengthIcon(modelData.strength ?? 0)
            label: modelData.name ?? modelData.ssid ?? ""
            detail: modelData.connected ? "Connected"
                : (Shell.NetworkService.requiresPassword(modelData) ? "Secured" : "Open")
            active: modelData.connected ?? false
            onToggled: {
                if (modelData.connected)
                    Shell.NetworkService.disconnectWifiNetwork(modelData)
                else if (!Shell.NetworkService.requiresPassword(modelData))
                    Shell.NetworkService.selectWifiNetwork(modelData)
                // Secured, not-yet-known networks: left to the shell's own
                // wifi satellite, which has the real password prompt.
            }
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
