import QtQuick
import Quickshell
import "../core"
import "../services"

/**
 * MacCcPanel -- the Control Center module grid (spec 3.4). There is no outer
 * panel: each module is its own glass shape on the wallpaper, on a 292 pt
 * grid. Positions and sizes come from MacTokens.
 *
 * Wiring (existing services only, nothing new):
 *   Wi-Fi          NetworkService (wifiEnabled, connectionName, toggleWifi)
 *   Bluetooth      BluetoothService (enabled, connected device, toggleEnabled)
 *   LocalSend      inert: no service behind it (AirDrop's Linux stand-in)
 *   Now Playing    MediaService (title, artwork, transport)
 *   Screen Mirror  inert: no shell hook opens the phone mirror yet; shows
 *                  PhoneService.airplayState
 *   Screenshot     the regionScreenshot action from core/ShellCompatShortcuts
 *   Keep awake     IdleService (inhibited, toggleInhibition)
 *   Night Light    NightLightService (enabled, toggle)
 *   Focus          NotificationService.doNotDisturb (toggleDoNotDisturb)
 *   Display        BrightnessService (level, setBrightness)
 *   Sound          AudioService (volume, setVolume)
 *
 * `dismissRequested()` asks the owning window to close after an action that
 * ends the session (Screenshot).
 */
Item {
    id: root

    signal dismissRequested()

    readonly property real colRight: MacTokens.s(MacTokens.ccGridWidth - MacTokens.ccTileWidth)
    readonly property real colPitch: MacTokens.s(MacTokens.ccColPitch)
    function rowY(n: int): real { return MacTokens.s(n * MacTokens.ccRowPitch) }

    width: MacTokens.s(MacTokens.ccGridWidth)
    height: MacTokens.s(MacTokens.ccEditY + MacTokens.ccEditHeight)

    // ---- row 0: Wi-Fi, Now Playing (rows 0 and 1) ------------------------
    MacCcTile {
        x: 0
        y: root.rowY(0)
        title: "Wi-Fi"
        subtitle: NetworkService.wifiEnabled ? NetworkService.connectionName : "Off"
        icon: "wifi"
        active: NetworkService.wifiEnabled
        available: NetworkService.available
        onActivated: NetworkService.toggleWifi()
    }

    MacCcNowPlaying {
        x: root.colRight
        y: root.rowY(0)
        title: MediaService.title
        artwork: MediaService.artwork
        playing: MediaService.playing
        available: MediaService.available
        canPrevious: MediaService.canPrevious
        canNext: MediaService.canNext
        onPreviousRequested: MediaService.previous()
        onToggleRequested: MediaService.togglePlaying()
        onNextRequested: MediaService.next()
    }

    // ---- row 1: Bluetooth ------------------------------------------------
    MacCcTile {
        x: 0
        y: root.rowY(1)
        title: "Bluetooth"
        subtitle: BluetoothService.connected ? BluetoothService.primaryDeviceName
            : (BluetoothService.enabled ? "On" : "Off")
        icon: BluetoothService.enabled ? "bluetooth-connected" : "bluetooth-off"
        active: BluetoothService.enabled
        available: BluetoothService.available
        onActivated: BluetoothService.toggleEnabled()
    }

    // ---- row 2: LocalSend (inert), Screen Mirroring (inert) ----------------
    MacCcTile {
        x: 0
        y: root.rowY(2)
        title: "LocalSend"
        icon: "smartphone"
        inert: true
    }

    MacCcToggle {
        x: root.colRight
        y: root.rowY(2) + (MacTokens.s(MacTokens.ccTileHeight) - height) / 2
        icon: "airplay"
        active: PhoneService.airplayState === "mirroring"
        available: true
        inert: true
    }

    // ---- row 2, right: Keep awake, beside the AirPlay toggle --------------
    // Reference (Tahoe 04) has a second round toggle here. It was an inert
    // Stage Manager stand-in. Keep awake replaces it: IdleService already owns
    // the flag (the island's Keep awake toggle reads the same one), and
    // toggleInhibition() stops the shell's dpms, lock and suspend timers.
    MacCcToggle {
        x: root.width - width
        y: root.rowY(2) + (MacTokens.s(MacTokens.ccTileHeight) - height) / 2
        icon: "coffee"
        active: IdleService.inhibited
        available: true
        onActivated: IdleService.toggleInhibition()
    }

    // ---- row 3: Night Light, Screenshot, Focus ----------------------------
    MacCcToggle {
        x: 0
        y: root.rowY(3) + (MacTokens.s(MacTokens.ccTileHeight) - height) / 2
        icon: "sunset"
        active: NightLightService.enabled
        available: NightLightService.available
        onActivated: NightLightService.toggle()
    }

    MacCcToggle {
        x: root.colPitch
        y: root.rowY(3) + (MacTokens.s(MacTokens.ccTileHeight) - height) / 2
        icon: "scan-line"
        available: true
        // Same command as the Region screenshot shortcut in core/ShellCompatShortcuts.qml.
        onActivated: {
            Quickshell.execDetached(["sh", "-c",
                "pidof slurp >/dev/null || hyprshot --freeze --clipboard-only --mode region --silent"])
            root.dismissRequested()
        }
    }

    MacCcTile {
        x: root.colRight
        y: root.rowY(3)
        title: "Focus"
        icon: "moon"
        active: NotificationService.doNotDisturb
        available: true
        onActivated: NotificationService.toggleDoNotDisturb()
    }

    // ---- rows 4 and 5: Display, Sound (full width) -------------------------
    MacCcSlider {
        x: 0
        y: root.rowY(4)
        title: "Display"
        leftIcon: "sun-dim"
        rightIcon: "sun"
        value: BrightnessService.level
        available: BrightnessService.available
        onMoved: v => BrightnessService.setBrightness(Math.round(v * 100))
    }

    MacCcSlider {
        x: 0
        y: root.rowY(5)
        title: "Sound"
        leftIcon: "volume-1"
        rightIcon: "volume-2"
        value: AudioService.volume
        available: AudioService.available
        onMoved: v => AudioService.setVolume(Math.round(v * 100))
    }

    // ---- Edit Controls: visual only --------------------------------------
    Rectangle {
        x: (root.width - width) / 2
        y: MacTokens.s(MacTokens.ccEditY)
        width: MacTokens.s(MacTokens.ccEditWidth)
        height: MacTokens.s(MacTokens.ccEditHeight)
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: MacTokens.ccEditBorder

        Text {
            anchors.centerIn: parent
            text: "Edit Controls"
            color: MacTokens.ccTitleColor
            font.family: MacTokens.textFamily
            font.pixelSize: MacTokens.s(MacTokens.ccEditTextSize)
        }
    }
}
