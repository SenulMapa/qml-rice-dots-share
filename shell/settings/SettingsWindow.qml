import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Io
import "../components"
import "../core"
import "../services"

FloatingWindow {
    id: root

    width: 900
    height: 620
    title: "qml-rice settings"
    visible: false

    // Ink (settings.html): #000 window with a 1px inkRim ring. With the gate
    // off nothing is painted and the user's chosen font is used.
    Squircle {
        anchors.fill: parent
        visible: Config.appearance.ink
        color: Theme.ink
        radius: Theme.rCtl
        borderWidth: 1
        borderColor: Theme.inkRim
    }

    component SettingsCard: Squircle {
        id: card
        property string title: ""
        property string detail: ""
        property real contentHeight: 40
        property bool inlineLayout: false
        property bool headerToggleVisible: false
        property bool headerChecked: false
        property bool headerToggleAvailable: true
        signal headerToggled(bool enabled)
        default property alias content: contentHost.data

        implicitHeight: inlineLayout
            ? Math.max(cardHeader.implicitHeight, contentHeight) + Theme.space2 * 2
            : cardHeader.implicitHeight + contentHeight + Theme.space2 * 3
        radius: Config.appearance.ink ? Theme.rCtl : Theme.radiusMedium
        // Ink rows sit on the black window with whitespace, no card fill.
        color: Config.appearance.ink ? "transparent" : Qt.alpha(Theme.surfaceContainerHigh,
            Theme.dark ? 0.58 : 0.48)
        borderWidth: Config.appearance.ink ? 0 : 1
        borderColor: Qt.alpha(Theme.outlineVariant, 0.28)

        GridLayout {
            anchors.fill: parent
            anchors.margins: Theme.space3
            anchors.topMargin: Theme.space2
            anchors.bottomMargin: Theme.space2
            columns: card.inlineLayout ? 2 : 1
            columnSpacing: Theme.space3
            rowSpacing: Theme.space2

            RowLayout {
                id: cardHeader
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Theme.space2

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: card.title
                        color: Config.appearance.ink ? Theme.t1 : Theme.surfaceText
                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                        font.pixelSize: Theme.textSmall
                        font.weight: Font.DemiBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: card.detail
                        color: Config.appearance.ink ? Theme.t2 : Theme.surfaceVariantText
                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                SettingsToggle {
                    visible: card.headerToggleVisible
                    checked: card.headerChecked
                    available: card.headerToggleAvailable
                    onToggled: enabled => card.headerToggled(enabled)
                }
            }

            Item {
                id: contentHost
                Layout.fillWidth: !card.inlineLayout
                Layout.preferredWidth: card.inlineLayout
                    ? Math.min(250, card.width * 0.52) : -1
                Layout.preferredHeight: card.contentHeight
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    component TextButton: Squircle {
        id: btn
        property string text: ""
        signal clicked()
        property bool enabled: true
        property bool compact: false

        implicitWidth: btnText.implicitWidth + Theme.space2 * 2
        implicitHeight: compact ? 28 : 36
        radius: Theme.radiusSmall
        color: btnMouse.pressed ? Qt.alpha(Theme.primary, 0.2)
            : btnMouse.hovered ? Qt.alpha(Theme.primary, 0.12)
            : Qt.alpha(Theme.primaryContainer, 0.3)
        opacity: enabled ? 1.0 : 0.5

        Text {
            id: btnText
            anchors.centerIn: parent
            text: btn.text
            color: Theme.primary
            font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
            font.pixelSize: compact ? 9 : 10
            font.weight: Font.DemiBold
        }

        HoverHandler { id: btnMouse }
        TapHandler {
            enabled: btn.enabled
            onTapped: btn.clicked()
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.space2
        spacing: Theme.space2

        // Left sidebar with section buttons
        Squircle {
            Layout.preferredWidth: 160
            Layout.fillHeight: true
            radius: Config.appearance.ink ? Theme.rCtl : Theme.radiusSmall
            color: Config.appearance.ink ? "transparent" : Qt.alpha(Theme.surfaceContainerLow, 0.5)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.space2
                spacing: Theme.space1

                Text {
                    Layout.leftMargin: Theme.space1
                    text: "SETTINGS"
                    color: Theme.surfaceVariantText
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                }

                Repeater {
                    model: [
                        { id: "appearance", icon: "󰏘", label: "Appearance" },
                        { id: "pill", icon: "󰇄", label: "Pill" },
                        { id: "motion", icon: "󰑐", label: "Motion" },
                        { id: "desktop", icon: "󰊗", label: "Desktop widgets" },
                        { id: "audio", icon: "󰕿", label: "Audio" },
                        { id: "network", icon: "󰤨", label: "Network" },
                        { id: "about", icon: "ℹ", label: "About" }
                    ]
                    delegate: Squircle {
                        id: navRow
                        required property var modelData
                        readonly property bool selected: root.currentSection === modelData.id
                        Layout.fillWidth: true
                        Layout.preferredHeight: Config.appearance.ink ? 40 : 36
                        radius: Config.appearance.ink ? 14 : Theme.radiusSmall
                        color: Config.appearance.ink
                            ? (navRow.selected ? Theme.inkRaised
                                : btnHover.hovered ? Theme.inkRaised2 : "transparent")
                            : navRow.selected
                            ? Qt.alpha(Theme.primaryContainer, 0.8)
                            : btnHover.hovered
                                ? Qt.alpha(Theme.surfaceContainerHigh, 0.6)
                                : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space2
                            anchors.rightMargin: Theme.space2
                            spacing: Theme.space1

                            Text {
                                text: modelData.icon
                                color: Config.appearance.ink
                                    ? (navRow.selected ? Theme.t1 : Theme.t2)
                                    : navRow.selected
                                    ? Theme.primary : Theme.surfaceVariantText
                                font.family: Config.appearance.monoFontFamily
                                font.pixelSize: Theme.iconSmall
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: Config.appearance.ink
                                    ? (navRow.selected ? Theme.t1 : Theme.t2)
                                    : navRow.selected
                                    ? Theme.primary : Theme.surfaceVariantText
                                font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                font.pixelSize: Config.appearance.ink ? 14 : 10
                                font.weight: Config.appearance.ink ? Font.Medium : Font.DemiBold
                            }
                        }

                        HoverHandler { id: btnHover }
                        TapHandler {
                            onTapped: root.currentSection = modelData.id
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // Main content area
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.space2

            // Header
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.appearance.ink ? 52 : 40
                spacing: Theme.space2

                Squircle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: Theme.radiusSmall
                    color: Config.appearance.ink ? Theme.inkRaised : Qt.alpha(Theme.primaryContainer, 0.8)

                    Text {
                        anchors.centerIn: parent
                        text: root.currentSectionData.icon
                        color: Config.appearance.ink ? Theme.t1 : Theme.primary
                        font.family: Config.appearance.monoFontFamily
                        font.pixelSize: Theme.iconSmall
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: root.currentSectionData.label
                        color: Config.appearance.ink ? Theme.t1 : Theme.surfaceText
                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: root.currentSectionData.description
                        color: Theme.surfaceVariantText
                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                        font.pixelSize: 10
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Content area
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: contentCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: contentCol
                    width: parent.width
                    spacing: Theme.space2

                    // Appearance section
                    ColumnLayout {
                        visible: root.currentSection === "appearance"
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        spacing: Theme.space2

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Theme mode"
                            inlineLayout: true
                            contentHeight: 36

                            RowLayout {
                                anchors.fill: parent
                                spacing: Theme.space1
                                Item { Layout.fillWidth: true }
                                Repeater {
                                    model: [
                                        { id: "auto", label: "Auto" },
                                        { id: "dark", label: "Dark" },
                                        { id: "light", label: "Light" }
                                    ]
                                    delegate: SettingsChoice {
                                        required property var modelData
                                        compact: true
                                        label: modelData.label
                                        selected: Config.appearance.mode === modelData.id
                                        onActivated: AppearanceService.setMode(modelData.id)
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Ink interface"
                            detail: "Black island and pages, Geist with Instrument Serif numerals"
                            inlineLayout: true
                            contentHeight: 36
                            headerToggleVisible: true
                            headerChecked: Config.appearance.ink
                            onHeaderToggled: enabled => SettingsStore.setInk(enabled)
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Wallpaper"
                            detail: "Select and configure"
                            inlineLayout: true
                            contentHeight: 36

                            RowLayout {
                                anchors.fill: parent
                                Item { Layout.fillWidth: true }
                                TextButton {
                                    text: "Open wallpaper picker"
                                    onClicked: {
                                        // The picker is the island's "wallpaper" page, not
                                        // part of this window -- open it, then get out of
                                        // its way.
                                        ShellActions.insightOpenRequested("wallpaper")
                                        root.close()
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Dither wallpaper"
                            detail: "Bayer dither effect with cursor reveal"
                            inlineLayout: true
                            contentHeight: 36

                            RowLayout {
                                anchors.fill: parent
                                Text {
                                    Layout.fillWidth: true
                                    text: "Enable dither"
                                    color: Theme.surfaceText
                                    font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                    font.pixelSize: Theme.textSmall
                                }
                                SettingsToggle {
                                    checked: Config.wallpaper.dither
                                    onToggled: enabled => SettingsStore.setWallpaperDither(enabled)
                                }
                            }
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Dither dot size"
                            detail: "Bayer dot pitch, in pixels"
                            inlineLayout: true
                            contentHeight: 36
                            visible: Config.wallpaper.dither

                            RowLayout {
                                anchors.fill: parent
                                spacing: Theme.space2
                                SettingsSlider {
                                    Layout.preferredWidth: 140
                                    from: 2.0
                                    to: 8.0
                                    stepSize: 0.5
                                    value: Config.wallpaper.ditherDotSize
                                    onAdjusted: value => SettingsStore.setWallpaperDitherDotSize(value)
                                }
                                Text {
                                    Layout.preferredWidth: 30
                                    text: Config.wallpaper.ditherDotSize.toFixed(1)
                                    color: Config.appearance.ink ? Theme.t1 : Theme.primary
                                    font.family: Config.appearance.ink ? Theme.fontSerif : Config.appearance.monoFontFamily
                                    font.pixelSize: 9
                                }
                            }
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Dither black point"
                            detail: "Suppresses dot grain in dark areas"
                            inlineLayout: true
                            contentHeight: 36
                            visible: Config.wallpaper.dither

                            RowLayout {
                                anchors.fill: parent
                                spacing: Theme.space2
                                SettingsSlider {
                                    Layout.preferredWidth: 140
                                    from: 0.0
                                    to: 0.5
                                    stepSize: 0.01
                                    value: Config.wallpaper.ditherBlackPoint
                                    onAdjusted: value => SettingsStore.setWallpaperDitherBlackPoint(value)
                                }
                                Text {
                                    Layout.preferredWidth: 30
                                    text: Config.wallpaper.ditherBlackPoint.toFixed(2)
                                    color: Config.appearance.ink ? Theme.t1 : Theme.primary
                                    font.family: Config.appearance.ink ? Theme.fontSerif : Config.appearance.monoFontFamily
                                    font.pixelSize: 9
                                }
                            }
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Dither idle wave"
                            detail: "Slow ripple in the dot grid"
                            inlineLayout: true
                            contentHeight: 36
                            visible: Config.wallpaper.dither

                            RowLayout {
                                anchors.fill: parent
                                Text {
                                    Layout.fillWidth: true
                                    text: "Enable wave"
                                    color: Theme.surfaceText
                                    font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                    font.pixelSize: Theme.textSmall
                                }
                                SettingsToggle {
                                    checked: Config.wallpaper.ditherWave
                                    onToggled: enabled => SettingsStore.setWallpaperDitherWave(enabled)
                                }
                            }
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Dither image"
                            detail: Config.wallpaper.ditherImage || "Follows current wallpaper"
                            inlineLayout: true
                            contentHeight: 36
                            visible: Config.wallpaper.dither

                            RowLayout {
                                anchors.fill: parent
                                Item { Layout.fillWidth: true }
                                TextButton {
                                    text: "Clear override"
                                    onClicked: SettingsStore.setWallpaperDitherImage("")
                                }
                            }
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "UI font"
                            detail: Config.appearance.fontFamily
                            contentHeight: 36

                            RowLayout {
                                anchors.fill: parent
                                Item { Layout.fillWidth: true }
                                TextButton {
                                    text: "Change font"
                                    onClicked: {} // Placeholder
                                }
                            }
                        }
                    }

                    // Pill section
                    ColumnLayout {
                        visible: root.currentSection === "pill"
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        spacing: Theme.space2

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Satellite join"
                            detail: "Controls the neck between satellites and pill body"
                            inlineLayout: true
                            contentHeight: 36

                            RowLayout {
                                anchors.fill: parent
                                spacing: Theme.space1
                                Item { Layout.fillWidth: true }
                                Repeater {
                                    model: [
                                        { id: "joined", label: "Joined" },
                                        { id: "separate", label: "Separate" }
                                    ]
                                    delegate: SettingsChoice {
                                        required property var modelData
                                        compact: true
                                        label: modelData.label
                                        selected: Config.island.satelliteJoin === modelData.id
                                        onActivated: SettingsStore.setIslandSatelliteJoin(modelData.id)
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Auto-hide"
                            detail: Config.island.autoHide ? "Enabled" : "Disabled"
                            headerToggleVisible: true
                            headerChecked: Config.island.autoHide
                            onHeaderToggled: enabled => SettingsStore.setIslandAutoHide(enabled)
                            contentHeight: 60

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: Theme.space2

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Show reveal lip"
                                        color: Theme.surfaceText
                                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                        font.pixelSize: Theme.textSmall
                                        enabled: Config.island.autoHide
                                    }
                                    SettingsToggle {
                                        checked: Config.island.showRevealLip
                                        enabled: Config.island.autoHide
                                        onToggled: enabled => SettingsStore.setIslandRevealLip(enabled)
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Hide after"
                                        color: Theme.surfaceText
                                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                        font.pixelSize: Theme.textSmall
                                        enabled: Config.island.autoHide
                                    }
                                    SettingsSlider {
                                        Layout.preferredWidth: 120
                                        from: 0.5
                                        to: 10
                                        stepSize: 0.5
                                        value: Config.island.autoHideDelay / 1000
                                        enabled: Config.island.autoHide
                                        onAdjusted: value => SettingsStore.setIslandMetric("autoHideDelay", value * 1000)
                                    }
                                    Text {
                                        Layout.preferredWidth: 30
                                        text: (Config.island.autoHideDelay / 1000).toFixed(1) + "s"
                                        color: Config.appearance.ink ? Theme.t1 : Theme.primary
                                        font.family: Config.appearance.ink ? Theme.fontSerif : Config.appearance.monoFontFamily
                                        font.pixelSize: 9
                                        enabled: Config.island.autoHide
                                    }
                                }
                            }
                        }
                    }

                    // Motion section
                    ColumnLayout {
                        visible: root.currentSection === "motion"
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        spacing: Theme.space2

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Reduce motion"
                            detail: "Minimizes animations and transitions"
                            inlineLayout: true
                            contentHeight: 36

                            RowLayout {
                                anchors.fill: parent
                                Text {
                                    Layout.fillWidth: true
                                    text: "Enable"
                                    color: Theme.surfaceText
                                    font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                    font.pixelSize: Theme.textSmall
                                }
                                SettingsToggle {
                                    checked: Config.appearance.reducedMotion
                                    onToggled: enabled => AppearanceService.setReducedMotion(enabled)
                                }
                            }
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Motion speed scale"
                            detail: "Adjust all animation durations"
                            inlineLayout: true
                            contentHeight: 36
                            visible: !Config.appearance.reducedMotion

                            RowLayout {
                                anchors.fill: parent
                                spacing: Theme.space2
                                Text {
                                    Layout.fillWidth: true
                                    text: "0.8x"
                                    color: Theme.surfaceVariantText
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: 9
                                }
                                SettingsSlider {
                                    Layout.preferredWidth: 160
                                    from: 0.8
                                    to: 1.2
                                    stepSize: 0.05
                                    value: Config.appearance.motionSpeedMultiplier
                                    onAdjusted: value => SettingsStore.setMotionScale(value)
                                }
                                Text {
                                    Layout.preferredWidth: 50
                                    text: (Config.appearance.motionSpeedMultiplier).toFixed(2) + "x"
                                    color: Config.appearance.ink ? Theme.t1 : Theme.primary
                                    font.family: Config.appearance.ink ? Theme.fontSerif : Config.appearance.monoFontFamily
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: "1.2x"
                                    horizontalAlignment: Text.AlignRight
                                    color: Theme.surfaceVariantText
                                    font.family: Config.appearance.monoFontFamily
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }

                    // Desktop widgets section
                    ColumnLayout {
                        visible: root.currentSection === "desktop"
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        spacing: Theme.space2

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Desktop widgets"
                            detail: WidgetStore.editMode ? "Edit mode enabled" : "Edit widgets"
                            inlineLayout: true
                            contentHeight: 36

                            RowLayout {
                                anchors.fill: parent
                                Text {
                                    Layout.fillWidth: true
                                    text: "Edit mode"
                                    color: Theme.surfaceText
                                    font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                    font.pixelSize: Theme.textSmall
                                }
                                SettingsToggle {
                                    checked: WidgetStore.editMode
                                    onToggled: enabled => {
                                        if (enabled !== WidgetStore.editMode)
                                            WidgetStore.toggleEditMode()
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Widgets live on the desktop. Toggle edit mode to move, resize, add, or remove them."
                            color: Theme.surfaceVariantText
                            wrapMode: Text.WordWrap
                            font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                            font.pixelSize: 9
                        }
                    }

                    // Audio section
                    ColumnLayout {
                        visible: root.currentSection === "audio"
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        spacing: Theme.space2

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Output device"
                            detail: Pipewire.preferredDefaultAudioSink
                            contentHeight: 200

                            ListView {
                                anchors.fill: parent
                                model: Pipewire.nodes
                                clip: true
                                spacing: Theme.space1

                                delegate: Squircle {
                                    required property var modelData
                                    required property int index
                                    visible: modelData.isSink && !modelData.isStream
                                    width: ListView.view.width
                                    height: visible ? 36 : 0
                                    radius: Theme.radiusSmall
                                    color: Pipewire.preferredDefaultAudioSink === modelData.name
                                        ? Qt.alpha(Theme.primaryContainer, 0.6)
                                        : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.space1
                                        anchors.rightMargin: Theme.space1

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            color: Pipewire.preferredDefaultAudioSink === modelData.name
                                                ? Theme.primary : Theme.surfaceText
                                            font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                            font.pixelSize: 10
                                        }

                                        TapHandler {
                                            onTapped: Pipewire.preferredDefaultAudioSink = modelData.name
                                        }
                                    }
                                }
                            }
                        }

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Input device"
                            detail: Pipewire.preferredDefaultAudioSource
                            contentHeight: 200

                            ListView {
                                anchors.fill: parent
                                model: Pipewire.nodes
                                clip: true
                                spacing: Theme.space1

                                delegate: Squircle {
                                    required property var modelData
                                    required property int index
                                    visible: modelData.isSource && !modelData.isStream
                                    width: ListView.view.width
                                    height: visible ? 36 : 0
                                    radius: Theme.radiusSmall
                                    color: Pipewire.preferredDefaultAudioSource === modelData.name
                                        ? Qt.alpha(Theme.primaryContainer, 0.6)
                                        : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.space1
                                        anchors.rightMargin: Theme.space1

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            color: Pipewire.preferredDefaultAudioSource === modelData.name
                                                ? Theme.primary : Theme.surfaceText
                                            font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                            font.pixelSize: 10
                                        }

                                        TapHandler {
                                            onTapped: Pipewire.preferredDefaultAudioSource = modelData.name
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Network section
                    ColumnLayout {
                        visible: root.currentSection === "network"
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        spacing: Theme.space2

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "Wi-Fi"
                            detail: "Network connectivity"
                            inlineLayout: true
                            contentHeight: 36

                            RowLayout {
                                anchors.fill: parent
                                Item { Layout.fillWidth: true }
                                TextButton {
                                    text: "Open Wi-Fi panel"
                                    onClicked: {
                                        // Call IPC to open Wi-Fi satellite
                                        ShellApi.ipc("island satellite wifi")
                                    }
                                }
                            }
                        }
                    }

                    // About section
                    ColumnLayout {
                        visible: root.currentSection === "about"
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        spacing: Theme.space2

                        SettingsCard {
                            Layout.fillWidth: true
                            title: "qml-rice"
                            detail: "Settings UI"
                            contentHeight: 72

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: Theme.space1

                                RowLayout {
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Version"
                                        color: Theme.surfaceVariantText
                                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                        font.pixelSize: 9
                                    }
                                    Text {
                                        text: "0.2.1"
                                        color: Theme.surfaceText
                                        font.family: Config.appearance.monoFontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }

                                RowLayout {
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Git hash"
                                        color: Theme.surfaceVariantText
                                        font.family: (Config.appearance.ink ? Theme.fontUi : Config.appearance.fontFamily)
                                        font.pixelSize: 9
                                    }
                                    Text {
                                        text: "blob-rebuild"
                                        color: Theme.surfaceText
                                        font.family: Config.appearance.monoFontFamily
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    property string currentSection: "appearance"
    readonly property var sectionData: [
        { id: "appearance", icon: "󰏘", label: "Appearance", description: "Theme and fonts" },
        { id: "pill", icon: "󰇄", label: "Pill", description: "Island and satellites" },
        { id: "motion", icon: "󰑐", label: "Motion", description: "Animation settings" },
        { id: "desktop", icon: "󰊗", label: "Desktop widgets", description: "Widget management" },
        { id: "audio", icon: "󰕿", label: "Audio", description: "Sound devices" },
        { id: "network", icon: "󰤨", label: "Network", description: "Connectivity" },
        { id: "about", icon: "ℹ", label: "About", description: "Version and info" }
    ]
    readonly property var currentSectionData: sectionData.find(s => s.id === currentSection) || sectionData[0]
}
