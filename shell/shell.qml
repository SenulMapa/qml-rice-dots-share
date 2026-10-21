//@ pragma Env QSG_RENDER_LOOP=threaded
// Qt picked the basic (GUI-thread) render loop here, so every frame waited on
// QML/JS work. Threaded keeps frame pacing even while bindings run -- measured
// to load cleanly on this machine (13 Sep 2026).
//@ pragma Env QSG_DISTANCEFIELD_ANTIALIASING=gray
// Distance-field text defaulted to subpixel AA on desktop GL, which is wrong
// on translucent layer-shell surfaces: pixel-dumped pill text showed blue
// (#002EC7) fringes on left glyph edges and orange (#F39700) on right edges
// even with fontconfig's rgba=none. Forcing grayscale AA here removed every
// fringe on relaunch.
import Quickshell
import Quickshell.Io
import QtQuick
import "applications"
import "core"
import "desktop"
import "desktop/deck"
import "dock"
import "desktop/services" as DeskServices
import "edge"
import "island"
import "lock"
import "missioncontrol"
import "mac"
import "services"
import "settings"
import "visualizer"
import "wallpaper"
import "wallpaper-switcher"
import "widgets"

ShellRoot {
    Component.onCompleted: {
        ShellState.start()
        ApplicationService.refresh()
        WallpaperService.refresh()
        // Read-only colour extraction from whatever wallpaper is already on
        // screen -- never renders/applies one, so this is safe to always run
        // (unlike WallpaperService.bootstrap below, which is not).
        PaletteAutoService.start()
        GlassBlurProfile.start()
        // Bootstrap the wallpaper renderer on launch (manageOnStartup default
        // true -- see core/Config.qml). This reconciles awww against the last
        // committed manifest/current-wallpaper in XDG_STATE_HOME, so the
        // wallpaper the user actually picked keeps showing on every output
        // after a restart instead of only being restored the next time the
        // picker is touched. bootstrap()/start_renderer() no-ops if a
        // matching-namespace awww-daemon (eg. one started earlier by
        // hyprland's execs.lua) is already up, so this never spawns a
        // duplicate daemon.
        if (Config.wallpaper.manageOnStartup)
            WallpaperService.bootstrap(false)
        // Register our lock/LockScreen.qml instance below with
        // services/LockService.qml so the `quickshell:lock` shortcut and
        // SessionService's lock path can engage it. LockScreen itself stays
        // inert (WlSessionLock.locked defaults false) until something
        // actually calls LockService.engage() -- instantiating it here does
        // NOT lock anything.
        LockService.registerLockScreen(lockScreen)
    }

    // Forces core/FrameProbe.qml (registered as the `MotionFrameProbe`
    // singleton -- see core/qmldir) to instantiate at startup so its
    // `frameprobe` IPC target (`qs ipc call frameprobe report`) exists from
    // boot, same as every other IPC-only singleton here. Nothing else in
    // the shell references it by name.
    property var _motionFrameProbeBoot: MotionFrameProbe

    Variants {
        model: Quickshell.screens

        Island {
            required property var modelData
            screen: modelData
        }
    }

    // macOS-style dock (dock/). One shared model, one layer surface per
    // screen (namespace qml-rice:dock). Gated by the `dock.enabled` setting,
    // default true; the island above is not involved.
    DockModel { id: dockData }

    Variants {
        model: SettingsStore.boolValue("dock", "enabled", true) ? Quickshell.screens : []

        Dock {
            required property var modelData
            screen: modelData
            dockModel: dockData
        }
    }

    // Dither-reveal wallpaper overlay (wallpaper/DitherWallpaper.qml) -- one
    // Background-layer surface per screen, behind all other windows. Gated on
    // the wallpaper.dither setting, off by default. Also disabled for animated
    // wallpapers (videos/GIFs) since the opaque background-layer dither surface
    // would cover the gslapper/mpvpaper video and burn GPU.
    Variants {
        model: SettingsStore.boolValue("wallpaper", "dither", false) && !WallpaperService.currentIsAnimated ? Quickshell.screens : []

        DitherWallpaper {
            // modelData already required/declared inside
            // wallpaper/DitherWallpaper.qml itself -- redeclaring it here
            // only shadowed it (qmllint: property-override).
            screen: modelData
        }
    }

    // impasto-ported desktop widgets (desktop/*) -- one bottom-layer surface
    // per screen, wallpaper-side of every window. Replaces the Pixel-style
    // WidgetLayer below by default; see desktop/services/DeskSettings.qml's
    // `enabled` (settings.json "desktopEnabled") to fall back to the old
    // layer without a rebuild. The two are mutually exclusive -- both bind
    // the same screen-bottom real estate and both claim right-click on the
    // wallpaper, so running them together would fight over input.
    Variants {
        model: DeskServices.DeskSettings.enabled ? Quickshell.screens : []

        Desktop {
            required property var modelData
            screen: modelData
        }
    }

    // The notes edge deck (desktop/deck/Deck.qml) -- a second per-screen
    // surface above Desktop's, since it needs to float to WlrLayer.Overlay
    // while arranging (Desktop only goes as high as Top). Gated the same as
    // Desktop above; the deck has nothing to draw with it off.
    Variants {
        model: DeskServices.DeskSettings.enabled ? Quickshell.screens : []

        Deck {
            required property var modelData
            screen: modelData
        }
    }

    // Tahoe ("mac") presentation (mac/). Loaded only while uiStyle is "mac",
    // so pill mode never instantiates it. Switching is live: the Loader comes
    // and goes with the setting. IslandController routes the toast, NC,
    // launcher and ringing call here (see its macRoute / syncPhoneCall guards).
    // MacPresence keeps it mounted for the 220 ms fade-out after a switch back.
    Loader {
        active: MacPresence.mounted
        sourceComponent: MacStyleRoot { }
    }

    // Pixel-style desktop widgets (widgets/*) -- kept, not deleted, as the
    // fallback when desktop/ is gated off above. See services/WidgetStore.qml
    // for the persisted layout/edit-mode API.
    Variants {
        model: DeskServices.DeskSettings.enabled ? [] : Quickshell.screens

        WidgetLayer {
            required property var modelData
            screen: modelData
        }
    }

    // Bottom-edge cava visualizer (visualizer/EdgeVisualizer.qml) -- one per
    // screen, always instantiated; the component itself decides visibility
    // (nothing playing / fullscreen / setting off) and fades accordingly,
    // same "always present, self-gating" shape as Island above.
    Variants {
        model: Quickshell.screens

        EdgeVisualizer {
            required property var modelData
            screen: modelData
        }
    }

    // Edge-scroll volume (edge/VolumeEdgeStrip.qml) -- one instance per
    // OUTER screen edge, not per screen: core/EdgeGeometry.instancesFor
    // flattens Quickshell.screens into {screen, edge} pairs, skipping any
    // edge that's actually shared with an adjacent monitor (the inner
    // boundary the cursor crosses between them never gets a strip).
    Variants {
        model: Config.volumeEdge.enabled
            ? EdgeGeometry.instancesFor(Quickshell.screens) : []

        VolumeEdgeStrip {
            required property var modelData
            screen: modelData.screen
            dockEdge: modelData.edge
        }
    }

    // "Workspace N" launcher-open OSD (island/WorkspaceToast.qml) -- one per
    // screen, additive alongside the Island/WidgetLayer Variants above; each
    // instance only actually presents on the monitor
    // ShellActions.launcherOpened names.
    Variants {
        model: Quickshell.screens

        WorkspaceToast {
            required property var modelData
            screen: modelData
        }
    }

    // Quick wallpaper switcher overlay (wallpaper-switcher/WallpaperSwitcher.qml)
    // -- one per screen, opens on focused monitor when Super+W is pressed.
    // Lightweight overlay with horizontal thumbnail strip at bottom-center.
    property var wallpaperSwitchers: ({})

    // HyprlandMonitor (Hyprland.focusedMonitor) has no `.screen` -- only
    // id/name/geometry (see quickshell-hyprland-ipc.qmltypes). Each
    // WallpaperSwitcher instance already resolves its own Hyprland monitor
    // via `Hyprland.monitorFor(screen)` (same pattern island/Island.qml uses
    // for `monitor`/`presentationTarget`), so the focused instance is found
    // by matching monitor ids across the per-screen switchers, not by
    // deriving a screen from the monitor.
    function focusedWallpaperSwitcher(): var {
        const focusedMonitor = HyprlandService.focusedMonitor
        if (!focusedMonitor)
            return null
        const switchers = Object.values(wallpaperSwitchers)
        return switchers.find(candidate =>
            candidate.monitor && candidate.monitor.id === focusedMonitor.id) || null
    }
    Variants {
        model: Quickshell.screens

        WallpaperSwitcher {
            id: wallpaperSwitcherInstance
            required property var modelData
            screen: modelData
            Component.onCompleted: {
                wallpaperSwitchers[screen] = this
            }
        }
    }

    // Mission Control (quickshell:missionControlToggle). One state object; one
    // window per screen, and only the focused-at-open monitor's window shows.
    // Available in every uiStyle: it is a standalone overlay, not a mac surface.
    MissionControl { id: missionControl }
    Variants {
        model: Quickshell.screens

        MissionControlWindow {
            required property var modelData
            owner: missionControl
        }
    }

    // Global (not per-screen -- Hyprland shortcuts have no monitor concept)
    // compatibility shim for end4-pC's `quickshell:*` binds. See its own
    // header comment for the gating rules and QMLRICE_COMPAT_SHORTCUTS.
    ShellCompatShortcuts { }

    // One WlSessionLock plus one lock/LockSurface.qml per screen (Quickshell
    // instantiates lockSurfaceComponent per output automatically). Inactive
    // until services/LockService.qml calls lockScreen.lock() -- see above.
    LockScreen {
        id: lockScreen
    }

    // New Settings window (settings/) -- a separate floating xdg-shell
    // toplevel with sidebar sections for all major settings categories.
    // One instance, global like LockScreen above (a window isn't a per-screen
    // surface). Inert (visible defaults false) until `settings open`/`toggle`
    // is called via IPC.
    SettingsWindow {
        id: settingsWindow
    }

    // IPC target for the settings window. Wired to existing Hyprland binds
    // that reference settings (e.g., qr("settings open")).
    IpcHandler {
        target: "settings"

        function open(): string {
            settingsWindow.visible = true
            return "SETTINGS_OPEN_SUCCESS"
        }

        function toggle(): string {
            settingsWindow.visible = !settingsWindow.visible
            return "SETTINGS_TOGGLE_SUCCESS"
        }

        function close(): string {
            settingsWindow.visible = false
            return "SETTINGS_CLOSE_SUCCESS"
        }

        // install.sh binds SUPER+SHIFT+W to `qr("settings wallpaper")` --
        // the wallpaper picker/dither toggle now lives inside the
        // "appearance" sidebar section (spec section 5), not its own
        // window, so this opens the window straight to that section
        // instead of leaving the keybind pointing at nothing.
        function wallpaper(): string {
            settingsWindow.currentSection = "appearance"
            settingsWindow.visible = true
            return "SETTINGS_WALLPAPER_OPEN_SUCCESS"
        }

        // Section aliases matching settings/SettingsWindow.qml's own
        // sidebar ids -- "island" kept as the old friendly name for what
        // is now the "pill" section.
        function island(): string {
            settingsWindow.currentSection = "pill"
            settingsWindow.visible = true
            return "SETTINGS_ISLAND_OPEN_SUCCESS"
        }
        function pill(): string {
            settingsWindow.currentSection = "pill"
            settingsWindow.visible = true
            return "SETTINGS_PILL_OPEN_SUCCESS"
        }
        function motion(): string {
            settingsWindow.currentSection = "motion"
            settingsWindow.visible = true
            return "SETTINGS_MOTION_OPEN_SUCCESS"
        }
        function desktop(): string {
            settingsWindow.currentSection = "desktop"
            settingsWindow.visible = true
            return "SETTINGS_DESKTOP_OPEN_SUCCESS"
        }
        function audio(): string {
            settingsWindow.currentSection = "audio"
            settingsWindow.visible = true
            return "SETTINGS_AUDIO_OPEN_SUCCESS"
        }
        function network(): string {
            settingsWindow.currentSection = "network"
            settingsWindow.visible = true
            return "SETTINGS_NETWORK_OPEN_SUCCESS"
        }
    }

    // IPC handler for dither wallpaper toggle
    IpcHandler {
        target: "dither"

        function toggle(): string {
            const currentState = SettingsStore.boolValue("wallpaper", "dither", false)
            SettingsStore.setWallpaperDither(!currentState)
            return "DITHER_TOGGLE_SUCCESS"
        }
    }

    // IPC handler for quick wallpaper switcher overlay
    IpcHandler {
        target: "wallswitch"

        function toggle(): string {
            const switcher = focusedWallpaperSwitcher()
            if (!switcher)
                return "WALLSWITCH_TOGGLE_FAILED"
            if (switcher.isOpen)
                switcher.close()
            else
                switcher.open()
            return "WALLSWITCH_TOGGLE_SUCCESS"
        }

        function open(): string {
            const switcher = focusedWallpaperSwitcher()
            if (!switcher)
                return "WALLSWITCH_OPEN_FAILED"
            switcher.open()
            return "WALLSWITCH_OPEN_SUCCESS"
        }

        function close(): string {
            const switcher = focusedWallpaperSwitcher()
            if (!switcher)
                return "WALLSWITCH_CLOSE_FAILED"
            switcher.close()
            return "WALLSWITCH_CLOSE_SUCCESS"
        }
    }
}
