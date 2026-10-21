import QtQuick
import QtQuick.Layouts
import "../core"
import "../services"

// Satellite content for exactly ONE section (wifi/bluetooth/audio) at a
// time. The caller (island/Island.qml) wraps this in a Surface -- which
// already carries the gradient/sheen/hairline the prototype specifies -- so
// this component itself owns no background of its own, only the padded
// content: header, row list, and the Wi-Fi credential/information subviews.
Item {
    id: root

    required property var controller
    required property string section

    // Lucide names for ConnectivityRow leading icons (ink). Mirrors the
    // glyph mapping in NetworkService.strengthIcon / BluetoothService.deviceIcon.
    function wifiIconName(option): string {
        const pct = Math.round((option?.signalStrength ?? 0) * 100);
        return pct >= 60 ? "wifi-high" : pct >= 25 ? "wifi-low" : "wifi-zero";
    }
    function bluetoothIconName(device): string {
        let hint = "";
        try { hint = device?.icon || ""; } catch (e) { hint = ""; }
        const identity = (hint + " " + BluetoothService.deviceName(device)).toLowerCase();
        if (identity.includes("head") || identity.includes("audio") || identity.includes("airpod"))
            return "headphones";
        if (identity.includes("mouse")) return "mouse";
        if (identity.includes("keyboard")) return "keyboard";
        if (identity.includes("watch")) return "watch";
        if (identity.includes("phone")) return "smartphone";
        return "bluetooth";
    }

    readonly property var informationOption: controller.informationOptionFor(section)
    readonly property bool wifiCredentialsActive:
        section === "wifi" && controller.wifiCredentialsActive
    readonly property bool informationViewActive: informationOption !== null
    readonly property bool detailSubviewActive: wifiCredentialsActive || informationViewActive
    readonly property var detailModel: controller.detailModelFor(section)
    readonly property bool scanning: section === "wifi" ? NetworkService.scanning
        : section === "bluetooth" ? BluetoothService.discovering : false
    readonly property bool canScan: section === "wifi" || section === "bluetooth"

    // Ink (showcase satellites.html): monochrome text on black, an opaque
    // fillOn accent, inkRaised chips, and no filled overlays. Glass keeps
    // the wallpaper-derived colours and surfaces.
    readonly property color paneText: Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText
    readonly property color paneTextDim: Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim
    readonly property color paneCaption: Config.appearance.ink ? Theme.t3 : Theme.outline
    readonly property color paneAccent: Config.appearance.ink ? Theme.fillOn : AdaptiveColor.activeFill
    readonly property color paneAccentText: Config.appearance.ink ? Theme.glyphOn : Theme.accentFillText
    readonly property color paneChip: Config.appearance.ink ? Theme.inkRaised : Theme.surfaceContainerLow
    readonly property color paneOverlay: Config.appearance.ink ? Qt.rgba(0, 0, 0, 0) : Theme.surfaceContainer
    readonly property string paneFont: Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily

    // A satellite sizes to header + all rows + bottom padding, up to this
    // ceiling -- past it the row list scrolls internally instead of the
    // satellite growing past the screen. Set here (not Config) for the same
    // reason satellite width lives at the island/Island.qml call sites: a
    // Phase A design-unit value has no business in the Theme-independent
    // Config singleton.
    readonly property real maxHeight: Theme.u(9.5)
    // Audio adds up to two volume sliders (output/input) above the row
    // list -- see the LevelControls below -- so its chrome is taller.
    readonly property real chromeHeight: Theme.u(0.51) * 2
        + headerRow.implicitHeight + chromeColumn.spacing
        + (section === "audio"
            ? (Theme.u(1.2) * 2 + chromeColumn.spacing * 2) : 0)
    readonly property real rowsCap: Math.max(Theme.u(1.6), maxHeight - chromeHeight)

    // The satellite's REAL content height (see island/Island.qml). This
    // used to be `chromeColumn.implicitHeight` alone, which -- despite the
    // commit that introduced it calling this a real measurement -- silently
    // dropped the ColumnLayout's own anchors.topMargin/bottomMargin
    // (Theme.u(0.51) each): implicitHeight is a Layout's natural CONTENT
    // size, never the margins used to position it within its parent. The
    // other half of the same clipping bug was the row list itself: a
    // virtualizing ListView bound its own height to its own contentHeight
    // (Layout.preferredHeight: Math.max(contentHeight, ...)), which is
    // circular -- a ListView only instantiates delegates within its
    // CURRENT height plus cache buffer, so a small starting height (or a
    // freshly reassigned model, see detailModelFor()'s new arrays) measures
    // a small contentHeight, which keeps the height small. Rows below now
    // come from a plain Repeater in a ColumnLayout -- never virtualized, so
    // its implicitHeight is exact and immediate, including through a scan
    // adding/removing rows -- inside a Flickable that only scrolls once the
    // natural height exceeds rowsCap.
    readonly property int contentHeight: Math.round(chromeColumn.implicitHeight
        + Theme.u(0.51) * 2)

    ColumnLayout {
        id: chromeColumn
        anchors.fill: parent
        anchors.topMargin: Theme.u(0.51)
        anchors.bottomMargin: Theme.u(0.51)
        anchors.leftMargin: Theme.u(0.44)
        anchors.rightMargin: Theme.u(0.44)
        spacing: Theme.u(0.2)

        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: Theme.u(0.2)

            Rectangle {
                visible: root.detailSubviewActive
                Layout.preferredWidth: Theme.u(0.5)
                Layout.preferredHeight: Theme.u(0.5)
                radius: width / 2
                color: Config.appearance.ink ? Theme.inkRaised : Theme.surfaceContainer

                BackArrowIcon {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -1
                    color: root.paneTextDim
                    size: Theme.u(0.24)
                }
                HoverHandler { id: detailBackHover }
                TapHandler { onTapped: root.controller.closeDetailSubview(root.section) }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    id: headerTitle
                    text: root.informationViewActive ? root.controller.informationTitle(root.section)
                        : root.wifiCredentialsActive
                            ? (root.controller.wifiCredentialNetwork?.name || "Wi-Fi password")
                            : root.controller.detailTitle(root.section)
                    color: root.paneText
                    font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.displayFontFamily
                    font.pixelSize: Config.appearance.ink ? 20 : Theme.u(0.58)
                    font.weight: Config.appearance.ink ? Font.DemiBold : Font.Normal
                    font.letterSpacing: Config.appearance.ink ? -0.3 : 0

                    TapHandler {
                        enabled: !root.detailSubviewActive && root.canScan
                        onTapped: root.controller.toggleDiscovery(root.section)
                    }
                }
                Text {
                    visible: !root.detailSubviewActive && root.scanning
                    text: Config.appearance.ink ? "Scanning" : "SCANNING"
                    color: root.paneCaption
                    font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.monoFontFamily
                    font.pixelSize: Config.appearance.ink ? 12 : Theme.u(0.26)
                    font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
                    font.letterSpacing: Config.appearance.ink ? 0 : Theme.u(0.26) * 0.1
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                visible: root.informationViewActive && root.section === "wifi"
                spacing: Theme.u(0.15)

                Repeater {
                    model: [
                        { label: "Automatic", automatic: true },
                        { label: "Manual", automatic: false }
                    ]
                    delegate: Squircle {
                        required property var modelData
                        Layout.preferredWidth: Theme.u(1.6)
                        Layout.preferredHeight: Theme.u(0.5)
                        radius: Config.appearance.ink ? Theme.rCtl : Theme.u(0.15)
                        opacity: NetworkService.wifiProfileSaving ? 0.55 : 1
                        color: root.controller.wifiAutomatic === modelData.automatic
                            ? (Config.appearance.ink ? Theme.fillOn : AdaptiveColor.activeFill) : (Config.appearance.ink ? Theme.inkRaised : Theme.surfaceContainerLow)

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.controller.wifiAutomatic === modelData.automatic
                                ? (Config.appearance.ink ? Theme.glyphOn : Theme.accentFillText)
                                : (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
                            font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                            font.pixelSize: Theme.u(0.26)
                            font.weight: Font.DemiBold
                        }
                        TapHandler {
                            enabled: !NetworkService.wifiProfileSaving
                                && root.controller.wifiAutomatic
                                    !== modelData.automatic
                            onTapped: root.controller.toggleWifiMode()
                        }
                    }
                }
            }

            Rectangle {
                visible: !root.detailSubviewActive && root.canScan
                Layout.preferredWidth: Theme.u(0.5)
                Layout.preferredHeight: Theme.u(0.5)
                radius: width / 2
                color: Config.appearance.ink ? Theme.inkRaised : Theme.surfaceContainer

                Text {
                    id: scanGlyph
                    anchors.centerIn: parent
                    text: "󰑐"
                    // Geist Mono is missing this Nerd Font codepoint (it
                    // rendered as an unrelated glyph); WeatherPage.qml and
                    // ClipboardPage.qml already use the exact same "󰑐"
                    // refresh icon on the UI font (Geist) successfully, so
                    // this matches a proven-working call site rather than
                    // gambling on a second icon font.
                    color: root.paneText
                    font.family: root.paneFont
                    font.pixelSize: Theme.u(0.26)
                    RotationAnimation on rotation {
                        running: root.scanning && !Config.appearance.reducedMotion
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1100
                        onStopped: scanGlyph.rotation = 0
                    }
                }
                HoverHandler { id: scanHover }
                TapHandler { onTapped: root.controller.toggleDiscovery(root.section) }
            }
        }

        // Output/input volume -- lived only in the (now deprecated)
        // ControlCenter page's own sliders; restored here so the Audio
        // satellite is a complete replacement. Never dragged in tests --
        // it changes real system volume. See HANDOVER.md.
        LevelControl {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.u(1.2)
            visible: root.section === "audio" && !root.detailSubviewActive
                && AudioService.available
            icon: AudioService.muted ? "󰝟" : "󰕾"
            iconName: AudioService.muted ? "volume-x" : "volume-2"
            level: AudioService.volume
            available: AudioService.available
            onLevelRequested: level => AudioService.setVolume(Math.round(level * 100))
            onActionRequested: AudioService.toggleMute()
        }

        LevelControl {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.u(1.2)
            visible: root.section === "audio" && !root.detailSubviewActive
                && AudioService.microphoneAvailable
            icon: AudioService.microphoneMuted ? "󰍭" : "󰍬"
            iconName: AudioService.microphoneMuted ? "mic-off" : "mic"
            level: AudioService.microphoneVolume
            available: AudioService.microphoneAvailable
            onLevelRequested: level => AudioService.setMicrophoneVolume(Math.round(level * 100))
            onActionRequested: AudioService.toggleMicrophoneMute()
        }

        Item {
            id: rowsArea
            Layout.fillWidth: true
            Layout.preferredHeight: root.wifiCredentialsActive ? Theme.u(3.4)
                : root.informationViewActive ? Theme.u(root.section === "wifi" ? 6.5 : 5.6)
                : Math.min(rowsColumn.implicitHeight, root.rowsCap)

            Flickable {
                id: rowsScroll
                anchors.fill: parent
                visible: !root.detailSubviewActive
                contentWidth: width
                contentHeight: rowsColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: rowsColumn
                    width: rowsScroll.width
                    spacing: Theme.u(0.3)

                    // ---- Wi-Fi / Bluetooth: a single flat list ----
                    Repeater {
                        model: root.section === "audio" ? [] : root.detailModel
                        delegate: ConnectivityRow {
                            required property var modelData
                            Layout.fillWidth: true
                            title: root.controller.optionTitle(modelData, root.section)
                            detail: root.controller.optionDetail(modelData, root.section)
                            icon: root.section === "wifi"
                                ? NetworkService.strengthIcon(Math.round((modelData.signalStrength ?? 0) * 100))
                                : BluetoothService.deviceIcon(modelData)
                            iconName: root.section === "wifi"
                                ? root.wifiIconName(modelData)
                                : root.bluetoothIconName(modelData)
                            selected: root.controller.optionSelected(modelData, root.section, "")
                            available: root.controller.optionAvailable(modelData, root.section)
                            busy: modelData?.stateChanging || modelData?.pairing || false
                                || (root.section === "bluetooth"
                                    && BluetoothService.deviceBusy(modelData))
                            informationAvailable: (root.section === "wifi"
                                && modelData?.connected) || root.section === "bluetooth"
                            onActivated: {
                                root.controller.activateOption(modelData, root.section, "")
                                if (root.section === "wifi" && root.controller.wifiCredentialsActive)
                                    Qt.callLater(() => wifiPasswordInput.forceActiveFocus())
                            }
                            onInformationRequested: root.controller.showInformation(root.section, modelData)
                        }
                    }

                    // ---- Audio: OUTPUT then INPUT groups ----
                    // Restores the input-device picker lost with the
                    // Microphone tile (Phase A regression) alongside the
                    // pre-existing output list.
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.u(0.1)
                        visible: root.section === "audio"
                            && root.controller.audioOutputDevices.length > 0
                        text: Config.appearance.ink ? "Output" : "OUTPUT"
                        color: root.paneCaption
                        font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.monoFontFamily
                        font.pixelSize: Config.appearance.ink ? 12 : Theme.u(0.26)
                        font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
                        font.letterSpacing: Config.appearance.ink ? 0 : Theme.u(0.26) * 0.1
                    }
                    Repeater {
                        model: root.section === "audio" ? root.controller.audioOutputDevices : []
                        delegate: ConnectivityRow {
                            required property var modelData
                            Layout.fillWidth: true
                            title: root.controller.optionTitle(modelData, "audio")
                            detail: root.controller.optionDetail(modelData, "audio")
                            icon: "󰕾"
                            iconName: "volume-2"
                            selected: root.controller.optionSelected(modelData, "audio", "output")
                            available: root.controller.optionAvailable(modelData, "audio")
                            onActivated: root.controller.activateOption(modelData, "audio", "output")
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.u(0.1)
                        visible: root.section === "audio"
                            && root.controller.audioInputDevices.length > 0
                        text: Config.appearance.ink ? "Input" : "INPUT"
                        color: root.paneCaption
                        font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.monoFontFamily
                        font.pixelSize: Config.appearance.ink ? 12 : Theme.u(0.26)
                        font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
                        font.letterSpacing: Config.appearance.ink ? 0 : Theme.u(0.26) * 0.1
                    }
                    Repeater {
                        model: root.section === "audio" ? root.controller.audioInputDevices : []
                        delegate: ConnectivityRow {
                            required property var modelData
                            Layout.fillWidth: true
                            title: root.controller.optionTitle(modelData, "audio")
                            detail: root.controller.optionDetail(modelData, "audio")
                            icon: "󰍬"
                            iconName: "mic"
                            selected: root.controller.optionSelected(modelData, "audio", "input")
                            available: root.controller.optionAvailable(modelData, "audio")
                            // Sets the default source through
                            // AudioService.setInputDevice() -- do not tap
                            // this live, it changes real system state.
                            onActivated: root.controller.activateOption(modelData, "audio", "input")
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !root.detailSubviewActive && (root.section === "audio"
                    ? (root.controller.audioOutputDevices.length === 0
                        && root.controller.audioInputDevices.length === 0)
                    : root.detailModel.length === 0)
                text: root.section === "bluetooth"
                    ? (BluetoothService.discovering
                        ? "Searching for nearby devices…" : "No devices found")
                    : root.section === "wifi"
                        ? (NetworkService.scanning
                            ? "Searching for networks…" : "No networks found")
                        : "No audio devices found"
                color: root.paneTextDim
                font.family: root.paneFont
                font.pixelSize: Theme.u(0.28)
            }

            Squircle {
                anchors.fill: parent
                visible: root.wifiCredentialsActive
                z: 3
                radius: Theme.u(0.2)
                color: root.paneOverlay

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(470, parent.width - Theme.space5 * 2)
                    spacing: Theme.space2

                    Text {
                        Layout.fillWidth: true
                        text: "Enter the password for this network. It is passed directly to NetworkManager and never stored by the shell."
                        color: root.paneTextDim
                        wrapMode: Text.WordWrap
                        font.family: root.paneFont
                        font.pixelSize: Theme.u(0.26)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        spacing: Theme.space2

                        Squircle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Theme.u(0.34)
                            color: root.paneChip
                            borderWidth: wifiPasswordInput.activeFocus ? 2 : 0
                            borderColor: root.paneAccent

                            TextInput {
                                id: wifiPasswordInput
                                anchors.fill: parent
                                anchors.margins: Theme.space2
                                text: root.controller.wifiPassword
                                onTextChanged: root.controller.wifiPassword = text
                                color: root.paneText
                                selectionColor: root.paneAccent
                                selectedTextColor: root.paneAccentText
                                echoMode: TextInput.Password
                                passwordCharacter: "•"
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: root.paneFont
                                font.pixelSize: Theme.u(0.28)
                                Keys.onReturnPressed: root.controller.submitWifiPassword()
                                Keys.onEnterPressed: root.controller.submitWifiPassword()
                                Keys.onEscapePressed: root.controller.clearWifiCredentials()
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: 88
                            Layout.preferredHeight: Theme.u(0.8)
                            Layout.alignment: Qt.AlignVCenter
                            radius: height / 2
                            opacity: root.controller.wifiPassword.length >= 8 ? 1 : 0.42
                            color: root.paneAccent
                            Text {
                                anchors.centerIn: parent
                                text: "Connect"
                                color: root.paneAccentText
                                font.family: root.paneFont
                                font.pixelSize: Theme.u(0.26)
                                font.weight: Font.DemiBold
                            }
                            TapHandler {
                                enabled: root.controller.wifiPassword.length >= 8
                                onTapped: root.controller.submitWifiPassword()
                            }
                        }
                    }
                }
            }

            Squircle {
                anchors.fill: parent
                visible: root.informationViewActive
                z: 4
                radius: Theme.u(0.2)
                color: root.paneOverlay

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.space2
                    visible: root.section === "wifi"
                    spacing: Theme.space2

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 58
                        spacing: Theme.space2

                        Repeater {
                            model: [
                                { label: "Connection", key: "status", value: root.informationOption?.connected ? "Connected" : "Disconnected", accent: Theme.success, editable: false },
                                { label: "Signal", key: "signal", value: Math.round((root.informationOption?.signalStrength || 0) * 100) + "%", accent: root.paneAccent, editable: false },
                                { label: "IPv4 address", key: "address", value: NetworkService.wifiRuntime.address || "Not assigned", accent: root.paneAccent, editable: true },
                                { label: "Gateway", key: "gateway", value: NetworkService.wifiRuntime.gateway || "Not assigned", accent: Theme.tertiary, editable: true }
                            ]
                            delegate: Rectangle {
                                id: fieldTile
                                required property var modelData
                                readonly property bool editing: !root.controller.wifiAutomatic
                                    && modelData.editable
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                radius: editing ? Theme.u(0.34) : Theme.radiusSmall
                                color: editing ? (Config.appearance.ink ? Theme.inkRaised : Theme.surfaceContainerLow)
                                    : Config.appearance.ink ? Qt.rgba(0, 0, 0, 0)
                                    : Qt.alpha(Theme.surfaceContainerHigh,
                                        Theme.dark ? 0.70 : 0.58)
                                border.width: editing && fieldInput.activeFocus ? 2 : 0
                                border.color: (Config.appearance.ink ? Theme.fillOn : AdaptiveColor.activeFill)

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.space2
                                    spacing: 2

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        color: (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
                                        elide: Text.ElideRight
                                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                        font.pixelSize: Theme.u(0.26)
                                        font.weight: Font.Medium
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: !fieldTile.editing
                                        text: modelData.value
                                        color: modelData.accent
                                        elide: Text.ElideRight
                                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                        font.pixelSize: Theme.u(0.28)
                                        font.weight: Font.DemiBold
                                    }
                                    TextInput {
                                        id: fieldInput
                                        Layout.fillWidth: true
                                        property bool userEdited: false
                                        visible: fieldTile.editing
                                        text: modelData.key === "address"
                                            ? root.controller.manualWifiAddress
                                            : root.controller.manualWifiGateway
                                        color: root.controller.validIpv4(text)
                                            ? modelData.accent : Theme.error
                                        selectionColor: (Config.appearance.ink ? Theme.fillOn : AdaptiveColor.activeFill)
                                        selectedTextColor: (Config.appearance.ink ? Theme.glyphOn : Theme.accentFillText)
                                        selectByMouse: true
                                        font.family: Config.appearance.monoFontFamily
                                        font.pixelSize: Theme.u(0.26)
                                        onTextEdited: {
                                            userEdited = true
                                            if (modelData.key === "address")
                                                root.controller.manualWifiAddress = text
                                            else
                                                root.controller.manualWifiGateway = text
                                            root.controller.wifiModeStaged = true
                                        }
                                        onEditingFinished: {
                                            if (!userEdited)
                                                return
                                            userEdited = false
                                            root.controller.saveManualWifiAddress()
                                        }
                                        Keys.onReturnPressed: {
                                            userEdited = false
                                            root.controller.saveManualWifiAddress()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Squircle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 82
                        radius: Theme.radiusSmall
                        color: Config.appearance.ink ? Qt.rgba(0, 0, 0, 0)
                            : Qt.alpha(Theme.surfaceContainerHigh,
                                Theme.dark ? 0.52 : 0.42)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.space2
                            spacing: Theme.space1

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 25
                                spacing: 0

                                Text {
                                    text: "DNS servers"
                                    color: root.paneText
                                    font.family: root.paneFont
                                    font.pixelSize: Theme.u(0.28)
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: root.controller.wifiAutomatic
                                        ? "Provided by this network"
                                        : "Use a custom IPv4 resolver"
                                    color: root.paneTextDim
                                    font.family: root.paneFont
                                    font.pixelSize: Theme.u(0.26)
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 27
                                visible: root.controller.wifiAutomatic
                                spacing: Theme.space1

                                Repeater {
                                    model: root.controller.automaticWifiDnsServers
                                        .split(",").map(value => value.trim())
                                        .filter(value => value.length > 0)
                                    delegate: Squircle {
                                        required property string modelData
                                        width: Math.min(150,
                                            automaticDnsLabel.implicitWidth
                                                + Theme.space3 * 2)
                                        height: 27
                                        radius: Theme.radiusSmall
                                        color: Config.appearance.ink ? (Config.appearance.ink ? Theme.inkRaised : Theme.surfaceContainerLow) : Qt.alpha(Theme.surfaceContainer, 0.66)

                                        Text {
                                            id: automaticDnsLabel
                                            anchors.centerIn: parent
                                            width: Math.min(126, implicitWidth)
                                            text: modelData
                                            color: (Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim)
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            font.family: Config.appearance.monoFontFamily
                                            font.pixelSize: Theme.u(0.26)
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 27
                                visible: !root.controller.wifiAutomatic
                                clip: true
                                radius: Theme.u(0.34)
                                color: root.paneChip
                                border.width: wifiDnsInput.activeFocus ? 2 : 0
                                border.color: root.paneAccent

                                TextInput {
                                    id: wifiDnsInput
                                    property bool userEdited: false
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space2
                                    anchors.rightMargin: Theme.space2
                                    text: root.controller.manualWifiDnsServers
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: root.paneText
                                    selectionColor: root.paneAccent
                                    selectedTextColor: root.paneAccentText
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: Theme.u(0.26)
                                    onTextEdited: {
                                        userEdited = true
                                        root.controller.manualWifiDnsServers = text
                                    }
                                    onEditingFinished: {
                                        if (!userEdited)
                                            return
                                        userEdited = false
                                        root.controller.saveManualWifiDns()
                                    }
                                    Keys.onReturnPressed: {
                                        userEdited = false
                                        root.controller.saveManualWifiDns()
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: NetworkService.wifiProfileError.length > 0 || NetworkService.wifiProfileStatus.length > 0
                        text: NetworkService.wifiProfileError || NetworkService.wifiProfileStatus
                        color: NetworkService.wifiProfileError.length > 0 ? Theme.error : Theme.success
                        font.family: root.paneFont
                        font.pixelSize: Theme.u(0.26)
                        wrapMode: Text.WordWrap
                    }
                }

                GridLayout {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: Theme.space3
                    width: Math.min(520, parent.width - Theme.space5 * 2)
                    columns: 2
                    rowSpacing: Theme.space3
                    columnSpacing: Theme.space5
                    visible: root.section !== "wifi"

                    Repeater {
                        model: root.controller.informationRows(root.section)
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40

                            Column {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    // Ink captions are sentence case; glass keeps uppercase via capitalization.
                                    text: modelData.label
                                    color: (Config.appearance.ink ? Theme.t3 : Theme.outline)
                                    font.capitalization: Config.appearance.ink ? Font.MixedCase : Font.AllUppercase
                                    font.family: Config.appearance.ink ? Theme.fontUi : Config.appearance.monoFontFamily
                                    font.pixelSize: Config.appearance.ink ? 12 : Theme.u(0.26)
                                    font.weight: Config.appearance.ink ? Font.Medium : Font.Normal
                                    font.letterSpacing: Config.appearance.ink ? 0 : Theme.u(0.26) * 0.1
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.value
                                    color: (Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText)
                                    elide: Text.ElideRight
                                    font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                    font.pixelSize: Theme.u(0.28)
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }

                // Primary/secondary actions: Forget (Wi-Fi) or
                // Disconnect/Forget (Bluetooth), restoring the capability
                // the Microphone-tile-era Odyssey UI never exposed here.
                // network.forget()/.disconnect() and device.disconnect()/
                // .forget() are native Quickshell calls -- see
                // services/NetworkService.qml and services/BluetoothService.qml.
                // These are wired and correct but were never clicked while
                // building this: doing so would change real network/
                // Bluetooth state on the machine running this shell.
                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Theme.space2
                    spacing: Theme.space3
                    visible: root.controller.primaryDetailActionLabel(root.section).length > 0

                    Rectangle {
                        Layout.preferredWidth: primaryActionLabel.implicitWidth + Theme.u(0.6)
                        Layout.preferredHeight: Theme.u(0.8)
                        radius: height / 2
                        color: root.paneAccent

                        Text {
                            id: primaryActionLabel
                            anchors.centerIn: parent
                            text: root.controller.primaryDetailActionLabel(root.section)
                            color: root.paneAccentText
                            font.family: root.paneFont
                            font.pixelSize: Theme.u(0.26)
                            font.weight: Font.DemiBold
                        }
                        TapHandler {
                            onTapped: root.controller.invokePrimaryDetailAction(root.section)
                        }
                    }

                    Text {
                        visible: root.controller.secondaryDetailActionLabel(root.section).length > 0
                        text: root.controller.secondaryDetailActionLabel(root.section)
                        color: secondaryActionHover.hovered ? root.paneText : root.paneAccent
                        font.family: root.paneFont
                        font.pixelSize: Theme.u(0.26)
                        font.weight: Font.Medium

                        HoverHandler { id: secondaryActionHover }
                        TapHandler {
                            onTapped: root.controller.invokeSecondaryDetailAction(root.section)
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
