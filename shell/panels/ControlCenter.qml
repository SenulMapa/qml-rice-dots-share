// DEPRECATED (13 Sep 2026): superseded by dashboard + satellites
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../components"
import "../core"
import "../services"

Item {
    id: root

    // ---- Wi-Fi / Bluetooth / Audio satellites ----
    // Open/close state used to live here. It now lives on
    // island/IslandExpanded.qml (satelliteController below) so the
    // satellites work from the overview page too, not just this
    // (deprecated, unrouted) page -- see HANDOVER.md. These become
    // thin read-through aliases so the tile grid/tray row further down
    // this file still compile and render even though nothing routes here
    // any more.
    property var satelliteController: null
    readonly property bool wifiSatelliteOpen:
        satelliteController ? satelliteController.wifiSatelliteVisible : false
    readonly property bool bluetoothSatelliteOpen:
        satelliteController ? satelliteController.bluetoothSatelliteVisible : false
    readonly property bool audioSatelliteOpen:
        satelliteController ? satelliteController.audioSatelliteVisible : false

    // Tray menu -- shares the same right satellite as Bluetooth/Audio (see
    // island/Island.qml's bluetoothSatellite), so only one of the three is
    // ever open. trayActiveItem is the SystemTrayItem whose menu is showing;
    // null means the tray satellite is closed.
    readonly property var trayActiveItem:
        satelliteController ? satelliteController.traySatelliteItem : null
    readonly property bool traySatelliteOpen: trayActiveItem !== null

    property var wifiCredentialNetwork: null
    property string wifiPassword: ""
    property bool wifiAutomatic: true
    property bool wifiModeStaged: false
    property string automaticWifiDnsServers: ""
    property string manualWifiDnsServers: ""
    property string manualWifiAddress: ""
    property string manualWifiGateway: ""

    property var wifiInformationOption: null
    property var bluetoothInformationOption: null

    readonly property bool wifiCredentialsActive: wifiCredentialNetwork !== null
    readonly property bool wifiInformationViewActive: wifiInformationOption !== null
    readonly property bool bluetoothInformationViewActive: bluetoothInformationOption !== null

    // The Audio satellite's two groups (see components/ControlDetailPanel.qml).
    // Monitor sources (".monitor") are PipeWire's loopback-capture nodes for
    // each sink, not real input devices, so they're excluded from INPUT.
    readonly property var audioOutputDevices: AudioService.outputDevices
    readonly property var audioInputDevices: AudioService.inputDevices.filter(
        node => !(node?.name || "").endsWith(".monitor"))

    // How tall the panel's own content wants to be right now -- header, tile
    // grid, sliders, the media card (which may itself be mid-spring into its
    // lyrics-expanded height) and up to 3 notifications. island/
    // IslandController.qml reads this through IslandExpanded to size the
    // surface, so the island tracks a MOVING target exactly like it already
    // does for its own geometry -- no separate progress/duration plumbing.
    readonly property alias contentHeight: mainColumn.implicitHeight

    signal backRequested()

    function toggleSection(section: string): void {
        toggleSatellite(section)
    }

    function closeWifiSatellite(): void {
        clearWifiCredentials()
        clearInformationView("wifi")
        if (satelliteController && wifiSatelliteOpen)
            satelliteController.toggleSatellite("wifi")
    }

    function closeBluetoothSatellite(): void {
        clearInformationView("bluetooth")
        if (satelliteController && bluetoothSatelliteOpen)
            satelliteController.toggleSatellite("bluetooth")
    }

    function closeAudioSatellite(): void {
        if (satelliteController && audioSatelliteOpen)
            satelliteController.toggleSatellite("audio")
    }

    function toggleSatellite(section: string): void {
        if (satelliteController)
            satelliteController.toggleSatellite(section)
    }

    function closeTrayMenu(): void {
        if (satelliteController && traySatelliteOpen)
            satelliteController.closeSatellite()
    }

    // Left/right click on a tray icon (panels/ControlCenter.qml's own tray
    // row below); toggles the same item's menu shut, or switches to a
    // different item's menu, closing Bluetooth/Audio the same way they
    // already close each other.
    function toggleTrayMenu(item): void {
        if (satelliteController)
            satelliteController.toggleSatellite("tray:" + item.id)
    }

    function closeAnySubview(): bool {
        if (wifiCredentialsActive) { clearWifiCredentials(); return true }
        if (wifiInformationViewActive) { clearInformationView("wifi"); return true }
        if (bluetoothInformationViewActive) { clearInformationView("bluetooth"); return true }
        return false
    }

    // The general "close the deepest open layer" used by Escape AND the
    // panel's own back button: a subview first (in whichever satellite has
    // one open), then all satellites.
    function closeExpandedSection(): bool {
        if (closeAnySubview())
            return true
        if (wifiSatelliteOpen || bluetoothSatelliteOpen || audioSatelliteOpen || traySatelliteOpen) {
            if (satelliteController)
                satelliteController.closeSatellite()
            return true
        }
        return false
    }

    function resetDetails(): void {
        clearWifiCredentials()
        clearInformationView("wifi")
        clearInformationView("bluetooth")
        if (satelliteController)
            satelliteController.closeSatellite()
    }

    function detailTitle(section: string): string {
        if (section === "wifi")
            return "Wi-Fi"
        if (section === "bluetooth")
            return "Bluetooth"
        if (section === "audio")
            return "Audio"
        if (section === "energy")
            return "Energy"
        return ""
    }

    function detailModelFor(section: string): var {
        if (section === "audio")
            return AudioService.outputDevices
        if (section === "wifi") {
            const networks = NetworkService.wifiNetworks.slice()
            networks.sort((a, b) => Number(b.connected) - Number(a.connected)
                || Number(b.known) - Number(a.known)
                || (b.signalStrength || 0) - (a.signalStrength || 0))
            return networks
        }
        if (section === "bluetooth")
            return BluetoothService.discoverableDevices
        return []
    }

    function optionTitle(option, section: string): string {
        if (section === "audio")
            return AudioService.displayName(option, "Audio device")
        if (section === "wifi")
            return option?.name || "Unnamed network"
        return BluetoothService.deviceName(option)
    }

    function optionDetail(option, section: string): string {
        if (section === "audio")
            return Math.round((option?.audio?.volume || 0) * 100) + "%"
        if (section === "wifi") {
            if (option?.connected)
                return "Connected"
            if (option?.stateChanging)
                return "Connecting…"
            const strength = Math.round((option?.signalStrength || 0) * 100) + "%"
            if (option?.known)
                return "Saved · " + strength
            return NetworkService.securityLabel(option) + " · " + strength
        }
        if (option?.connected) {
            const battery = option.batteryAvailable
                ? " · " + Math.round(option.battery * 100) + "%" : ""
            return "Connected" + battery
        }
        if (option?.pairing)
            return "Pairing…"
        return option?.paired || option?.bonded ? "Connect" : "Pair"
    }

    function optionSelected(option, section: string, group: string): bool {
        if (section === "audio")
            return group === "input"
                ? option?.id === AudioService.source?.id
                : option?.id === AudioService.sink?.id
        return option?.connected ?? false
    }

    function optionAvailable(option, section: string): bool {
        if (section === "wifi")
            return NetworkService.canSelectNetwork(option)
        if (section === "bluetooth")
            return option !== null && option !== undefined && !option.blocked
        return option !== null && option !== undefined
    }

    function activateOption(option, section: string, group: string): void {
        if (section === "audio") {
            if (group === "input")
                AudioService.setInputDevice(option)
            else
                AudioService.setOutputDevice(option)
        }
        else if (section === "wifi") {
            if (NetworkService.requiresPassword(option)) {
                wifiCredentialNetwork = option
                wifiPassword = ""
            } else {
                NetworkService.selectWifiNetwork(option)
            }
        }
        else if (section === "bluetooth")
            BluetoothService.activateDevice(option)
    }

    function clearWifiCredentials(): void {
        wifiCredentialNetwork = null
        wifiPassword = ""
    }

    function clearInformationView(section: string): void {
        if (section === "wifi") {
            wifiInformationOption = null
            NetworkService.closeActiveWifiProfile()
        } else if (section === "bluetooth") {
            bluetoothInformationOption = null
        }
    }

    function closeDetailSubview(section: string): void {
        if (section === "wifi")
            clearWifiCredentials()
        clearInformationView(section)
    }

    function showInformation(section: string, option): void {
        if (!option || (section !== "wifi" && section !== "bluetooth"))
            return
        if (section === "wifi") {
            clearWifiCredentials()
            if (!NetworkService.openActiveWifiProfile(option))
                return
            wifiInformationOption = option
            wifiModeStaged = false
            syncWifiDnsProfile()
        } else {
            bluetoothInformationOption = option
        }
    }

    function informationOptionFor(section: string): var {
        return section === "wifi" ? wifiInformationOption
            : section === "bluetooth" ? bluetoothInformationOption : null
    }

    function informationTitle(section: string): string {
        const option = informationOptionFor(section)
        return option ? optionTitle(option, section) : detailTitle(section)
    }

    function informationRows(section: string): var {
        const option = informationOptionFor(section)
        if (!option)
            return []
        if (section === "wifi") {
            return [
                { label: "Status", value: option.connected ? "Connected"
                    : option.known ? "Saved" : "Available" },
                { label: "Signal", value: Math.round((option.signalStrength || 0) * 100) + "%" },
                { label: "Security", value: NetworkService.securityLabel(option) },
                { label: "Profile", value: option.known ? "Remembered" : "Not saved" }
            ]
        }
        return [
            { label: "Status", value: option.connected ? "Connected"
                : option.paired || option.bonded ? "Paired" : "Nearby" },
            { label: "Address", value: option.address || "Unavailable" },
            { label: "Trusted", value: option.trusted ? "Yes" : "No" },
            { label: "Battery", value: option.batteryAvailable
                ? Math.round(option.battery * 100) + "%" : "Unavailable" }
        ]
    }

    // ---- Wi-Fi/Bluetooth information-view actions ----
    // The details subview only ever opens for the CONNECTED wifi network
    // (openActiveWifiProfile requires network.connected) or a paired/
    // connected bluetooth device, so the primary pill is always meaningful.
    // network.forget()/.disconnect() and device.disconnect()/.forget() are
    // native Quickshell calls (WifiNetwork / BluetoothDevice) -- see
    // services/NetworkService.qml and services/BluetoothService.qml.
    function primaryDetailActionLabel(section: string): string {
        if (section === "wifi")
            return wifiInformationOption ? "Forget" : ""
        if (section === "bluetooth") {
            const option = bluetoothInformationOption
            if (!option)
                return ""
            return option.connected ? "Disconnect" : "Forget"
        }
        return ""
    }

    function secondaryDetailActionLabel(section: string): string {
        if (section === "wifi")
            return wifiInformationOption?.connected ? "Disconnect" : ""
        if (section === "bluetooth") {
            const option = bluetoothInformationOption
            return option?.connected && (option.paired || option.bonded)
                ? "Forget" : ""
        }
        return ""
    }

    function invokePrimaryDetailAction(section: string): void {
        if (section === "wifi") {
            if (NetworkService.forgetWifiNetwork(wifiInformationOption))
                clearInformationView("wifi")
        } else if (section === "bluetooth") {
            const option = bluetoothInformationOption
            const ok = option?.connected
                ? BluetoothService.disconnectDevice(option)
                : BluetoothService.forgetDevice(option)
            if (ok)
                clearInformationView("bluetooth")
        }
    }

    function invokeSecondaryDetailAction(section: string): void {
        if (section === "wifi") {
            if (NetworkService.disconnectWifiNetwork(wifiInformationOption))
                clearInformationView("wifi")
        } else if (section === "bluetooth") {
            if (BluetoothService.forgetDevice(bluetoothInformationOption))
                clearInformationView("bluetooth")
        }
    }

    function submitWifiPassword(): void {
        if (!wifiCredentialNetwork || wifiPassword.length < 8)
            return
        if (NetworkService.selectWifiNetwork(wifiCredentialNetwork, wifiPassword))
            clearWifiCredentials()
    }

    function syncWifiDnsProfile(): void {
        const profileAutomatic = NetworkService.wifiProfile.automaticAddress
            && NetworkService.wifiProfile.automaticDns
        if (!wifiModeStaged)
            wifiAutomatic = profileAutomatic
        automaticWifiDnsServers = NetworkService.wifiRuntime.dnsServers
            || NetworkService.wifiProfile.automaticDnsServers
            || NetworkService.wifiProfile.manualDnsServers || "Unavailable"
        if (wifiAutomatic || manualWifiDnsServers.length === 0)
            manualWifiDnsServers = NetworkService.wifiProfile.manualDnsServers || ""
        if (wifiAutomatic || manualWifiAddress.length === 0)
            manualWifiAddress = NetworkService.wifiRuntime.address
                || (NetworkService.wifiProfile.address === "Unavailable"
                    ? "" : NetworkService.wifiProfile.address || "")
        if (wifiAutomatic || manualWifiGateway.length === 0)
            manualWifiGateway = NetworkService.wifiRuntime.gateway
                || (NetworkService.wifiProfile.gateway === "Unavailable"
                    ? "" : NetworkService.wifiProfile.gateway || "")
    }

    function toggleWifiMode(): void {
        if (NetworkService.wifiProfileSaving)
            return
        if (wifiAutomatic) {
            if (manualWifiDnsServers.length === 0)
                manualWifiDnsServers = automaticWifiDnsServers === "Unavailable"
                    ? "" : automaticWifiDnsServers
            manualWifiAddress = NetworkService.wifiRuntime.address
                || manualWifiAddress
            manualWifiGateway = NetworkService.wifiRuntime.gateway
                || manualWifiGateway
            wifiAutomatic = false
            wifiModeStaged = true
            return
        }
        manualAddressSave.stop()
        if (NetworkService.applyActiveWifiAutomatic()) {
            wifiAutomatic = true
            wifiModeStaged = false
        }
    }

    function saveManualWifiDns(): void {
        if (!wifiAutomatic
                && NetworkService.applyActiveWifiDns(
                    false, manualWifiDnsServers))
            wifiModeStaged = false
    }

    function saveManualWifiAddress(): void {
        if (!wifiAutomatic)
            manualAddressSave.restart()
    }

    function validIpv4(value: string): bool {
        return NetworkService.ipv4Number(value) >= 0
    }

    function toggleDiscovery(section: string): void {
        if (section === "wifi")
            NetworkService.setScanning(!NetworkService.scanning)
        else if (section === "bluetooth")
            BluetoothService.setDiscovering(!BluetoothService.discovering)
    }

    // Scanning side effects now live on island/IslandExpanded.qml
    // (onWifiSatelliteVisibleChanged/onBluetoothSatelliteVisibleChanged),
    // since satelliteController is the real owner of open/close state.

    Timer {
        id: manualAddressSave
        interval: 140
        onTriggered: {
            if (!root.wifiAutomatic
                    && NetworkService.applyActiveWifiAddress(
                        root.manualWifiAddress, root.manualWifiGateway))
                root.wifiModeStaged = false
        }
    }

    Connections {
        target: NetworkService
        function onWifiProfileChanged() {
            if (root.wifiInformationViewActive)
                root.syncWifiDnsProfile()
        }
        function onWifiRuntimeChanged() {
            if (root.wifiInformationViewActive)
                root.syncWifiDnsProfile()
        }
    }

    onVisibleChanged: {
        if (!visible) {
            NetworkService.setScanning(false)
            BluetoothService.setDiscovering(false)
            resetDetails()
        }
    }

    Component.onDestruction: {
        NetworkService.setScanning(false)
        BluetoothService.setDiscovering(false)
    }

    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        // IslandExpanded's own ColumnLayout already insets every page by
        // Theme.space4 (16 px at density 1) from the surface edge. The
        // Phase A spec's panel padding is Theme.u(0.555) (24 px) -- the
        // remainder on top of that shared inset, so the control centre
        // reads as a panel 11u wide with 9.88u of content, matching the
        // prototype, without touching the other pages' padding.
        anchors.leftMargin: Math.max(0, Theme.u(0.555) - Theme.space4)
        anchors.rightMargin: Math.max(0, Theme.u(0.555) - Theme.space4)
        spacing: Theme.u(0.28)

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.u(0.3)

            Rectangle {
                Layout.preferredWidth: Theme.u(0.76)
                Layout.preferredHeight: Theme.u(0.76)
                radius: width / 2
                color: Theme.surfaceContainer

                BackArrowIcon {
                    anchors.centerIn: parent
                    // Nudged half a pixel toward the vertex: an arrow's
                    // visual weight sits in the head, so true geometric
                    // centring reads as slightly right-shifted.
                    anchors.horizontalCenterOffset: -1
                    color: AdaptiveColor.glassText
                    size: Theme.u(0.34)
                }

                HoverHandler { id: backHover }
                TapHandler { onTapped: root.backRequested() }
            }

            Text {
                text: "Control Center"
                color: AdaptiveColor.glassText
                font.family: Config.appearance.displayFontFamily
                font.pixelSize: Theme.u(0.46)
                font.weight: Font.Normal
                font.letterSpacing: Theme.u(0.46) * -0.02
            }

            Item { Layout.fillWidth: true }
        }

        GridLayout {
            id: tileGrid
            Layout.fillWidth: true
            columns: 3
            rowSpacing: Theme.u(0.28)
            columnSpacing: Theme.u(0.28)

            ControlTile {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.u(1.3)
                title: "Wifi"
                detail: NetworkService.wifiConnected
                    ? NetworkService.ssid : NetworkService.wifiEnabled ? "On" : "Off"
                icon: NetworkService.icon
                checked: NetworkService.wifiEnabled
                available: NetworkService.wifiAvailable
                expandable: NetworkService.wifiAvailable
                expanded: root.wifiSatelliteOpen
                onActivated: root.toggleSatellite("wifi")
                onToggleRequested: NetworkService.toggleWifi()
            }

            ControlTile {
                Layout.fillWidth: true
                Layout.columnSpan: 2
                Layout.preferredHeight: Theme.u(1.3)
                title: "Audio"
                detail: AudioService.available ? AudioService.outputName : "No output"
                icon: AudioService.muted ? "󰝟" : "󰕾"
                checked: !AudioService.muted && AudioService.available
                available: AudioService.available
                expandable: AudioService.available
                expanded: root.audioSatelliteOpen
                onActivated: root.toggleSatellite("audio")
                onToggleRequested: AudioService.toggleMute()
            }

            ControlTile {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.u(1.3)
                title: "Bluetooth"
                detail: BluetoothService.detailLabel
                icon: BluetoothService.icon
                checked: BluetoothService.enabled
                available: BluetoothService.available && !BluetoothService.blocked
                expandable: BluetoothService.available && !BluetoothService.blocked
                expanded: root.bluetoothSatelliteOpen
                onActivated: root.toggleSatellite("bluetooth")
                onToggleRequested: BluetoothService.toggleEnabled()
            }

            ControlTile {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.u(1.3)
                title: "Peace"
                detail: NotificationService.doNotDisturb ? "On" : "Off"
                icon: NotificationService.doNotDisturb ? "󰂛" : "󰂚"
                checked: NotificationService.doNotDisturb
                expandable: false
                onActivated: NotificationService.toggleDoNotDisturb()
            }

            ControlTile {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.u(1.3)
                title: "Night Light"
                detail: !NightLightService.available ? "Unavailable"
                    : NightLightService.enabled ? "On" : "Off"
                icon: "󰖔"
                checked: NightLightService.enabled
                available: NightLightService.available
                expandable: false
                onActivated: NightLightService.toggle()
            }
        }

        LevelControl {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.u(1.2)
            icon: AudioService.muted ? "󰝟" : "󰕾"
            level: AudioService.volume
            available: AudioService.available
            onLevelRequested: level => AudioService.setVolume(Math.round(level * 100))
            onActionRequested: AudioService.toggleMute()
        }

        LevelControl {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.u(1.2)
            visible: BrightnessService.available
            icon: "󰃟"
            level: BrightnessService.level
            available: BrightnessService.available
            onLevelRequested: level => BrightnessService.setBrightness(Math.round(level * 100))
        }

        // Takes the slot brightness vacates on a machine with no backlight.
        LevelControl {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.u(1.2)
            visible: !BrightnessService.available
            icon: AudioService.microphoneMuted ? "󰍭" : "󰍬"
            level: AudioService.microphoneVolume
            available: AudioService.microphoneAvailable
            onLevelRequested: level => AudioService.setMicrophoneVolume(Math.round(level * 100))
            onActionRequested: AudioService.toggleMicrophoneMute()
        }

        MediaCard {
            Layout.fillWidth: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: NotificationService.count > 0
            spacing: Theme.u(0.2)

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "NOTIFICATIONS"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.u(0.26)
                    font.letterSpacing: Theme.u(0.26) * 0.1
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Clear all"
                    color: AdaptiveColor.activeFill
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.u(0.26)
                    font.weight: Font.Medium

                    HoverHandler { id: clearAllHover }
                    TapHandler { onTapped: NotificationService.clearHistory() }
                }
            }

            Repeater {
                model: NotificationService.history.slice(0, 3)
                delegate: NotificationCard {
                    required property var modelData
                    Layout.fillWidth: true
                    entry: modelData
                }
            }
        }

        // ---- System tray ----
        // A calm, flat row under the notifications list: a dim label, then
        // icons. Nothing at all (no label, no gap) when there are no items.
        // Menu opens in the right satellite (island/Island.qml,
        // components/TraySatellitePanel.qml) -- never a floating popup.
        ColumnLayout {
            Layout.fillWidth: true
            visible: SystemTray.items.values.length > 0
            spacing: Theme.u(0.2)

            Text {
                text: "In the background"
                color: AdaptiveColor.glassTextDim
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Theme.textSmall
            }

            RowLayout {
                spacing: Theme.u(0.3)

                Repeater {
                    model: SystemTray.items.values
                    delegate: Item {
                        required property var modelData
                        width: Theme.u(0.5)
                        height: Theme.u(0.5)

                        IconImage {
                            anchors.fill: parent
                            source: modelData.icon
                            asynchronous: true
                        }

                        HoverHandler { id: trayIconHover }
                        // left -> activate() (or open the menu if onlyMenu);
                        // middle -> secondaryActivate(); right -> open menu.
                        // Never actually tapped during this task -- see
                        // HANDOVER: activating a real entry changes real
                        // application state (raises/quits the app).
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: modelData.onlyMenu
                                ? root.toggleTrayMenu(modelData) : modelData.activate()
                        }
                        TapHandler {
                            acceptedButtons: Qt.MiddleButton
                            onTapped: modelData.secondaryActivate()
                        }
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: root.toggleTrayMenu(modelData)
                        }

                        Rectangle {
                            visible: trayIconHover.hovered
                            x: (parent.width - width) / 2
                            y: -height - Theme.u(0.08)
                            width: trayTip.implicitWidth + Theme.u(0.2)
                            height: trayTip.implicitHeight + Theme.u(0.1)
                            radius: Theme.u(0.1)
                            color: Theme.surfaceContainerHigh

                            Text {
                                id: trayTip
                                anchors.centerIn: parent
                                text: modelData.tooltipTitle || modelData.title || modelData.id
                                color: AdaptiveColor.glassText
                                font.family: Config.appearance.fontFamily
                                font.pixelSize: Theme.u(0.22)
                            }
                        }
                    }
                }
            }
        }
    }
}
