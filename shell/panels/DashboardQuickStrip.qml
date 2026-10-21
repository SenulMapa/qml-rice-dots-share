import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../components"
import "../core"
import "../services"

RowLayout {
    id: root

    signal pageRequested(string page)
    // Network/Bluetooth/Audio no longer navigate to the deprecated Control
    // Center page -- they open the matching satellite beside the island
    // instead (island/IslandExpanded.qml owns that state now). See
    // HANDOVER.md.
    signal satelliteRequested(string section)
    spacing: Theme.space2
    // Each item is its own reveal step, starting after the hero row's 3
    // and the media/system zones' 2 (see panels/Dashboard.qml) -- capped
    // at 8 steps total by components/Reveal.qml itself, so a 6-item strip
    // starting at 5 just means its last couple of items share the max
    // stagger delay with the ones before them.
    property int revealToken: 0
    property bool revealExiting: false
    readonly property int revealOrderBase: 5

    readonly property var statuses: [
        { label: "Audio", value: AudioService.available
                ? (AudioService.muted ? "Muted" : AudioService.volumePercent + "%")
                : "Unavailable", icon: AudioService.muted ? "󰝟" : "󰕾",
            accent: AudioService.muted ? Theme.error : AdaptiveColor.activeFill,
            action: "satellite", section: "audio", available: true },
        { label: "Network", value: NetworkService.available
                ? NetworkService.connectionName : "Unavailable",
            icon: NetworkService.icon,
            accent: NetworkService.connected ? AdaptiveColor.activeFill : Theme.error,
            action: "satellite", section: "wifi", available: true },
        { label: "Bluetooth", value: BluetoothService.statusLabel,
            icon: BluetoothService.icon,
            accent: BluetoothService.connected ? AdaptiveColor.activeFill
                : AdaptiveColor.glassTextDim,
            action: "satellite", section: "bluetooth", available: BluetoothService.available },
        { label: "iPhone", value: PhoneService.connected ? "Connected" : "Not connected",
            icon: "󰄜", accent: PhoneService.connected ? AdaptiveColor.activeFill
                : AdaptiveColor.glassTextDim,
            action: "satellite", section: "phone", available: Config.phone.enabled },
        { label: "Focus", value: NotificationService.doNotDisturb ? "DND on" : "DND off",
            icon: NotificationService.doNotDisturb ? "󰂛" : "󰂚",
            accent: NotificationService.doNotDisturb ? Theme.tertiary : AdaptiveColor.activeFill,
            action: "dnd", available: true },
        { label: "Power", value: PowerProfileService.profileName,
            icon: PowerProfileService.icon,
            accent: PowerProfileService.profileId === "performance"
                ? Theme.warning : Theme.success,
            action: "power", available: PowerProfileService.available },
        { label: "Wallpaper", value: WallpaperService.currentName,
            icon: "󰸉", accent: Theme.tertiary,
            action: "page", page: "wallpaper", available: true },
        // The dashboard's only entry point into panels/SettingsPage.qml --
        // fonts, accent, corner roundness, performance tier, etc. all live
        // there but were previously only reachable via a keybind
        // (core/ShellActions.qml's settingsOpenRequested IPC target).
        { label: "Settings", value: "Theme & fonts",
            icon: "󰒓", accent: AdaptiveColor.activeFill,
            action: "page", page: "settings", available: true }
    ]

    Repeater {
        model: root.statuses
        delegate: Item {
            id: quickDelegate
            required property var modelData
            required property int index
            visible: modelData.available
            Layout.fillWidth: true
            Layout.fillHeight: true

        Reveal {
            anchors.fill: parent
            token: root.revealToken
            exiting: root.revealExiting
            order: root.revealOrderBase + quickDelegate.index

        Rectangle {
            id: quickTile
            anchors.fill: parent
            radius: Theme.radiusMedium
            // De-bento: transparent at rest, a faint hover wash only.
            // Content is inset by Theme.space3 on both edges -- the same
            // inset every other dashboard zone uses -- so the first item's
            // icon lines up with the date block and album art above it.
            color: quickHover.hovered
                ? Qt.alpha(AdaptiveColor.glassText, 0.05)
                : "transparent"
            border.width: 0

            // Hover-lift + press-scale micro-interaction -- springs, not
            // duration clips, so a fast hover-in/hover-out or a tap that
            // lands mid-lift retargets instead of restarting.
            scale: pressSpring.value
            transform: Translate { y: -liftSpring.value }
            MotionValue {
                id: liftSpring
                unit: "px"
                omega: Motion.omegaEnter
                zeta: Motion.zetaEnter
                target: quickHover.hovered ? 2 : 0
            }
            MotionValue {
                id: pressSpring
                unit: "ratio"
                omega: Motion.omegaEnter
                zeta: 0.55
                target: quickTap.pressed ? 0.96 : (quickHover.hovered ? 1.015 : 1)
            }

            GridLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space3
                columns: 2
                rows: 2
                columnSpacing: Theme.space1
                rowSpacing: 0
                Text {
                    Layout.rowSpan: 1
                    Layout.alignment: Qt.AlignVCenter
                    text: modelData.icon
                    color: modelData.accent
                    font.family: Config.appearance.monoFontFamily
                    font.pixelSize: 15
                }
                Text {
                    Layout.fillWidth: true
                    text: modelData.label
                    color: AdaptiveColor.glassText
                    elide: Text.ElideRight
                    font.family: Config.appearance.fontFamily
                    // Caption floor, not dashLabel -- this row's per-item
                    // text column measures ~67px wide (7 icons across the
                    // 789px strip), too tight for the 16px label size used
                    // elsewhere on the dashboard without eliding real
                    // labels like "Bluetooth"/"Wallpaper". Verified against
                    // render-dashboard.qml's parentAvailWidth log.
                    font.pixelSize: Theme.dashMicro
                    font.weight: Font.DemiBold
                }
                Item {
                    Layout.preferredWidth: 15
                    Layout.preferredHeight: 1
                }
                Text {
                    Layout.fillWidth: true
                    text: modelData.value
                    color: AdaptiveColor.glassTextDim
                    elide: Text.ElideRight
                    font.family: Config.appearance.fontFamily
                    font.pixelSize: Theme.dashMicro
                }
            }

            HoverHandler { id: quickHover }
            TapHandler {
                id: quickTap
                onTapped: {
                    // Focus and Power act in place -- no page/satellite nav.
                    // Volume/DND/power profile are never toggled in tests.
                    if (modelData.action === "satellite")
                        root.satelliteRequested(modelData.section)
                    else if (modelData.action === "dnd")
                        NotificationService.toggleDoNotDisturb()
                    else if (modelData.action === "power")
                        PowerProfileService.cycleProfile()
                    else
                        root.pageRequested(modelData.page)
                }
            }
            Behavior on color { ColorAnimation { duration: Animations.fast } }
        }
        }
        }
    }

    // ---- Compact tray row ----
    // Control Center (the only place tray icons used to live) is
    // deprecated -- see HANDOVER.md. A compact row here keeps tray access
    // reachable from the dashboard; menus still open in the right
    // satellite via island/Island.qml's TraySatellitePanel. Never tapped
    // in tests -- activating a real tray entry changes real app state.
    RowLayout {
        id: trayRow
        visible: SystemTray.items.values.length > 0
        Layout.alignment: Qt.AlignVCenter
        spacing: Theme.space1

        Repeater {
            model: SystemTray.items.values
            delegate: Item {
                required property var modelData
                width: Theme.space5
                height: Theme.space5

                IconImage {
                    anchors.fill: parent
                    anchors.margins: 2
                    source: modelData.icon
                    asynchronous: true
                }

                HoverHandler { id: trayItemHover }
                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onTapped: root.satelliteRequested("tray:" + modelData.id)
                }

                Squircle {
                    anchors.fill: parent
                    radius: Theme.radiusSmall
                    z: -1
                    color: trayItemHover.hovered
                        ? Qt.alpha(AdaptiveColor.glassText, 0.08) : "transparent"
                }
            }
        }
    }
}
