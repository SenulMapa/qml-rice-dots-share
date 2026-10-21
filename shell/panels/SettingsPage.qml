import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../components"
import "../core"
import "../services"

Item {
    id: root

    property var monitor
    property string section: "appearance"
    property string pillPreviewMode: "rest"
    property string islandEditor: "overview"
    property bool accentPaletteOpen: false
    property string stagedAccent: Config.appearance.accentOverride
    property string pickedAccent: ""
    // Font pickers (Appearance section): at most one open at a time, each
    // with its own search filter -- "" means none open. See FontRoleCard
    // below and SettingsStore.setFontFamily/fontFamilyValue.
    property string fontPickerOpen: ""
    property string weatherNameDraft: Config.weather.locationName
    property string weatherLatitudeDraft: Number.isFinite(Config.weather.latitude)
        ? Config.weather.latitude.toString() : ""
    property string weatherLongitudeDraft: Number.isFinite(Config.weather.longitude)
        ? Config.weather.longitude.toString() : ""
    readonly property bool weatherDraftValid: weatherNameDraft.trim().length > 0
        && weatherNameDraft.trim().length <= 100
        && weatherLatitudeDraft.trim().length > 0
        && weatherLongitudeDraft.trim().length > 0
        && Number.isFinite(Number(weatherLatitudeDraft))
        && Number(weatherLatitudeDraft) >= -90
        && Number(weatherLatitudeDraft) <= 90
        && Number.isFinite(Number(weatherLongitudeDraft))
        && Number(weatherLongitudeDraft) >= -180
        && Number(weatherLongitudeDraft) <= 180
    readonly property bool livePreviewActive: section === "island"
        && islandEditor !== "overview"
    function setIslandItem(context: string, item: string,
            enabled: bool): void {
        pillPreviewMode = context
        SettingsStore.setIslandItemVisible(context, item, enabled)
    }
    function setIslandSpacing(context: string, value: real): void {
        pillPreviewMode = context
        SettingsStore.setIslandMetric(context + "ItemSpacing", value)
    }
    function pickAccentFromScreen(): void {
        if (!accentPicker.running) {
            pickedAccent = ""
            accentPicker.command = ["hyprpicker", "--format", "hex", "--no-fancy",
                "--lowercase-hex"]
            accentPicker.running = true
        }
    }
    property Process accentPicker: Process {
        stdout: StdioCollector { onStreamFinished: root.pickedAccent = text.trim() }
        onExited: code => {
            if (code === 0 && /^#[0-9a-fA-F]{6}$/.test(root.pickedAccent))
                AppearanceService.setAccentOverride(root.pickedAccent.toLowerCase())
        }
    }
    onSectionChanged: {
        if (section !== "island")
            islandEditor = "overview"
        Qt.callLater(() => settingsScroll.contentY = 0)
    }
    onIslandEditorChanged: Qt.callLater(() => settingsScroll.contentY = 0)
    readonly property var sections: [
        { id: "appearance", icon: "󰏘", label: "Appearance" },
        { id: "island", icon: "󰇄", label: "Island & Motion" },
        { id: "idle", icon: "󰅶", label: "Power & Idle" },
        { id: "displays", icon: "󰍹", label: "Displays" },
        { id: "notifications", icon: "󰂚", label: "Notifications" },
        { id: "media", icon: "󰝚", label: "Media" },
        { id: "wallpaper", icon: "󰸉", label: "Wallpaper" },
        { id: "widgets", icon: "󰊗", label: "Desktop widgets" },
        { id: "dashboard", icon: "󰕮", label: "Dashboard" },
        { id: "command-launcher", icon: "", label: "Command Launcher" },
        { id: "integrations", icon: "󰕮", label: "System Integrations" }
    ]
    readonly property var currentSection: sections.find(
        option => option.id === section) || sections[0]

    RowLayout {
        anchors.fill: parent
        spacing: Theme.space2

        Squircle {
            Layout.preferredWidth: 154
            Layout.fillHeight: true
            radius: Theme.radiusLarge
            color: Qt.alpha(Theme.surfaceContainerLow, 0.44)
            borderWidth: 1
            borderColor: Qt.alpha(Theme.outlineVariant, 0.28)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.space2
                spacing: Theme.space1

                Text {
                    Layout.leftMargin: Theme.space1
                    Layout.bottomMargin: Theme.space1
                    text: "ODYSSEY  /  SETTINGS"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                }

                Repeater {
                    model: root.sections
                    delegate: Squircle {
                        id: sectionButton
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 31
                        activeFocusOnTab: true
                        radius: Theme.radiusSmall
                        color: root.section === modelData.id
                            ? Qt.alpha(Theme.primaryContainer, 0.82)
                            : sectionHover.hovered
                                ? Qt.alpha(Theme.surfaceContainerHigh, 0.72)
                                : "transparent"
                        borderWidth: activeFocus ? 1 : 0
                        borderColor: Qt.alpha(AdaptiveColor.activeFill, 0.78)

                        Keys.onReturnPressed: root.section = modelData.id
                        Keys.onEnterPressed: root.section = modelData.id
                        Keys.onSpacePressed: root.section = modelData.id

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space2
                            anchors.rightMargin: Theme.space2
                            spacing: Theme.space1
                            Rectangle {
                                Layout.preferredWidth: 3
                                Layout.preferredHeight: 15
                                radius: 2
                                visible: root.section === modelData.id
                                color: AdaptiveColor.activeFill
                            }
                            Text {
                                text: modelData.icon
                                color: root.section === modelData.id
                                    ? AdaptiveColor.activeFill
                                    : AdaptiveColor.glassTextDim
                                font.family: Config.appearance.monoFontFamily
                                font.pixelSize: Theme.iconSmall
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: root.section === modelData.id
                                    ? AdaptiveColor.glassText : AdaptiveColor.glassTextDim
                                font.family: Config.appearance.fontFamily
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                        HoverHandler { id: sectionHover }
                        TapHandler {
                            onTapped: {
                                sectionButton.forceActiveFocus()
                                root.section = modelData.id
                            }
                        }
                        Behavior on color {
                            ColorAnimation { duration: Animations.fast }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                Text {
                    visible: SettingsStore.errorMessage.length > 0
                    Layout.fillWidth: true
                    text: SettingsStore.errorMessage
                    color: Theme.error
                    wrapMode: Text.WordWrap
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 9
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.space2

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    spacing: Theme.space2
                    Squircle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: Theme.radiusSmall
                        color: Qt.alpha(Theme.primaryContainer, 0.78)
                        Text {
                            anchors.centerIn: parent
                            text: root.currentSection.icon
                            color: AdaptiveColor.activeFill
                            font.family: Config.appearance.monoFontFamily
                            font.pixelSize: Theme.iconSmall
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: root.section === "island"
                                    && root.islandEditor === "geometry"
                                ? "Live Edit"
                                : root.section === "island"
                                    && root.islandEditor === "content"
                                    ? "Resting & Hover Island"
                                    : root.currentSection.label
                            color: AdaptiveColor.glassText
                            font.family: Config.appearance.fontFamily
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: root.section === "appearance"
                                ? "Color, surfaces, and motion"
                                : root.section === "island"
                                    ? "Footprint, rhythm, and resting content"
                                : root.section === "idle"
                                    ? "Screen rest and system sleep"
                                : root.section === "displays"
                                    ? "Placement and display policy"
                                : root.section === "notifications"
                                    ? "Interruption and local history"
                                : root.section === "media"
                                    ? "Playback presence in the Island"
                                : root.section === "wallpaper"
                                    ? "Library, color, and transitions"
                                : root.section === "dashboard"
                                    ? "Overview appearance"
                                : root.section === "widgets"
                                    ? "Desktop screen widgets"
                                : root.section === "command-launcher"
                                    ? "Local history and terminal preferences"
                                    : "Explicit external theme ownership"
                            color: AdaptiveColor.glassTextDim
                            font.family: Config.appearance.fontFamily
                            font.pixelSize: 10
                        }
                    }
                }

                Flickable {
                    id: settingsScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: pageContent.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: pageContent
                        width: parent.width
                        spacing: Theme.space2

                        ColumnLayout {
                            visible: root.section === "appearance"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Theme mode"
                                detail: "Auto follows the generated wallpaper palette"
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
                                title: "Surface opacity"
                                detail: Math.round(Config.appearance.surfaceOpacity * 100)
                                    + "% · Applies live to expanded shell surfaces"
                                inlineLayout: true
                                contentHeight: 36
                                SettingsSlider {
                                    width: 190
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    from: 0.72
                                    to: 1
                                    stepSize: 0.01
                                    value: Config.appearance.surfaceOpacity
                                    onAdjusted: value => AppearanceService
                                        .setSurfaceOpacity(value)
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Color style"
                                detail: AppearanceService.changingScheme
                                    ? "Generating a new palette…"
                                    : "Choose how Matugen interprets the current wallpaper"
                                contentHeight: 100
                                GridLayout {
                                    anchors.fill: parent
                                    columns: 3
                                    columnSpacing: Theme.space2
                                    rowSpacing: Theme.space2
                                    Repeater {
                                        model: [
                                            { id: "scheme-content", label: "Content" },
                                            { id: "scheme-tonal-spot", label: "Tonal" },
                                            { id: "scheme-vibrant", label: "Vibrant" },
                                            { id: "scheme-monochrome", label: "Monochrome" },
                                            { id: "scheme-expressive", label: "Expressive" },
                                            { id: "scheme-fidelity", label: "Fidelity" },
                                            { id: "scheme-fruit-salad", label: "Fruit salad" },
                                            { id: "scheme-neutral", label: "Neutral" },
                                            { id: "scheme-rainbow", label: "Rainbow" }
                                        ]
                                        delegate: SettingsChoice {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            compact: true
                                            label: modelData.label
                                            selected: Config.wallpaper.scheme === modelData.id
                                            available: !AppearanceService.changingScheme
                                            onActivated: AppearanceService.setScheme(modelData.id)
                                        }
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Accent color override"
                                detail: accentPaletteOpen ? "Pick a color, then Use color to commit it" : "Optional primary-accent override"
                                contentHeight: accentPaletteOpen ? 222 : 34
                                ColumnLayout { anchors.fill: parent; spacing: Theme.space2
                                    RowLayout { Layout.fillWidth: true; spacing: Theme.space2
                                        AccentSwatch { swatchColor: AdaptiveColor.activeFill; glyph: "󰏘"; selected: !Theme.accentOverridden; onActivated: AppearanceService.clearAccentOverride() }
                                        Repeater { model: ["#7c3aed", "#0284c7", "#059669", "#d97706", "#e11d48"]; delegate: AccentSwatch { required property string modelData; swatchColor: modelData; selected: Config.appearance.accentOverride === modelData; onActivated: AppearanceService.setAccentOverride(modelData) } }
                                        AccentSwatch { swatchColor: AdaptiveColor.activeFill; glyph: "󰐕"; selected: accentPaletteOpen; onActivated: { root.stagedAccent = Config.appearance.accentOverride; root.accentPaletteOpen = !root.accentPaletteOpen } }
                                        Item { Layout.fillWidth: true }
                                    }
                                    GridLayout { visible: root.accentPaletteOpen; Layout.alignment: Qt.AlignHCenter; columns: 9; columnSpacing: 4; rowSpacing: 4
                                        Repeater { model: ["#1d4ed8","#2563eb","#3b82f6","#60a5fa","#93c5fd", "#047857","#059669","#10b981","#34d399","#6ee7b7", "#ca8a04","#eab308","#facc15","#fde047","#fef08a", "#c2410c","#ea580c","#f97316","#fb923c","#fdba74", "#be123c","#e11d48","#f43f5e","#fb7185","#fda4af", "#6d28d9","#7c3aed","#8b5cf6","#a78bfa","#c4b5fd", "#713f12","#854d0e","#a16207","#b45309","#d6a96c", "#111827","#374151","#6b7280","#9ca3af","#d1d5db", "#f9fafb","#e5e7eb","#cbd5e1","#94a3b8","#475569"]
                                            delegate: AccentPaletteSwatch { required property string modelData; swatchColor: modelData; selected: Config.appearance.accentOverride === modelData; onActivated: AppearanceService.setAccentOverride(modelData) }
                                        }
                                    }
                                    RowLayout { visible: root.accentPaletteOpen; Layout.fillWidth: true
                                        Squircle { Layout.preferredWidth: 36; Layout.preferredHeight: 28; radius: Theme.radiusSmall; color: /^#[0-9a-fA-F]{6}$/.test(accentHex.text) ? accentHex.text : AdaptiveColor.activeFill; borderWidth: 1; borderColor: Qt.alpha(Theme.outlineVariant, 0.72) }
                                        TextInput {
                                            id: accentHex
                                            Layout.fillWidth: true
                                            text: ""
                                            selectByMouse: true
                                            color: AdaptiveColor.glassText
                                            font.family: Config.appearance.monoFontFamily
                                            font.pixelSize: 10
                                            validator: RegularExpressionValidator {
                                                regularExpression: /#[0-9a-fA-F]{6}/
                                            }
                                            Text { anchors.verticalCenter: parent.verticalCenter; visible: !accentHex.text && !accentHex.activeFocus; text: "Enter hex value"; color: AdaptiveColor.glassTextDim; font: accentHex.font }
                                            onTextEdited: if (/^#[0-9a-fA-F]{6}$/.test(text)) root.stagedAccent = text.toLowerCase()
                                        }
                                        TextButton { compact: true; text: "Pick"; onClicked: root.pickAccentFromScreen() }
                                        TextButton { compact: true; text: "Cancel"; onClicked: { root.stagedAccent=Config.appearance.accentOverride; root.accentPaletteOpen=false } }
                                        TextButton { compact: true; text: "Select"; enabled: /^#[0-9a-fA-F]{6}$/.test(accentHex.text); onClicked: { AppearanceService.setAccentOverride(root.stagedAccent); root.accentPaletteOpen=false } }
                                    }
                                }
                            }

                            InfoStrip {
                                Layout.fillWidth: true
                                glyph: "󰏘"
                                error: AppearanceService.errorMessage.length > 0
                                accent: AppearanceService.errorMessage.length > 0
                                    ? Theme.error : AdaptiveColor.activeFill
                                message: AppearanceService.errorMessage.length > 0
                                    ? AppearanceService.errorMessage
                                    : AppearanceService.statusMessage.length > 0
                                        ? AppearanceService.statusMessage
                                        : "Palette changes update the shell and enabled integrations live."
                            }

                            // ---- Typography ----------------------------------
                            // Each face is independently pickable from every
                            // family Qt actually has installed (Qt.fontFamilies())
                            // -- not a fixed list -- and applies live via
                            // Config.appearance.*FontFamily, which already reads
                            // through SettingsStore.fontFamilyValue().
                            FontRoleCard {
                                Layout.fillWidth: true
                                label: "UI font"
                                detail: "Tiles, body text, and controls"
                                configKey: "fontFamily"
                                currentFamily: Config.appearance.fontFamily
                                open: root.fontPickerOpen === "fontFamily"
                                onToggled: root.fontPickerOpen =
                                    root.fontPickerOpen === "fontFamily" ? "" : "fontFamily"
                                onFamilyChosen: family => {
                                    SettingsStore.setFontFamily("fontFamily", family)
                                    root.fontPickerOpen = ""
                                }
                            }
                            FontRoleCard {
                                Layout.fillWidth: true
                                label: "Mono font"
                                detail: "Numerals, ids, durations -- always tabular"
                                configKey: "monoFontFamily"
                                currentFamily: Config.appearance.monoFontFamily
                                open: root.fontPickerOpen === "monoFontFamily"
                                onToggled: root.fontPickerOpen =
                                    root.fontPickerOpen === "monoFontFamily" ? "" : "monoFontFamily"
                                onFamilyChosen: family => {
                                    SettingsStore.setFontFamily("monoFontFamily", family)
                                    root.fontPickerOpen = ""
                                }
                            }
                            FontRoleCard {
                                Layout.fillWidth: true
                                label: "Clock font"
                                detail: "The resting Island pill's clock"
                                configKey: "clockFontFamily"
                                currentFamily: Config.appearance.clockFontFamily
                                open: root.fontPickerOpen === "clockFontFamily"
                                onToggled: root.fontPickerOpen =
                                    root.fontPickerOpen === "clockFontFamily" ? "" : "clockFontFamily"
                                onFamilyChosen: family => {
                                    SettingsStore.setFontFamily("clockFontFamily", family)
                                    root.fontPickerOpen = ""
                                }
                            }
                            FontRoleCard {
                                Layout.fillWidth: true
                                label: "Handwriting font"
                                detail: "Now Playing card only (Figma node 9:3)"
                                configKey: "handFontFamily"
                                currentFamily: Config.appearance.handFontFamily
                                open: root.fontPickerOpen === "handFontFamily"
                                onToggled: root.fontPickerOpen =
                                    root.fontPickerOpen === "handFontFamily" ? "" : "handFontFamily"
                                onFamilyChosen: family => {
                                    SettingsStore.setFontFamily("handFontFamily", family)
                                    root.fontPickerOpen = ""
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Font scale"
                                detail: Math.round(Config.appearance.fontScale * 100)
                                    + "% · Scales shared text and icon tokens shell-wide"
                                inlineLayout: true
                                contentHeight: 36
                                SettingsSlider {
                                    width: 190
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    from: 0.8
                                    to: 1.3
                                    stepSize: 0.05
                                    value: Config.appearance.fontScale
                                    onAdjusted: value => SettingsStore.setFontScale(value)
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Performance tier"
                                detail: "Auto detects battery/iGPU (services/PerformanceService.qml) · currently "
                                    + PerformanceService.tier
                                inlineLayout: true
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    Repeater {
                                        model: [
                                            { id: "auto", label: "Auto" },
                                            { id: "low", label: "Low" },
                                            { id: "high", label: "High" }
                                        ]
                                        delegate: SettingsChoice {
                                            required property var modelData
                                            compact: true
                                            label: modelData.label
                                            selected: Config.appearance.performanceTierOverride
                                                === modelData.id
                                            onActivated: SettingsStore
                                                .setPerformanceTierOverride(modelData.id)
                                        }
                                    }
                                }
                            }

                        }

                        ColumnLayout {
                            visible: root.section === "idle"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            HeaderToggleCard {
                                Layout.fillWidth: true
                                title: "Keep awake"
                                detail: "Prevents dimming, locking, display-off, suspend, and hibernate until disabled"
                                checked: IdleService.inhibited
                                onToggled: enabled => {
                                    if (enabled !== IdleService.inhibited)
                                        IdleService.toggleInhibition()
                                }
                            }

                            HeaderToggleCard {
                                Layout.fillWidth: true
                                title: "Power connection sound"
                                detail: Config.idle.powerSoundsEnabled
                                    ? "Play a chime when external power changes"
                                    : "Disabled · power changes remain visual only"
                                checked: Config.idle.powerSoundsEnabled
                                onToggled: enabled => SettingsStore
                                    .setPowerSoundsEnabled(enabled)
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Power profile"
                                detail: "Balance performance against battery life"
                                contentHeight: 44
                                // Moved here from the control centre's own root
                                // in the Phase A reskin -- the capability stays
                                // reachable, just relocated.
                                PowerProfileChooser {
                                    anchors.fill: parent
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.section === "displays"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Island placement"
                                detail: Config.displays.islandPolicy === "all"
                                    ? "Each connected display keeps its own Island"
                                    : "One persistent display owns the shell's surfaces"
                                inlineLayout: true
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    SettingsChoice {
                                        compact: true
                                        label: "All displays"
                                        selected: Config.displays.islandPolicy === "all"
                                        onActivated: HyprlandService
                                            .setIslandPolicy("all")
                                    }
                                    SettingsChoice {
                                        compact: true
                                        label: "Primary only"
                                        selected: Config.displays.islandPolicy === "primary"
                                        onActivated: HyprlandService
                                            .setIslandPolicy("primary")
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Primary display"
                                detail: !HyprlandService.primaryPreferenceAvailable
                                    ? Config.displays.primaryMonitor
                                        + " is disconnected · using "
                                        + HyprlandService.primaryMonitorName
                                    : "Active primary · "
                                        + HyprlandService.primaryMonitorName
                                inlineLayout: true
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    SettingsChoice {
                                        compact: true
                                        label: "Automatic"
                                        selected: Config.displays.primaryMonitor
                                            === "auto"
                                        onActivated: HyprlandService
                                            .setPrimaryMonitor("auto")
                                    }
                                    Repeater {
                                        model: HyprlandService.connectedMonitors
                                        delegate: SettingsChoice {
                                            required property var modelData
                                            compact: true
                                            label: modelData.name
                                            selected: Config.displays.primaryMonitor
                                                === modelData.name
                                            onActivated: HyprlandService
                                                .setPrimaryMonitor(modelData.name)
                                        }
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Monitor behavior"
                                detail: "Focused events follow the active display in All mode. Primary-only mode routes shortcuts, notifications, media, and system feedback to the chosen display."
                                contentHeight: 24
                                Text {
                                    anchors.fill: parent
                                    text: HyprlandService.connectedMonitors.length
                                        + " displays connected · top-center placement"
                                    color: AdaptiveColor.glassTextDim
                                    wrapMode: Text.WordWrap
                                    font.family: Config.appearance.fontFamily
                                    font.pixelSize: Theme.textSmall
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                TextButton {
                                    text: "Reset"
                                    onClicked: HyprlandService
                                        .resetDisplayPreferences()
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.section === "notifications"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            HeaderToggleCard {
                                Layout.fillWidth: true
                                title: "Do not disturb"
                                detail: "Silences standard alerts while retaining their history"
                                checked: NotificationService.doNotDisturb
                                onToggled: enabled => NotificationService
                                    .setDoNotDisturb(enabled)
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Island alerts"
                                detail: "Critical alerts can remain visible independently"
                                contentHeight: 68
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space2
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Standard notification banners"
                                        checked: Config.notifications.showPopups
                                        onToggled: enabled => NotificationService
                                            .setShowPopups(enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Allow critical alerts"
                                        checked: Config.notifications.allowCriticalAlerts
                                        onToggled: enabled => NotificationService
                                            .setAllowCriticalAlerts(enabled)
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Presentation time"
                                detail: "How long the Island keeps each alert visible"
                                contentHeight: 60
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space2
                                    StepperRow {
                                        Layout.fillWidth: true
                                        label: "Standard"
                                        value: Config.notifications.timeout / 1000
                                        from: 2; to: 10; suffix: "sec"
                                        onAdjusted: value => NotificationService
                                            .setDuration("timeout", value * 1000)
                                    }
                                    StepperRow {
                                        Layout.fillWidth: true
                                        label: "Critical"
                                        value: Config.notifications.criticalTimeout / 1000
                                        from: 4; to: 15; suffix: "sec"
                                        onAdjusted: value => NotificationService
                                            .setDuration("criticalTimeout", value * 1000)
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "History retention"
                                detail: "Older entries are discarded locally when the limit is reached"
                                contentHeight: 36
                                StepperRow {
                                    anchors.fill: parent
                                    label: "Recent items"
                                    value: Config.notifications.historyLimit
                                    from: 20; to: 100; suffix: ""
                                    onAdjusted: value => NotificationService
                                        .setHistoryLimit(value)
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                TextButton {
                                    text: "Reset"
                                    onClicked: NotificationService.resetPreferences()
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.section === "media"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            HeaderToggleCard {
                                Layout.fillWidth: true
                                title: "Track-change presentation"
                                detail: "Briefly surface new playback in the Island"
                                checked: Config.media.enabled
                                onToggled: enabled => MediaService
                                    .setPresentationsEnabled(enabled)
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Presentation time"
                                detail: "How long track changes remain visible"
                                contentHeight: 36
                                StepperRow {
                                    anchors.fill: parent
                                    label: "Track change"
                                    value: Config.media.presentationTimeout / 1000
                                    from: 2; to: 10; suffix: "sec"
                                    onAdjusted: value => MediaService
                                        .setPresentationTimeout(value * 1000)
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Player priority"
                                detail: "Choose how the shell responds when multiple players exist"
                                inlineLayout: true
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    SettingsChoice {
                                        compact: true
                                        label: "Keep selected"
                                        selected: !Config.media.preferPlaying
                                        onActivated: MediaService.setPreferPlaying(false)
                                    }
                                    SettingsChoice {
                                        compact: true
                                        label: "Follow playing"
                                        selected: Config.media.preferPlaying
                                        onActivated: MediaService.setPreferPlaying(true)
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Hover presence"
                                detail: "Decide when media artwork and metadata use hover space"
                                inlineLayout: true
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    Repeater {
                                        model: [
                                            { id: "hidden", label: "Hidden" },
                                            { id: "playing", label: "Playing" },
                                            { id: "available", label: "Available" }
                                        ]
                                        delegate: SettingsChoice {
                                            required property var modelData
                                            compact: true
                                            label: modelData.label
                                            selected: Config.media.hoverMode
                                                === modelData.id
                                            onActivated: MediaService
                                                .setHoverMode(modelData.id)
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                TextButton {
                                    text: "Reset"
                                    onClicked: MediaService.resetPreferences()
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.section === "wallpaper"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Apply selections to"
                                detail: Config.wallpaper.target === "all"
                                    ? "One selection updates every display"
                                    : "Selections affect the display that opened the shell"
                                inlineLayout: true
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    SettingsChoice {
                                        compact: true
                                        label: "This display"
                                        selected: Config.wallpaper.target === "current"
                                        onActivated: WallpaperService.setTarget("current")
                                    }
                                    SettingsChoice {
                                        compact: true
                                        label: "All displays"
                                        selected: Config.wallpaper.target === "all"
                                        onActivated: WallpaperService.setTarget("all")
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Transition"
                                detail: Config.appearance.reducedMotion
                                    ? "Reduced Motion applies changes instantly; your selection is saved."
                                    : WallpaperService.backendDetail
                                contentHeight: 104
                                ColumnLayout {
                                    anchors.fill: parent; spacing: Theme.space2
                                    GridLayout { Layout.fillWidth: true; columns: 4; columnSpacing: Theme.space1; rowSpacing: Theme.space1
                                        Repeater { model: [
                                            {id:"fade",label:"Fade"}, {id:"slide",label:"Slide"}, {id:"wipe",label:"Wipe"}, {id:"wave",label:"Wave"},
                                            {id:"expand",label:"Expand"}, {id:"contract",label:"Contract"}, {id:"spotlight",label:"Spotlight"}, {id:"random",label:"Random"}]
                                            delegate: SettingsChoice { required property var modelData; Layout.fillWidth: true; label: modelData.label; selected: Config.wallpaper.transition === modelData.id; onActivated: WallpaperService.setTransition(modelData.id) }
                                        }
                                    }
                                    RowLayout { Layout.fillWidth: true
                                        Text { Layout.fillWidth: true; text: "Duration"; color: AdaptiveColor.glassTextDim; font.family: Config.appearance.fontFamily; font.pixelSize: 10 }
                                        SettingsSlider { Layout.preferredWidth: 164; from: 0.3; to: 4.0; stepSize: 0.1; value: Config.wallpaper.transitionDuration; onAdjusted: value => WallpaperService.setTransitionDuration(value) }
                                        Text { Layout.preferredWidth: 34; horizontalAlignment: Text.AlignHCenter; text: Config.wallpaper.transitionDuration.toFixed(1) + " s"; color: AdaptiveColor.activeFill; font.family: Config.appearance.monoFontFamily; font.pixelSize: 9; font.weight: Font.DemiBold }
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Gallery density"
                                detail: "Changes browsing density without altering image files"
                                inlineLayout: true
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    Repeater {
                                        model: [
                                            { columns: 2, label: "Spacious" },
                                            { columns: 3, label: "Balanced" },
                                            { columns: 4, label: "Compact" }
                                        ]
                                        delegate: SettingsChoice {
                                            required property var modelData
                                            compact: true
                                            label: modelData.label
                                            selected: Config.wallpaper.galleryColumns
                                                === modelData.columns
                                            onActivated: WallpaperService
                                                .setGalleryColumns(modelData.columns)
                                        }
                                    }
                                }
                            }

                            HeaderToggleCard {
                                Layout.fillWidth: true
                                title: "Library refresh"
                                detail: "Rescan configured image folders when Wallpaper opens"
                                checked: Config.wallpaper.refreshOnOpen
                                onToggled: enabled => WallpaperService
                                    .setRefreshOnOpen(enabled)
                            }

                            InfoStrip {
                                Layout.fillWidth: true
                                glyph: "󰉋"
                                accent: Theme.tertiary
                                message: "Library: ~/wallpaper and ~/Pictures/Wallpapers · Color generation remains independently controlled under Palette."
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                TextButton {
                                    text: "Reset"
                                    onClicked: WallpaperService.resetPreferences()
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.section === "dashboard"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Overview sections"
                                detail: "The center always retains Media or System for balance"
                                contentHeight: 104
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space2
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Calendar, weather, and notification context"
                                        checked: Config.dashboard.showHero
                                        onToggled: enabled => SettingsStore
                                            .setDashboardSection("showHero", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Media card"
                                        checked: Config.dashboard.showMedia
                                        onToggled: enabled => SettingsStore
                                            .setDashboardSection("showMedia", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "System health card"
                                        checked: Config.dashboard.showSystem
                                        onToggled: enabled => SettingsStore
                                            .setDashboardSection("showSystem", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Quick status strip"
                                        checked: Config.dashboard.showQuickStrip
                                        onToggled: enabled => SettingsStore
                                            .setDashboardSection("showQuickStrip", enabled)
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Weather location"
                                detail: WeatherService.configured
                                    ? "Saved locally for Open-Meteo forecasts"
                                    : "Unconfigured — no forecast request is made"
                                contentHeight: 70
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.space2
                                        WeatherField {
                                            Layout.fillWidth: true
                                            label: "City or label"
                                            value: root.weatherNameDraft
                                            onEdited: value => root.weatherNameDraft = value
                                        }
                                        WeatherField {
                                            Layout.preferredWidth: 112
                                            label: "Latitude"
                                            value: root.weatherLatitudeDraft
                                            onEdited: value => root.weatherLatitudeDraft = value
                                        }
                                        WeatherField {
                                            Layout.preferredWidth: 112
                                            label: "Longitude"
                                            value: root.weatherLongitudeDraft
                                            onEdited: value => root.weatherLongitudeDraft = value
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Item { Layout.fillWidth: true }
                                        TextButton {
                                            compact: true
                                            text: "Clear"
                                            enabled: WeatherService.configured
                                            onClicked: {
                                                SettingsStore.clearWeatherLocation()
                                                root.weatherNameDraft = ""
                                                root.weatherLatitudeDraft = ""
                                                root.weatherLongitudeDraft = ""
                                            }
                                        }
                                        TextButton {
                                            compact: true
                                            text: "Save location"
                                            enabled: root.weatherDraftValid
                                            onClicked: SettingsStore.setWeatherLocation(
                                                root.weatherNameDraft,
                                                root.weatherLatitudeDraft,
                                                root.weatherLongitudeDraft)
                                        }
                                    }
                                }
                            }

                            InfoStrip {
                                Layout.fillWidth: true
                                glyph: "󰕮"
                                message: "Visible sections rebalance automatically inside the existing Dashboard size."
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                TextButton {
                                    text: "Reset"
                                    onClicked: SettingsStore.resetDashboard()
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.section === "widgets"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            HeaderToggleCard {
                                Layout.fillWidth: true
                                title: "Edit widgets"
                                detail: WidgetStore.editMode
                                    ? "Drag to move, tap a slot to add or remove -- see the palette on screen"
                                    : "Turn on to move, resize, add, or remove desktop widgets"
                                checked: WidgetStore.editMode
                                onToggled: enabled => {
                                    if (enabled !== WidgetStore.editMode)
                                        WidgetStore.toggleEditMode()
                                }
                            }

                            InfoStrip {
                                Layout.fillWidth: true
                                glyph: "󰊗"
                                message: "Widgets live on the desktop, not inside the Island -- this toggles the same edit mode as `qs -p ./shell.qml ipc call widgets edit`."
                            }
                        }

                        ColumnLayout {
                            visible: root.section === "command-launcher"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Shell history source"
                                detail: "Read on demand from the current user's existing history"
                                contentHeight: 34
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    Repeater {
                                        model: [
                                            { id: "auto", label: "Auto" },
                                            { id: "zsh", label: "Zsh" },
                                            { id: "bash", label: "Bash" },
                                            { id: "fish", label: "Fish" }
                                        ]
                                        delegate: SettingsChoice {
                                            required property var modelData
                                            compact: true
                                            label: modelData.label
                                            selected: Config.commandLauncher.historySource
                                                === modelData.id
                                            onActivated: SettingsStore
                                                .setCommandHistorySource(modelData.id)
                                        }
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Terminal"
                                detail: "A new terminal opens on the current workspace"
                                contentHeight: 34
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    Repeater {
                                        model: [
                                            { id: "auto", label: "Auto" },
                                            { id: "kitty", label: "Kitty" },
                                            { id: "foot", label: "Foot" },
                                            { id: "alacritty", label: "Alacritty" },
                                            { id: "ghostty", label: "Ghostty" }
                                        ]
                                        delegate: SettingsChoice {
                                            required property var modelData
                                            compact: true
                                            label: modelData.label
                                            selected: Config.commandLauncher.terminal
                                                === modelData.id
                                            onActivated: SettingsStore
                                                .setCommandTerminal(modelData.id)
                                        }
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "History suggestions"
                                detail: Config.commandLauncher.historySuggestions
                                    ? "Recent local commands appear when the query is empty"
                                    : "Only exact commands typed into the launcher are shown"
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Show local shell history"
                                        color: AdaptiveColor.glassText
                                        font.family: Config.appearance.fontFamily
                                        font.pixelSize: Theme.textSmall
                                    }
                                    SettingsToggle {
                                        checked: Config.commandLauncher.historySuggestions
                                        onToggled: enabled => SettingsStore
                                            .setCommandHistorySuggestions(enabled)
                                    }
                                }
                            }

                            InfoStrip {
                                Layout.fillWidth: true
                                glyph: "󰆍"
                                message: "History stays local and is never copied into a shell database. Enter runs; Ctrl+C or Ctrl+Enter copies without execution."
                            }
                        }

                        ColumnLayout {
                            visible: root.section === "island"
                                && root.islandEditor === "overview"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            SettingsActionCard {
                                Layout.fillWidth: true
                                title: "Island geometry"
                                detail: "Live placement · " + Config.island.dormantWidth
                                    + " / " + Config.island.hoverWidth + " / "
                                    + Config.island.expandedWidth + " px"
                                actionText: "Live edit"
                                onActivated: {
                                    root.pillPreviewMode = "rest"
                                    root.islandEditor = "geometry"
                                    settingsScroll.contentY = 0
                                }
                            }

                            SettingsActionCard {
                                Layout.fillWidth: true
                                title: "Resting & Hover Island"
                                detail: Config.island.restItemOrder.length
                                    + " resting · " + Config.island.hoverItemOrder.length
                                    + " hover items · order, spacing, and scale"
                                actionText: "Edit items"
                                onActivated: {
                                    root.pillPreviewMode = "rest"
                                    root.islandEditor = "content"
                                    settingsScroll.contentY = 0
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Clock format"
                                detail: "Applies to the resting pill, hover view, and shell clock"
                                inlineLayout: true
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space2
                                    Item { Layout.fillWidth: true }
                                    SettingsChoice {
                                        compact: true
                                        label: "12 hour"
                                        selected: !Config.appearance.use24HourClock
                                        onActivated: SettingsStore.setClock24Hour(false)
                                    }
                                    SettingsChoice {
                                        compact: true
                                        label: "24 hour"
                                        selected: Config.appearance.use24HourClock
                                        onActivated: SettingsStore.setClock24Hour(true)
                                    }
                                }
                            }

                            SettingsCard {
                                visible: false
                                Layout.fillWidth: true
                                title: "Resting pill content"
                                detail: "Choose which glanceable items remain visible at rest"
                                contentHeight: 148
                                GridLayout {
                                    anchors.fill: parent
                                    columns: 2
                                    columnSpacing: Theme.space4
                                    rowSpacing: Theme.space2
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Weather"
                                        checked: Config.island.restShowWeather
                                        onToggled: enabled => root.setIslandItem(
                                            "rest", "Weather", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Do not disturb"
                                        checked: Config.island.restShowDnd
                                        onToggled: enabled => root.setIslandItem(
                                            "rest", "Dnd", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Keep awake"
                                        checked: Config.island.restShowKeepAwake
                                        onToggled: enabled => root.setIslandItem(
                                            "rest", "KeepAwake", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Power profile"
                                        checked: Config.island.restShowPowerProfile
                                        onToggled: enabled => root.setIslandItem(
                                            "rest", "PowerProfile", enabled)
                                    }
                                }
                            }

                            SettingsCard {
                                visible: false
                                Layout.fillWidth: true
                                title: "Hover pill content"
                                detail: "Add or remove status groups from the expanded glance"
                                contentHeight: 148
                                GridLayout {
                                    anchors.fill: parent
                                    columns: 2
                                    columnSpacing: Theme.space4
                                    rowSpacing: Theme.space2
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Workspaces"
                                        checked: Config.island.hoverShowWorkspaces
                                        onToggled: enabled => root.setIslandItem(
                                            "hover", "Workspaces", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Clock & date"
                                        checked: Config.island.hoverShowClock
                                        onToggled: enabled => root.setIslandItem(
                                            "hover", "Clock", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Audio"
                                        checked: Config.island.hoverShowAudio
                                        onToggled: enabled => root.setIslandItem(
                                            "hover", "Audio", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Network"
                                        checked: Config.island.hoverShowNetwork
                                        onToggled: enabled => root.setIslandItem(
                                            "hover", "Network", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Do not disturb"
                                        checked: Config.island.hoverShowDnd
                                        onToggled: enabled => root.setIslandItem(
                                            "hover", "Dnd", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Bluetooth"
                                        checked: Config.island.hoverShowBluetooth
                                        onToggled: enabled => root.setIslandItem(
                                            "hover", "Bluetooth", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Keep awake"
                                        checked: Config.island.hoverShowKeepAwake
                                        onToggled: enabled => root.setIslandItem(
                                            "hover", "KeepAwake", enabled)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Battery"
                                        checked: Config.island.hoverShowBattery
                                        onToggled: enabled => root.setIslandItem(
                                            "hover", "Battery", enabled)
                                    }
                                }
                            }

                            SettingsCard {
                                visible: false
                                Layout.fillWidth: true
                                title: "Item spacing"
                                detail: "Set the breathing room between visible pill items"
                                contentHeight: 72
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space2
                                    MetricRow {
                                        Layout.fillWidth: true
                                        label: "Resting pill"
                                        value: SettingsStore.numberValue(
                                            "island", "restItemSpacing", 8, 2, 18)
                                        from: 2; to: 18
                                        onAdjusted: value => root
                                            .setIslandSpacing("rest", value)
                                    }
                                    MetricRow {
                                        Layout.fillWidth: true
                                        label: "Hover pill"
                                        value: SettingsStore.numberValue(
                                            "island", "hoverItemSpacing", 8, 2, 20)
                                        from: 2; to: 20
                                        onAdjusted: value => root
                                            .setIslandSpacing("hover", value)
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Auto hide"
                                detail: Config.island.autoHide
                                    ? (Config.island.showRevealLip
                                        ? "Leaves a four-pixel reveal edge at the top of the display"
                                        : "Keeps the top-edge invisible until revealed")
                                    : "The resting pill remains visible"
                                headerToggleVisible: true
                                headerChecked: Config.island.autoHide
                                onHeaderToggled: enabled => SettingsStore
                                    .setIslandAutoHide(enabled)
                                contentHeight: 60
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space2
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Lip"
                                        checked: Config.island.showRevealLip
                                        available: Config.island.autoHide
                                        onToggled: enabled => SettingsStore
                                            .setIslandRevealLip(enabled)
                                    }
                                    StepperRow {
                                        Layout.fillWidth: true
                                        label: "Hide after"
                                        value: Config.island.autoHideDelay / 1000
                                        from: 1; to: 10; suffix: "sec"
                                        available: Config.island.autoHide
                                        onAdjusted: value => SettingsStore
                                            .setIslandMetric("autoHideDelay",
                                                value * 1000)
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Surface density"
                                detail: "Adjust shared spacing without changing type size"
                                inlineLayout: true
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    Repeater {
                                        model: [
                                            { id: "compact", label: "Compact" },
                                            { id: "balanced", label: "Balanced" },
                                            { id: "airy", label: "Airy" }
                                        ]
                                        delegate: SettingsChoice {
                                            required property var modelData
                                            compact: true
                                            label: modelData.label
                                            selected: Config.appearance.density
                                                === modelData.id
                                            onActivated: AppearanceService
                                                .setDensity(modelData.id)
                                        }
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Display scale"
                                // core/DisplayScale.qml: Auto reads the
                                // screen's physical PPI (BlobLayout.unit()/
                                // Theme.u()/font tokens all route through
                                // it); Manual pins a flat factor instead --
                                // e.g. this laptop's panel measures ~157 PPI
                                // and auto-computes ~1.36-1.38.
                                detail: Config.appearance.displayScale > 0
                                    ? Math.round(Config.appearance.displayScale * 100)
                                        + "% · Manual override"
                                    : Math.round(DisplayScale.primary * 100)
                                        + "% · Auto from this screen's PPI"
                                contentHeight: Config.appearance.displayScale > 0 ? 72 : 36
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.space1
                                        Item { Layout.fillWidth: true }
                                        SettingsChoice {
                                            compact: true
                                            label: "Auto"
                                            selected: Config.appearance.displayScale <= 0
                                            onActivated: SettingsStore.setDisplayScale(0)
                                        }
                                        SettingsChoice {
                                            compact: true
                                            label: "Manual"
                                            selected: Config.appearance.displayScale > 0
                                            onActivated: SettingsStore.setDisplayScale(
                                                Config.appearance.displayScale > 0
                                                    ? Config.appearance.displayScale
                                                    : DisplayScale.primary)
                                        }
                                    }
                                    SettingsSlider {
                                        Layout.fillWidth: true
                                        visible: Config.appearance.displayScale > 0
                                        from: 1.0
                                        to: 2.0
                                        stepSize: 0.05
                                        value: Config.appearance.displayScale > 0
                                            ? Config.appearance.displayScale
                                            : DisplayScale.primary
                                        onAdjusted: value => SettingsStore.setDisplayScale(value)
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Corner character"
                                detail: "Affects shared cards, controls, and expanded surfaces"
                                inlineLayout: true
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    Repeater {
                                        model: [
                                            { id: "subtle", label: "Subtle" },
                                            { id: "balanced", label: "Balanced" },
                                            { id: "round", label: "Round" }
                                        ]
                                        delegate: SettingsChoice {
                                            required property var modelData
                                            compact: true
                                            label: modelData.label
                                            selected: Config.appearance.cornerStyle
                                                === modelData.id
                                            onActivated: AppearanceService
                                                .setCornerStyle(modelData.id)
                                        }
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Animation"
                                detail: "Controls morphs, fades, and feedback timing"
                                inlineLayout: true
                                contentHeight: 36
                                RowLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space1
                                    Item { Layout.fillWidth: true }
                                    Repeater {
                                        model: [
                                            { id: "quick", label: "Quick" },
                                            { id: "balanced", label: "Balanced" },
                                            { id: "calm", label: "Calm" }
                                        ]
                                        delegate: SettingsChoice {
                                            required property var modelData
                                            compact: true
                                            label: modelData.label
                                            selected: Config.appearance.motionSpeed
                                                === modelData.id
                                            available: !Config.appearance.reducedMotion
                                            onActivated: AppearanceService
                                                .setMotionSpeed(modelData.id)
                                        }
                                    }
                                }
                            }

                            HeaderToggleCard {
                                Layout.fillWidth: true
                                title: "Reduce motion"
                                detail: "Minimizes Island morphs, fades, and animated feedback"
                                checked: Config.appearance.reducedMotion
                                onToggled: enabled => AppearanceService
                                    .setReducedMotion(enabled)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                TextButton {
                                    text: "Reset"
                                    onClicked: AppearanceService.resetIslandAndMotion()
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.section === "island"
                                && root.islandEditor === "geometry"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            RowLayout {
                                Layout.fillWidth: true
                                TextButton {
                                    text: "‹ Back"
                                    onClicked: root.islandEditor = "overview"
                                }
                                Item { Layout.fillWidth: true }
                                SettingsChoice {
                                    Layout.preferredWidth: 78
                                    label: "Resting"
                                    selected: root.pillPreviewMode === "rest"
                                    onActivated: root.pillPreviewMode = "rest"
                                }
                                SettingsChoice {
                                    Layout.preferredWidth: 78
                                    label: "Hover"
                                    selected: root.pillPreviewMode === "hover"
                                    onActivated: root.pillPreviewMode = "hover"
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Screen placement"
                                detail: "Position the Island and reserve clear workspace below it"
                                contentHeight: 52
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space2
                                    MetricRow {
                                        Layout.fillWidth: true
                                        label: "Top gap"
                                        // BASE (unscaled) value -- Config.island.topMargin
                                        // now carries DisplayScale.primary, and reading
                                        // it here would show/store an already-scaled
                                        // number, compounding on the next drag.
                                        value: SettingsStore.numberValue(
                                            "island", "topMargin", 5, 0, 16)
                                        from: 0; to: 16
                                        onAdjusted: value => AppearanceService
                                            .setIslandMetric("topMargin", value)
                                    }
                                    MetricRow {
                                        Layout.fillWidth: true
                                        label: "Workspace clearance"
                                        value: SettingsStore.numberValue(
                                            "island", "reservedSpace", 30, 26, 52)
                                        from: 26; to: 52
                                        onAdjusted: value => AppearanceService
                                            .setIslandMetric("reservedSpace", value)
                                    }
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: "Island widths"
                                detail: "The live preview above follows the selected resting or hover state"
                                contentHeight: 80
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space2
                                    MetricRow {
                                        Layout.fillWidth: true
                                        label: "Resting width"
                                        // BASE (unscaled) value -- see the "Top gap"
                                        // MetricRow's own comment above.
                                        value: SettingsStore.numberValue(
                                            "island", "dormantWidth", 104, 96, 320)
                                        from: 214; to: 320
                                        onAdjusted: value => AppearanceService
                                            .setIslandMetric("dormantWidth", value)
                                    }
                                    MetricRow {
                                        Layout.fillWidth: true
                                        label: "Hover width"
                                        value: SettingsStore.numberValue(
                                            "island", "hoverWidth", 470, 470, 760)
                                        from: 470; to: 760
                                        onAdjusted: value => AppearanceService
                                            .setIslandMetric("hoverWidth", value)
                                    }
                                    MetricRow {
                                        Layout.fillWidth: true
                                        label: "Expanded width"
                                        value: SettingsStore.numberValue(
                                            "island", "expandedWidth", 789, 620, 900)
                                        from: 620; to: 900
                                        onAdjusted: value => AppearanceService
                                            .setIslandMetric("expandedWidth", value)
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.section === "island"
                                && root.islandEditor === "content"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            RowLayout {
                                Layout.fillWidth: true
                                TextButton {
                                    text: "‹ Back"
                                    onClicked: root.islandEditor = "overview"
                                }
                                Item { Layout.fillWidth: true }
                                SettingsChoice {
                                    Layout.preferredWidth: 84
                                    label: "Resting"
                                    selected: root.pillPreviewMode === "rest"
                                    onActivated: root.pillPreviewMode = "rest"
                                }
                                SettingsChoice {
                                    Layout.preferredWidth: 84
                                    label: "Hover"
                                    selected: root.pillPreviewMode === "hover"
                                    onActivated: root.pillPreviewMode = "hover"
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: root.pillPreviewMode === "rest"
                                    ? "Resting Island items" : "Hover Island items"
                                detail: root.pillPreviewMode === "rest"
                                    ? "Arrange the surrounding resting items"
                                    : "Drag items into slots, between slots, or into remove"
                                contentHeight: root.pillPreviewMode === "rest" ? 185 : 224
                                IslandOrderEditor {
                                    anchors.fill: parent
                                    context: root.pillPreviewMode
                                }
                            }

                            SettingsCard {
                                Layout.fillWidth: true
                                title: root.pillPreviewMode === "rest"
                                    ? "Resting spacing & scale"
                                    : "Hover spacing & scale"
                                detail: root.pillPreviewMode === "rest"
                                    ? "Tune resting spacing, text, and icon scale"
                                    : "Spacing is automatically limited when the chosen width is full"
                                contentHeight: 110
                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.space2
                                    MetricRow {
                                        Layout.fillWidth: true
                                        label: "Item spacing"
                                        // BASE (unscaled) value -- see the geometry
                                        // page's "Top gap" MetricRow comment above.
                                        value: root.pillPreviewMode === "rest"
                                            ? SettingsStore.numberValue(
                                                "island", "restItemSpacing", 8, 2, 18)
                                            : SettingsStore.numberValue(
                                                "island", "hoverItemSpacing", 8, 2, 20)
                                        from: 2
                                        to: root.pillPreviewMode === "rest" ? 18 : 20
                                        onAdjusted: value => root.setIslandSpacing(
                                            root.pillPreviewMode, value)
                                    }
                                    PreferenceToggleRow {
                                        Layout.fillWidth: true
                                        label: "Sync text and icons"
                                        checked: root.pillPreviewMode === "rest"
                                            ? Config.island.restScaleSynced
                                            : Config.island.hoverScaleSynced
                                        onToggled: enabled => SettingsStore
                                            .setIslandContentSync(
                                                root.pillPreviewMode, enabled)
                                    }
                                    MetricRow {
                                        Layout.fillWidth: true
                                        label: "Text size"
                                        // BASE (unscaled) value -- Config.island.
                                        // rest/hoverTextScale now carry
                                        // DisplayScale.primary too (core/Config.qml),
                                        // and reading that here would show/store an
                                        // already-scaled percentage, compounding on
                                        // the next drag. Same fix as the geometry
                                        // sliders above.
                                        value: SettingsStore.numberValue("island",
                                            root.pillPreviewMode === "rest"
                                                ? "restTextScale" : "hoverTextScale",
                                            100, 80, 130)
                                        from: 80; to: 130; suffix: "%"
                                        onAdjusted: value => SettingsStore
                                            .setIslandContentScale(
                                                root.pillPreviewMode, "text", value)
                                    }
                                    MetricRow {
                                        Layout.fillWidth: true
                                        label: "Icon size"
                                        value: SettingsStore.numberValue("island",
                                            root.pillPreviewMode === "rest"
                                                ? "restIconScale" : "hoverIconScale",
                                            100, 80, 130)
                                        from: 80; to: 130; suffix: "%"
                                        onAdjusted: value => SettingsStore
                                            .setIslandContentScale(
                                                root.pillPreviewMode, "icon", value)
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            visible: root.section === "integrations"
                            Layout.fillWidth: true
                            spacing: Theme.space2

                            IntegrationRow {
                                Layout.fillWidth: true
                                name: "Shell"
                                detail: "Wallpaper-derived semantic colors"
                                integrationEnabled: Config.appearance.wallpaperPaletteEnabled
                                available: true
                                managed: true
                                onToggleRequested: enabled =>
                                    AppearanceService.setOdysseyPaletteEnabled(enabled)
                            }
                            IntegrationRow { Layout.fillWidth: true; name: "Hyprland"; detail: "Window borders and compositor colors" }
                            IntegrationRow { Layout.fillWidth: true; name: "GTK / Thunar"; detail: "Application toolkit theme" }
                            IntegrationRow { Layout.fillWidth: true; name: "Qt"; detail: "Qt application color scheme" }

                            InfoStrip {
                                Layout.fillWidth: true
                                Layout.topMargin: Theme.space1
                                glyph: "󰋼"
                                message: "Manual means the shell leaves that target untouched. Managed targets use reversible ownership records and refuse conflicting external edits."
                            }
                        }
                    }
                }
            }
        }
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
        radius: Theme.radiusMedium
        color: Qt.alpha(Theme.surfaceContainerHigh,
            Theme.dark ? 0.58 : 0.48)
        borderWidth: 1
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
                        color: AdaptiveColor.glassText
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Theme.textSmall
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: card.detail
                        color: AdaptiveColor.glassTextDim
                        font.family: Config.appearance.fontFamily
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

    component SettingsActionCard: Squircle {
        id: actionCard
        property string title: ""
        property string detail: ""
        property string actionText: ""
        signal activated()
        implicitHeight: 52
        radius: Theme.radiusMedium
        color: Qt.alpha(Theme.surfaceContainerHigh,
            Theme.dark ? 0.42 : 0.34)
        borderWidth: 1
        borderColor: Qt.alpha(Theme.outlineVariant, 0.28)

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.space3
            spacing: Theme.space2
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: actionCard.title
                    color: AdaptiveColor.glassText
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.textSmall
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: actionCard.detail
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
            TextButton {
                text: actionCard.actionText
                compact: true
                onClicked: actionCard.activated()
            }
        }
    }

    component AccentSwatch: Rectangle {
        id: swatch
        property color swatchColor: AdaptiveColor.activeFill
        property string glyph: ""
        property bool selected: false
        signal activated()
        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        radius: width / 2
        color: swatch.swatchColor
        border.width: swatch.selected || swatch.activeFocus ? 2 : 1
        border.color: swatch.selected || swatch.activeFocus
            ? AdaptiveColor.glassText : Qt.alpha(Theme.outlineVariant, 0.72)
        activeFocusOnTab: true

        Text {
            anchors.centerIn: parent
            visible: swatch.glyph.length > 0
            text: swatch.glyph
            color: Theme.foregroundFor(swatch.swatchColor)
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: Theme.iconSmall
        }
        Keys.onReturnPressed: swatch.activated()
        Keys.onEnterPressed: swatch.activated()
        Keys.onSpacePressed: swatch.activated()
        TapHandler {
            onTapped: {
                swatch.forceActiveFocus()
                swatch.activated()
            }
        }
    }

    component AccentPaletteSwatch: Rectangle {
        id: paletteSwatch
        property color swatchColor: AdaptiveColor.activeFill
        property bool selected: false
        signal activated()
        Layout.preferredWidth: 31
        Layout.preferredHeight: 22
        radius: 5
        color: swatchColor
        border.width: selected || activeFocus ? 2 : 1
        border.color: selected || activeFocus ? AdaptiveColor.glassText
            : Qt.alpha(Theme.outlineVariant, 0.72)
        activeFocusOnTab: true
        Keys.onReturnPressed: activated()
        Keys.onEnterPressed: activated()
        Keys.onSpacePressed: activated()
        TapHandler { onTapped: { paletteSwatch.forceActiveFocus(); paletteSwatch.activated() } }
    }

    // Font role picker: shows the current family (rendered IN that family,
    // so the label is its own preview) and a "Change" toggle that expands a
    // searchable, scrollable list of every family Qt.fontFamilies() reports
    // as installed. Same expand-in-place interaction as "Accent color
    // override" above -- no popup/dialog, and no bento card border/fill
    // beyond the shared SettingsCard-style surface every other row here uses.
    component FontRoleCard: Rectangle {
        id: fontCard
        property string label: ""
        property string detail: ""
        property string configKey: ""
        property string currentFamily: ""
        property bool open: false
        property string filterText: ""
        signal toggled()
        signal familyChosen(string family)
        readonly property var filteredFamilies: {
            const all = Qt.fontFamilies()
            const query = fontCard.filterText.trim().toLowerCase()
            return query.length === 0 ? all
                : all.filter(family => family.toLowerCase().indexOf(query) >= 0)
        }
        Layout.fillWidth: true
        implicitHeight: Math.round(cardHeightMV.value)
        radius: Theme.radiusMedium
        color: Qt.alpha(Theme.surfaceContainerHigh, Theme.dark ? 0.58 : 0.48)
        border.width: 1
        border.color: Qt.alpha(Theme.outlineVariant, 0.28)
        clip: true
        property MotionValue cardHeightMV: MotionValue {
            unit: "px"
            omega: Motion.presetSmooth().omega
            zeta: Motion.presetSmooth().zeta
            target: fontCard.open ? 246 : 60
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space3
            spacing: Theme.space2

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space2
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: fontCard.label
                        color: AdaptiveColor.glassText
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: Theme.textSmall
                        font.weight: Font.DemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: fontCard.detail + " · " + fontCard.currentFamily
                        color: AdaptiveColor.glassTextDim
                        elide: Text.ElideRight
                        // Live preview: the detail line is set IN the
                        // currently chosen family for that role.
                        font.family: fontCard.currentFamily
                        font.pixelSize: 10
                    }
                }
                TextButton {
                    compact: true
                    text: fontCard.open ? "Close" : "Change"
                    onClicked: fontCard.toggled()
                }
            }

            ColumnLayout {
                visible: fontCard.open
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.space1

                Squircle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: Theme.radiusSmall
                    color: filterInput.activeFocus
                        ? Qt.alpha(Theme.primaryContainer, 0.36)
                        : Qt.alpha(Theme.surfaceContainer, 0.72)
                    borderWidth: 1
                    borderColor: filterInput.activeFocus
                        ? AdaptiveColor.activeFill : Qt.alpha(Theme.outlineVariant, 0.42)
                    TextInput {
                        id: filterInput
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space2
                        anchors.rightMargin: Theme.space2
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        color: AdaptiveColor.glassText
                        font.family: Config.appearance.fontFamily
                        font.pixelSize: 10
                        onTextEdited: fontCard.filterText = text
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: filterInput.text.length === 0
                                && !filterInput.activeFocus
                            text: "Search " + fontCard.filteredFamilies.length
                                + " installed fonts…"
                            color: AdaptiveColor.glassTextDim
                            font: filterInput.font
                        }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: fontCard.open ? fontCard.filteredFamilies : []
                    delegate: Squircle {
                        id: familyRow
                        required property string modelData
                        width: ListView.view ? ListView.view.width : 0
                        height: 26
                        radius: Theme.radiusSmall
                        color: familyRow.modelData === fontCard.currentFamily
                            ? Qt.alpha(Theme.primaryContainer, 0.62)
                            : familyHover.hovered
                                ? Qt.alpha(AdaptiveColor.glassText, 0.06) : "transparent"
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.space2
                            anchors.rightMargin: Theme.space2
                            text: familyRow.modelData
                            elide: Text.ElideRight
                            color: AdaptiveColor.glassText
                            font.family: familyRow.modelData
                            font.pixelSize: 11
                        }
                        HoverHandler { id: familyHover }
                        TapHandler {
                            onTapped: fontCard.familyChosen(familyRow.modelData)
                        }
                    }
                }
            }
        }
    }

    component InfoStrip: Squircle {
        id: infoStrip
        property string glyph: "󰋼"
        property string message: ""
        property color accent: AdaptiveColor.activeFill
        property bool error: false
        implicitHeight: Math.max(44, infoMessage.implicitHeight
            + Theme.space2 * 2)
        radius: Theme.radiusMedium
        color: Qt.alpha(Theme.primaryContainer, 0.16)
        borderWidth: 1
        borderColor: Qt.alpha(accent, 0.30)

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.space2
            spacing: Theme.space2
            Text {
                text: infoStrip.glyph
                color: infoStrip.accent
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: Theme.iconSmall
            }
            Text {
                id: infoMessage
                Layout.fillWidth: true
                text: infoStrip.message
                color: infoStrip.error ? Theme.error : AdaptiveColor.glassTextDim
                wrapMode: Text.WordWrap
                font.family: Config.appearance.fontFamily
                font.pixelSize: 10
            }
        }
    }

    component HeaderToggleCard: Squircle {
        id: headerToggle
        property string title: ""
        property string detail: ""
        property bool checked: false
        signal toggled(bool enabled)
        implicitHeight: 52
        radius: Theme.radiusMedium
        color: Qt.alpha(Theme.surfaceContainerHigh,
            Theme.dark ? 0.42 : 0.34)
        borderWidth: 1
        borderColor: Qt.alpha(Theme.outlineVariant, 0.28)

        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.space3
            spacing: Theme.space2
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    text: headerToggle.title
                    color: AdaptiveColor.glassText
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.textSmall
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: headerToggle.detail
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
            SettingsToggle {
                checked: headerToggle.checked
                onToggled: enabled => headerToggle.toggled(enabled)
            }
        }
    }

    component StepperRow: RowLayout {
        id: stepperRow
        property string label: ""
        property real value: 0
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property string suffix: ""
        property bool available: true
        signal adjusted(real value)
        enabled: available
        opacity: available ? 1 : 0.38
        spacing: Theme.space2
        Text {
            Layout.fillWidth: true
            text: stepperRow.label
            color: AdaptiveColor.glassText
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textSmall
            elide: Text.ElideRight
        }
        SettingsStepper {
            Layout.preferredWidth: implicitWidth
            from: stepperRow.from
            to: stepperRow.to
            value: stepperRow.value
            stepSize: stepperRow.stepSize
            suffix: stepperRow.suffix
            available: stepperRow.available
            onAdjusted: value => stepperRow.adjusted(value)
        }
    }

    component MetricRow: RowLayout {
        id: metric
        property string label: ""
        property real value: 0
        property real from: 0
        property real to: 100
        property bool available: true
        property bool editable: false
        property string suffix: " px"
        property real valueWidth: 44
        property real sliderWidth: 164
        signal adjusted(real value)
        enabled: available
        opacity: available ? 1 : 0.38
        spacing: Theme.space2
        Text {
            Layout.fillWidth: true
            text: metric.label
            color: AdaptiveColor.glassText
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textSmall
            elide: Text.ElideRight
        }
        SettingsSlider {
            Layout.preferredWidth: metric.sliderWidth
            Layout.maximumWidth: metric.sliderWidth
            from: metric.from
            to: metric.to
            value: metric.value
            available: metric.available
            stepSize: 1
            onAdjusted: value => metric.adjusted(value)
        }
        Squircle {
            visible: !metric.editable
            Layout.preferredWidth: metric.valueWidth
            Layout.preferredHeight: 22
            radius: Theme.radiusSmall
            color: Qt.alpha(Theme.surfaceContainer, 0.72)
            Text {
                anchors.centerIn: parent
                text: Math.round(metric.value) + metric.suffix
                color: AdaptiveColor.activeFill
                font.family: Config.appearance.monoFontFamily
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }
        Squircle {
            visible: metric.editable
            Layout.preferredWidth: visible ? metric.valueWidth : 0
            Layout.preferredHeight: 22
            radius: Theme.radiusSmall
            color: valueInput.activeFocus
                ? Qt.alpha(Theme.primaryContainer, 0.42)
                : Qt.alpha(Theme.surfaceContainerHigh, 0.72)
            borderWidth: 1
            borderColor: valueInput.activeFocus
                ? AdaptiveColor.activeFill : Qt.alpha(Theme.outlineVariant, 0.54)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space1
                anchors.rightMargin: Theme.space1
                spacing: 2
                TextInput {
                    id: valueInput
                    property bool cancelEdit: false
                    Layout.fillWidth: true
                    color: AdaptiveColor.activeFill
                    selectionColor: Theme.primaryContainer
                    selectedTextColor: Theme.primaryContainerText
                    horizontalAlignment: TextInput.AlignRight
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator {
                        bottom: Math.ceil(metric.from)
                        top: Math.floor(metric.to)
                    }
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    function restoreValue(): void {
                        text = Math.round(metric.value).toString()
                    }
                    function commitValue(): void {
                        const nextValue = Number(text)
                        if (acceptableInput && Number.isFinite(nextValue))
                            metric.adjusted(nextValue)
                    }
                    onActiveFocusChanged: {
                        if (activeFocus)
                            selectAll()
                        else {
                            if (!cancelEdit)
                                commitValue()
                            cancelEdit = false
                            restoreValue()
                        }
                    }
                    onAccepted: focus = false
                    Keys.onEscapePressed: event => {
                        cancelEdit = true
                        focus = false
                        event.accepted = true
                    }
                    Component.onCompleted: restoreValue()
                }
                Connections {
                    target: metric
                    function onValueChanged(): void {
                        if (!valueInput.activeFocus)
                            valueInput.restoreValue()
                    }
                }
                Text {
                    text: metric.suffix.trim()
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 9
                }
            }

            Behavior on color { ColorAnimation { duration: Animations.fast } }
            Behavior on borderColor { ColorAnimation { duration: Animations.fast } }
        }
    }

    component WeatherField: Squircle {
        id: weatherField
        property string label: ""
        property string value: ""
        signal edited(string value)
        implicitHeight: 32
        radius: Theme.radiusSmall
        color: weatherInput.activeFocus
            ? Qt.alpha(Theme.primaryContainer, 0.36)
            : Qt.alpha(Theme.surfaceContainerHigh, 0.60)
        borderWidth: 1
        borderColor: weatherInput.activeFocus
            ? AdaptiveColor.activeFill : Qt.alpha(Theme.outlineVariant, 0.42)

        TextInput {
            id: weatherInput
            anchors.fill: parent
            anchors.leftMargin: Theme.space2
            anchors.rightMargin: Theme.space2
            text: weatherField.value
            color: AdaptiveColor.glassText
            selectionColor: Theme.primaryContainer
            selectedTextColor: Theme.primaryContainerText
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            font.family: Config.appearance.fontFamily
            font.pixelSize: 10
            onTextEdited: weatherField.edited(text)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: weatherInput.text.length === 0
                    && !weatherInput.activeFocus
                text: weatherField.label
                color: AdaptiveColor.glassTextDim
                font: weatherInput.font
            }
        }
    }

    component PreferenceToggleRow: RowLayout {
        id: preference
        property string label: ""
        property bool checked: false
        property bool available: true
        signal toggled(bool enabled)
        enabled: available
        opacity: available ? 1 : 0.42
        spacing: Theme.space2
        Text {
            Layout.fillWidth: true
            text: preference.label
            color: AdaptiveColor.glassText
            font.family: Config.appearance.fontFamily
            font.pixelSize: Theme.textSmall
            elide: Text.ElideRight
        }
        SettingsToggle {
            checked: preference.checked
            available: preference.available
            onToggled: enabled => preference.toggled(enabled)
        }
    }

    component IntegrationRow: Squircle {
        id: integration
        property string name: ""
        property string detail: ""
        property bool integrationEnabled: false
        property bool available: false
        property bool managed: false
        signal toggleRequested(bool enabled)
        implicitHeight: 56
        radius: Theme.radiusMedium
        color: Qt.alpha(Theme.surfaceContainerHigh,
            Theme.dark ? 0.42 : 0.34)
        borderWidth: 1
        borderColor: Qt.alpha(Theme.outlineVariant, 0.28)
        RowLayout {
            anchors.fill: parent
            anchors.margins: Theme.space3
            spacing: Theme.space2
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    text: integration.name
                    color: AdaptiveColor.glassText
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.textSmall
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    text: integration.detail
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
            Rectangle {
                visible: !integration.managed
                Layout.preferredWidth: 58
                Layout.preferredHeight: 24
                radius: 12
                color: Theme.surfaceContainerHigh
                Text {
                    anchors.centerIn: parent
                    text: "MANUAL"
                    color: AdaptiveColor.glassTextDim
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 8
                    font.weight: Font.Bold
                }
            }
            SettingsToggle {
                visible: integration.managed
                checked: integration.integrationEnabled
                available: integration.available
                onToggled: checked => integration.toggleRequested(checked)
            }
        }
    }
}
