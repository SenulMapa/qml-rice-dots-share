import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../components"
import "../core"
import "../services"

/**
 * DashboardSlim -- the control centre that opens from the pill (glass
 * redesign Phase 3, docs/superpowers/specs/2026-10-06-glass-redesign-
 * design.md). It sits inside the island blob, whose fill is now glass over
 * Hyprland's blur, so nothing here paints a panel background.
 *
 * Top to bottom:
 *   now playing  -- album art with a glow cast from its own colours, title/
 *                   artist, the lyric wheel, a thin seekable progress
 *                   capsule with times, glass transport (play is the one
 *                   activeFill disc)
 *   toggles      -- round GlassToggles with labels; right-click/long-press
 *                   opens the detail satellite where one exists
 *   sliders      -- volume and (if a controllable display exists)
 *                   brightness, thick capsules with a white fill
 *   footer       -- StatusOrb + time/date, Notes/Todo/Pet links, power
 *
 * No cards, no borders between groups: hierarchy is spacing and type.
 * Rows rise 8px and fade in, 30ms apart, each time the page opens.
 */
Item {
    id: root

    signal pageRequested(string page)
    signal satelliteRequested(string section)
    signal back()

    property real availableWidth: 400
    property real availableHeight: 400

    // Ink shared-element tags (island/SharedElements.qml): the dashboard's
    // now-playing art (52px) and title/artist. Only the "dashboard" state
    // counts, and only while there is media.
    SharePoint {
        id: shareArt
        objectName: "share:art"
        shareKind: "art"
        shareState: "dashboard"
        measure: artBox
        shareLive: MediaService.available
        shareRadius: 12
    }
    SharePoint {
        id: shareTitle
        objectName: "share:title"
        shareKind: "title"
        shareState: "dashboard"
        measure: dashTitleCol
        shareLive: MediaService.available
        shareScale: 15 / 20
        shareSubScale: 1
    }
    readonly property var shareItems: [shareArt, shareTitle]

    readonly property real dashWidth: Math.min(Theme.u(18), availableWidth - Theme.u(2))
    readonly property real dashHeight: Math.min(Theme.u(9), availableHeight)

    // Ink: the page's full content height, margins included. The island
    // sizes the dashboard body to this (island/IslandController.qml), so
    // nothing is clipped and the footer always fits. Glass keeps its fixed
    // dashHeight, so this is only read under ink.
    readonly property real contentHeight: contentColumn.implicitHeight
        + contentColumn.anchors.topMargin + contentColumn.anchors.bottomMargin

    readonly property color text: Config.appearance.ink ? Theme.t1 : AdaptiveColor.glassText
    readonly property color textDim: Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim
    // Ink toggles are 56px circles (showcase dashboard); glass keeps 64px.
    readonly property real toggleW: Config.appearance.ink ? 56 : 64

    // Lucide name for the current weather code (ink draws Icon, not a glyph).
    function weatherIcon(): string {
        const c = WeatherService.weatherCode;
        if (c === 0) return WeatherService.isDay ? "sun" : "moon";
        if (c >= 1 && c <= 3) return WeatherService.isDay ? "cloud-sun" : "cloud";
        if (c === 45 || c === 48) return "cloud-fog";
        if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return "cloud-rain";
        if ((c >= 71 && c <= 77) || (c >= 85 && c <= 86)) return "cloud-snow";
        if (c >= 95) return "cloud-lightning";
        return "cloud";
    }

    function fmt(sec) {
        if (!isFinite(sec) || sec < 0) sec = 0;
        const m = Math.floor(sec / 60), s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // Ink footer: "Up 3d 4h · <user>". Uptime is read from /proc/uptime and
    // re-read every 60s while the dashboard is visible.
    property real uptimeSeconds: 0
    readonly property string userName: Quickshell.env("USER") ?? ""
    function formatUptime(sec): string {
        const total = Math.max(0, Math.floor(sec))
        const d = Math.floor(total / 86400)
        const h = Math.floor((total % 86400) / 3600)
        const m = Math.floor((total % 3600) / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        printErrors: false
        onLoaded: root.uptimeSeconds = parseFloat(text().split(" ")[0]) || 0
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.visible && Config.appearance.ink
        triggeredOnStart: true
        onTriggered: uptimeFile.reload()
    }

    // Staggered entrance, replayed whenever the page becomes visible.
    property int _reveal: 0
    onVisibleChanged: if (visible) { _reveal = 0; revealTimer.restart(); }
    Component.onCompleted: revealTimer.restart()
    Timer {
        id: revealTimer
        interval: 30
        repeat: true
        onTriggered: { root._reveal += 1; if (root._reveal >= 4) stop(); }
    }
    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        anchors.leftMargin: Config.appearance.ink ? 40 : 26
        anchors.rightMargin: Config.appearance.ink ? 40 : 26
        anchors.topMargin: Config.appearance.ink ? 28 : 22
        anchors.bottomMargin: Config.appearance.ink ? 28 : 16
        spacing: Config.appearance.ink ? 24 : 16

        // ─── Header (ink): serif date, weather ─────────────────────────
        Item {
            id: inkHead
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            visible: Config.appearance.ink
            readonly property bool shown: root._reveal > 0
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            property date today: new Date()
            Timer {
                interval: 60000
                running: root.visible
                repeat: true
                onTriggered: inkHead.today = new Date()
            }

            Text {
                id: inkDate
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                text: Qt.formatDate(inkHead.today, "ddd d")
                font.family: Theme.fontSerif
                font.pixelSize: 64
                font.letterSpacing: -1.3
                color: root.text
            }
            // No weather: month over time, right-aligned, time on the date's baseline.
            Text {
                id: inkTime
                visible: !WeatherService.available
                anchors.right: parent.right
                anchors.baseline: inkDate.baseline
                text: Qt.formatTime(inkHead.today, "h:mm AP")
                font.family: Theme.fontUi
                font.pixelSize: 20
                font.weight: Font.DemiBold
                color: root.text
            }
            Text {
                visible: !WeatherService.available
                anchors.right: parent.right
                anchors.bottom: inkTime.top
                anchors.bottomMargin: 2
                text: Qt.formatDate(inkHead.today, "MMMM")
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
                color: Theme.t2
            }
            // Weather: a Lucide icon and the serif temperature.
            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 12
                visible: WeatherService.available
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.weatherIcon()
                    size: 22
                    color: root.textDim
                }
                Text {
                    text: WeatherService.temperatureLabel
                    font.family: Theme.fontSerif
                    font.pixelSize: 64
                    font.letterSpacing: -1.3
                    color: root.text
                }
            }
        }

        // ─── Now playing ───────────────────────────────────────────────
        Item {
            id: hero
            Layout.fillWidth: true
            Layout.fillHeight: !Config.appearance.ink
            Layout.minimumHeight: Config.appearance.ink ? 60 : 128
            Layout.preferredHeight: Config.appearance.ink ? 64 : -1
            readonly property int order: 0
            readonly property bool shown: root._reveal > order
            opacity: shown ? 1 : 0
            transform: Translate { y: hero.shown ? 0 : 8; Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            // Art + glow
            Item {
                id: artBox
                width: Config.appearance.ink ? 52 : 124; height: width
                anchors.verticalCenter: parent.verticalCenter
                visible: MediaService.available
                // Ink: SharedArt (island/SharedElements.qml) draws the art.
                opacity: Config.appearance.ink ? 0 : 1

                Image {
                    id: art
                    anchors.fill: parent
                    source: MediaService.artwork
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(256, 256)
                    asynchronous: true
                    visible: false
                }
                // Glow: the art itself, blurred and spread, so its colour is
                // always the album's own (never a theme accent).
                MultiEffect {
                    anchors.centerIn: parent
                    width: parent.width; height: parent.height
                    scale: 1.18
                    visible: !Config.appearance.ink
                    source: art
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 48
                    saturation: 0.3
                    opacity: art.status === Image.Ready ? (MediaService.playing ? 0.7 : 0.4) : 0
                    Behavior on opacity { NumberAnimation { duration: 400 } }
                }
                Rectangle {
                    id: artMask
                    anchors.fill: parent
                    radius: Config.appearance.ink ? 14 : 22
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: art
                    maskEnabled: true
                    maskSource: artMask
                    visible: art.status === Image.Ready
                    scale: MediaService.playing ? 1 : 0.94
                    Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                }
                // No artwork yet: a glass tile with a note.
                Item {
                    anchors.fill: parent
                    visible: art.status !== Image.Ready
                    GlassMaterial { anchors.fill: parent; radius: Config.appearance.ink ? 14 : 22; shadow: 0.06 }
                    Icon {
                        anchors.centerIn: parent
                        visible: Config.appearance.ink
                        name: "music"
                        size: 22
                        color: root.textDim
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !Config.appearance.ink
                        text: "music_note"
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: 44
                        color: root.textDim
                    }
                }
            }

            ColumnLayout {
                anchors.left: artBox.right
                anchors.leftMargin: 22
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 2
                visible: MediaService.available

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    ColumnLayout {
                        id: dashTitleCol
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            // Ink: SharedTitle draws the title and artist.
                            opacity: Config.appearance.ink ? 0 : 1
                            text: MediaService.title
                            elide: Text.ElideRight
                            font.family: Theme.fontDisplay
                            font.pixelSize: Config.appearance.ink ? 15 : 21
                            font.weight: Font.DemiBold
                            color: root.text
                        }
                        Text {
                            Layout.fillWidth: true
                            opacity: Config.appearance.ink ? 0 : 1
                            text: MediaService.artist
                            elide: Text.ElideRight
                            font.family: Theme.fontUi
                            font.pixelSize: Config.appearance.ink ? 13 : 14
                            font.weight: Font.Medium
                            color: root.textDim
                        }
                    }
                    // Ink: bare transport glyphs, and a 36px fillOn disc for play/pause.
                    Row {
                        visible: Config.appearance.ink
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 10
                        Item {
                            width: 28; height: 28
                            opacity: MediaService.canPrevious ? 1 : 0.4
                            Icon { anchors.centerIn: parent; name: "transport/prev"; size: 18; color: Theme.t1 }
                            MouseArea { anchors.fill: parent; enabled: MediaService.canPrevious; cursorShape: Qt.PointingHandCursor; onClicked: MediaService.previous() }
                        }
                        Item {
                            width: 36; height: 36
                            opacity: MediaService.canToggle ? 1 : 0.4
                            Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.fillOn }
                            Icon {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: MediaService.playing ? 0 : 1
                                name: MediaService.playing ? "transport/pause" : "transport/play"
                                size: 16
                                color: Theme.glyphOn
                            }
                            MouseArea { anchors.fill: parent; enabled: MediaService.canToggle; cursorShape: Qt.PointingHandCursor; onClicked: MediaService.togglePlaying() }
                        }
                        Item {
                            width: 28; height: 28
                            opacity: MediaService.canNext ? 1 : 0.4
                            Icon { anchors.centerIn: parent; name: "transport/next"; size: 18; color: Theme.t1 }
                            MouseArea { anchors.fill: parent; enabled: MediaService.canNext; cursorShape: Qt.PointingHandCursor; onClicked: MediaService.next() }
                        }
                    }
                    GlassIconButton {
                        visible: !Config.appearance.ink
                        icon: "skip_previous"; size: 36
                        available: MediaService.canPrevious
                        onClicked: MediaService.previous()
                    }
                    GlassIconButton {
                        visible: !Config.appearance.ink
                        icon: MediaService.playing ? "pause" : "play_arrow"; size: 46
                        prominent: true
                        available: MediaService.canToggle
                        onClicked: MediaService.togglePlaying()
                    }
                    GlassIconButton {
                        visible: !Config.appearance.ink
                        icon: "skip_next"; size: 36
                        available: MediaService.canNext
                        onClicked: MediaService.next()
                    }
                }

                Item {
                    id: freeSpace
                    // Ink drops lyrics and the album line: the showcase strip has no room for them.
                    visible: !Config.appearance.ink
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 18
                    LyricWheel {
                        anchors.fill: parent
                        visible: LyricsService.active
                        textColor: root.textDim
                        activeColor: root.text
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        visible: !LyricsService.active && MediaService.album.length > 0
                        elide: Text.ElideRight
                        text: MediaService.album
                        font.family: Theme.fontUi
                        font.pixelSize: 13
                        color: root.textDim
                    }
                }

                // Progress: thin capsule, white fill, knob on hover; times.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        Layout.preferredWidth: Config.appearance.ink ? 40 : implicitWidth
                        horizontalAlignment: Text.AlignLeft
                        text: root.fmt(MediaService.position)
                        font.family: Config.appearance.ink ? Theme.fontUi : Theme.fontData
                        font.pixelSize: Config.appearance.ink ? 12 : 11
                        color: Config.appearance.ink ? Theme.t3 : root.textDim
                    }
                    Item {
                        id: track
                        Layout.fillWidth: true
                        height: 18
                        readonly property bool hot: seekArea.containsMouse || seekArea.pressed
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: Config.appearance.ink ? 3 : (track.hot ? 7 : 5)
                            radius: height / 2
                            color: Qt.rgba(root.text.r, root.text.g, root.text.b, Config.appearance.ink ? 0.16 : 0.22)
                            Behavior on height { NumberAnimation { duration: 140 } }
                            Rectangle {
                                height: parent.height
                                width: Math.max(height, parent.width * MediaService.progress)
                                radius: height / 2
                                color: root.text
                            }
                        }
                        Rectangle {
                            width: Config.appearance.ink ? 10 : 14; height: width; radius: width / 2
                            color: Config.appearance.ink ? Theme.fillOn : "white"
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width * MediaService.progress - width / 2
                            opacity: track.hot ? 1 : 0
                            scale: track.hot ? 1 : 0.4
                            Behavior on opacity { NumberAnimation { duration: 140 } }
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: MediaService.canSeek
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => MediaService.seekTo(mouse.x / width)
                        }
                    }
                    Text {
                        Layout.preferredWidth: Config.appearance.ink ? 44 : implicitWidth
                        horizontalAlignment: Text.AlignRight
                        text: "-" + root.fmt(MediaService.duration - MediaService.position)
                        font.family: Config.appearance.ink ? Theme.fontUi : Theme.fontData
                        font.pixelSize: Config.appearance.ink ? 12 : 11
                        color: Config.appearance.ink ? Theme.t3 : root.textDim
                    }
                }
            }

            // Idle: one calm line, never a blank gap.
            Row {
                anchors.centerIn: parent
                spacing: 12
                visible: !MediaService.available
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "music_off"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 26
                    color: root.textDim
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Nothing playing"
                    font.family: Theme.fontUi
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    color: root.textDim
                }
            }
        }

        // ─── Toggles ───────────────────────────────────────────────────
        Item {
            id: toggles
            Layout.fillWidth: true
            Layout.preferredHeight: toggleRow.implicitHeight
            readonly property bool shown: root._reveal > 1
            opacity: shown ? 1 : 0
            transform: Translate { y: toggles.shown ? 0 : 8; Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            Row {
                id: toggleRow
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property int toggleCount: 7 + (Config.phone.enabled ? 1 : 0)
                spacing: Math.min(30, (toggles.width - toggleCount * root.toggleW) / (toggleCount - 1))

                GlassToggle {
                    width: root.toggleW
                    on: NetworkService.connected
                    icon: NetworkService.connectionType === "ethernet" ? "lan"
                        : NetworkService.connected ? "wifi" : "wifi_off"
                    iconName: NetworkService.connectionType === "ethernet" ? "ethernet-port"
                        : NetworkService.connected ? "wifi" : "wifi-off"
                    label: NetworkService.connectionType === "ethernet" ? "Ethernet" : "Wi-Fi"
                    onActivated: root.satelliteRequested("wifi")
                    onSecondary: root.satelliteRequested("wifi")
                }
                GlassToggle {
                    width: root.toggleW
                    on: BluetoothService.enabled
                    icon: BluetoothService.connected ? "bluetooth_connected"
                        : BluetoothService.enabled ? "bluetooth" : "bluetooth_disabled"
                    iconName: BluetoothService.connected ? "bluetooth-connected"
                        : BluetoothService.enabled ? "bluetooth" : "bluetooth-off"
                    label: "Bluetooth"
                    onActivated: root.satelliteRequested("bluetooth")
                    onSecondary: root.satelliteRequested("bluetooth")
                }
                GlassToggle {
                    width: root.toggleW
                    on: !AudioService.muted
                    icon: AudioService.muted ? "volume_off" : "volume_up"
                    iconName: AudioService.muted ? "volume-x" : "volume-2"
                    label: "Sound"
                    onActivated: AudioService.toggleMute()
                    onSecondary: root.satelliteRequested("audio")
                }
                GlassToggle {
                    width: root.toggleW
                    on: NightLightService.enabled
                    icon: "bedtime"
                    iconName: "moon"
                    label: "Night"
                    onActivated: NightLightService.toggle()
                }
                GlassToggle {
                    width: root.toggleW
                    on: IdleService.inhibited
                    icon: "coffee"
                    iconName: "coffee"
                    label: "Caffeine"
                    onActivated: IdleService.toggleInhibition()
                }
                GlassToggle {
                    width: root.toggleW
                    on: NotificationService.doNotDisturb
                    icon: NotificationService.doNotDisturb ? "notifications_off" : "notifications"
                    iconName: NotificationService.doNotDisturb ? "bell-off" : "bell"
                    label: "Focus"
                    onActivated: NotificationService.setDoNotDisturb(!NotificationService.doNotDisturb)
                }
                GlassToggle {
                    width: root.toggleW
                    on: Config.wallpaper.dither
                    icon: "blur_on"
                    iconName: "grid-3x3"
                    label: "Dither"
                    onActivated: SettingsStore.setWallpaperDither(!Config.wallpaper.dither)
                }
                // iPhone continuity: only exists while phone.enabled.
                GlassToggle {
                    visible: Config.phone.enabled
                    width: root.toggleW
                    on: PhoneService.connected
                    icon: "smartphone"
                    iconName: "smartphone"
                    label: "iPhone"
                    onActivated: root.satelliteRequested("phone")
                    onSecondary: root.satelliteRequested("phone")
                }
            }
        }

        // ─── Sliders ───────────────────────────────────────────────────
        // Ink stacks the two capsules, each with a serif percentage; glass
        // keeps them side by side (one column when brightness is absent).
        GridLayout {
            id: sliders
            Layout.fillWidth: true
            columns: Config.appearance.ink || !BrightnessService.available ? 1 : 2
            columnSpacing: 14
            rowSpacing: 14
            readonly property bool shown: root._reveal > 2
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            RowLayout {
                Layout.fillWidth: true
                spacing: Config.appearance.ink ? 16 : 20
                GlassSlider {
                    Layout.fillWidth: true
                    value: AudioService.volume
                    icon: AudioService.muted || AudioService.volume < 0.01 ? "volume_off"
                        : AudioService.volume < 0.5 ? "volume_down" : "volume_up"
                    iconName: AudioService.muted || AudioService.volume < 0.01 ? "volume-x"
                        : AudioService.volume < 0.5 ? "volume-1" : "volume-2"
                    onMoved: v => AudioService.setVolume(Math.round(v * 100))
                }
                Text {
                    visible: Config.appearance.ink
                    Layout.preferredWidth: 64
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(AudioService.volume * 100) + "%"
                    font.family: Theme.fontSerif
                    font.pixelSize: 28
                    font.letterSpacing: -0.5
                    color: root.text
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Config.appearance.ink ? 16 : 20
                visible: BrightnessService.available
                GlassSlider {
                    Layout.fillWidth: true
                    value: BrightnessService.level
                    icon: "light_mode"
                    iconName: "sun"
                    onMoved: v => BrightnessService.setBrightness(Math.max(1, Math.round(v * 100)))
                }
                Text {
                    visible: Config.appearance.ink
                    Layout.preferredWidth: 64
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(BrightnessService.level * 100) + "%"
                    font.family: Theme.fontSerif
                    font.pixelSize: 28
                    font.letterSpacing: -0.5
                    color: root.text
                }
            }
        }

        // ─── Footer ────────────────────────────────────────────────────
        RowLayout {
            id: footer
            Layout.fillWidth: true
            spacing: 12
            readonly property bool shown: root._reveal > 3
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

            StatusOrb {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                wifiStrength: ConnectivityStatus.wifiStrength
                ethernet: ConnectivityStatus.ethernet
                btEnabled: ConnectivityStatus.btEnabled
                btSignal: ConnectivityStatus.btSignal
                btDevices: ConnectivityStatus.btDevices
                batteryLevel: BatteryService.available ? BatteryService.percentage : -1
                charging: BatteryService.charging
            }
            Text {
                id: clock
                property date now: new Date()
                Timer { interval: 1000; running: root.visible; repeat: true; onTriggered: clock.now = new Date() }
                text: Qt.formatTime(now, "h:mm") + "  ·  " + now.toLocaleDateString(Qt.locale(), "ddd d MMM")
                font.family: Theme.fontUi
                font.pixelSize: 13
                font.weight: Font.Medium
                color: root.textDim
            }
            Text {
                visible: Config.appearance.ink
                text: "Up " + root.formatUptime(root.uptimeSeconds)
                    + (root.userName !== "" ? " · " + root.userName : "")
                color: Theme.t3
                font.family: Theme.fontUi
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            Item { Layout.fillWidth: true }

            Repeater {
                model: [
                    { icon: "description", label: "Notes", page: "notes" },
                    { icon: "checklist", label: "Todo", page: "todo" },
                    { icon: "pets", label: "Pet", page: "pet" }
                ]
                delegate: Item {
                    required property var modelData
                    implicitWidth: linkRow.implicitWidth + 16
                    implicitHeight: 32
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.rgba(root.text.r, root.text.g, root.text.b, linkArea.containsMouse ? 0.12 : 0)
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    Row {
                        id: linkRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.icon
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 18
                            color: linkArea.containsMouse ? root.text : root.textDim
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: linkArea.containsMouse ? root.text : root.textDim
                        }
                    }
                    MouseArea {
                        id: linkArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pageRequested(modelData.page)
                    }
                }
            }

            GlassIconButton {
                icon: "power_settings_new"
                size: 34
                onClicked: root.pageRequested("session")
            }
        }
    }
}
