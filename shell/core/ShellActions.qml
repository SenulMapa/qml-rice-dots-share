pragma Singleton
import QtQuick
import Quickshell.Io
import "../services"

QtObject {
    id: root

    signal launcherToggleRequested()
    signal launcherOpenRequested()
    signal launcherCloseRequested()
    // Fired by island/Island.qml exactly when the launcher page actually
    // BECOMES the active expanded page (never on close, never on a toggle
    // that closed it) -- island/WorkspaceToast.qml's per-screen instances use
    // this, plus the monitor it opened on, to show the "Workspace N" OSD only
    // where the launcher itself just appeared.
    signal launcherOpened(var monitor)
    signal commandLauncherToggleRequested()
    signal commandLauncherOpenRequested()
    signal commandLauncherCloseRequested()
    // The impasto settings WINDOW (settings-impasto/SettingsWindow.qml,
    // instantiated in shell.qml). Raised from inside the island -- the
    // dashboard's own settings door used to open the island's legacy
    // settings page instead, which then outlived the island: dismissing the
    // pill left that page loaded behind it.
    signal impastoSettingsRequested()
    signal controlCenterToggleRequested()
    signal controlCenterOpenRequested()
    signal controlCenterCloseRequested()
    signal controlCenterSectionRequested(string section)
    signal clipboardToggleRequested()
    signal clipboardOpenRequested()
    signal clipboardCloseRequested()
    signal notificationsToggleRequested()
    signal notificationsOpenRequested()
    signal notificationsCloseRequested()
    signal sessionOpenRequested()
    signal sessionCloseRequested()
    signal settingsOpenRequested(string section)
    signal settingsCloseRequested()
    signal insightOpenRequested(string page)
    // Generic open/dismiss toggle for any island page, for callers (right now
    // just core/ShellCompatShortcuts.qml) that only need togglePage()
    // semantics and don't warrant their own dedicated *ToggleRequested pair.
    signal pageToggleRequested(string page)
    // Mission Control (missioncontrol/MissionControl.qml): the global shortcut
    // quickshell:missionControlToggle, fired from core/ShellCompatShortcuts.qml.
    signal missionControlToggleRequested()
    // Direct navigation (not toggle) for the dashboard/subpage family --
    // `qs ipc call island page <overview|notes|todo|pet>` (also accepts
    // "dashboard" as an alias for "overview"). Always OPENS to that exact
    // page regardless of current state, for scripted forward/back testing
    // of the dashboard<->subpage morph (island/IslandExpanded.qml's own
    // Notes/Todo/Pet `onBack` already goes back to "overview" the same
    // way). A toggle here would be unusable for that: re-sending the same
    // page while already on it would close the island instead of no-op'ing.
    signal islandPageRequested(string page)
    // Shows the volume OSD without changing the level -- see
    // core/ShellCompatShortcuts.qml's osdVolumeTrigger.
    signal osdVolumeTriggerRequested()
    // Alt+Tab app switcher (island/IslandController.qml's switcher state).
    // Routed to the primary island only, like every other island request.
    signal switcherNextRequested()
    signal switcherPrevRequested()
    signal switcherCommitRequested()
    signal switcherCancelRequested()
    // Mac style routing (IslandController.macRoute). Emitted instead of
    // opening the pill's "notifications" or "launcher" page while
    // Config.appearance.uiStyle is "mac". action is "open", "close" or
    // "toggle". Consumed by mac/MacStyleRoot.qml.
    signal macSurfaceRequested(string surface, string action)
    // Quick Look (mac/MacQuickLook.qml). action is "toggle", "show" or
    // "close"; path is absolute. Driven by tools/quicklook/quicklook.
    signal quickLookRequested(string action, string path)

    // `qml-rice ipc quicklook toggle <path>` (also show, close). Only the mac
    // presentation consumes it; in pill mode the call is accepted and ignored.
    property IpcHandler quickLookIpc: IpcHandler {
        target: "quicklook"

        function toggle(path: string): string {
            root.quickLookRequested("toggle", path)
            return "QUICKLOOK_TOGGLE_SUCCESS"
        }

        function show(path: string): string {
            root.quickLookRequested("show", path)
            return "QUICKLOOK_SHOW_SUCCESS"
        }

        function close(): string {
            root.quickLookRequested("close", "")
            return "QUICKLOOK_CLOSE_SUCCESS"
        }
    }

    property IpcHandler launcherIpc: IpcHandler {
        target: "launcher"

        function toggle(): string {
            root.launcherToggleRequested()
            return "LAUNCHER_TOGGLE_SUCCESS"
        }

        function open(): string {
            root.launcherOpenRequested()
            return "LAUNCHER_OPEN_SUCCESS"
        }

        function close(): string {
            root.launcherCloseRequested()
            return "LAUNCHER_CLOSE_SUCCESS"
        }
    }

    // Keybinds (hypr/hyprland/keybinds.lua and the installer templates):
    // Super+H hides the focused app; Super+` cycles its windows (RunningApps).
    signal appsHideFocusedRequested()
    signal appsCycleRequested()

    // ALT+Tab -> next, ALT+Shift+Tab -> prev, ALT release -> commit (a no-op
    // unless the switcher is open), ALT+Escape -> cancel.
    property IpcHandler switcherIpc: IpcHandler {
        target: "switcher"

        function next(): string {
            root.switcherNextRequested()
            return "SWITCHER_NEXT_SUCCESS"
        }

        function prev(): string {
            root.switcherPrevRequested()
            return "SWITCHER_PREV_SUCCESS"
        }

        function commit(): string {
            root.switcherCommitRequested()
            return "SWITCHER_COMMIT_SUCCESS"
        }

        function cancel(): string {
            root.switcherCancelRequested()
            return "SWITCHER_CANCEL_SUCCESS"
        }
    }

    // `qml-rice ipc apps hide-focused` / `apps cycle`; wired in ShellCompatShortcuts.
    property IpcHandler appsIpc: IpcHandler {
        target: "apps"

        function hideFocused(): string {
            root.appsHideFocusedRequested()
            return "APPS_HIDE_FOCUSED_SUCCESS"
        }

        function cycle(): string {
            root.appsCycleRequested()
            return "APPS_CYCLE_SUCCESS"
        }
    }

    property IpcHandler commandLauncherIpc: IpcHandler {
        target: "command-launcher"

        function toggle(): string {
            root.commandLauncherToggleRequested()
            return "COMMAND_LAUNCHER_TOGGLE_SUCCESS"
        }

        function open(): string {
            root.commandLauncherOpenRequested()
            return "COMMAND_LAUNCHER_OPEN_SUCCESS"
        }

        function close(): string {
            root.commandLauncherCloseRequested()
            return "COMMAND_LAUNCHER_CLOSE_SUCCESS"
        }
    }

    property IpcHandler controlCenterIpc: IpcHandler {
        target: "control-center"

        function toggle(): string {
            root.controlCenterToggleRequested()
            return "CONTROL_CENTER_TOGGLE_SUCCESS"
        }

        function open(): string {
            root.controlCenterOpenRequested()
            return "CONTROL_CENTER_OPEN_SUCCESS"
        }

        function close(): string {
            root.controlCenterCloseRequested()
            return "CONTROL_CENTER_CLOSE_SUCCESS"
        }

        // Testability hook for the Wi-Fi/Bluetooth/Audio satellites: opens
        // the control centre if needed, then toggles the named section, so a
        // verification script can drive each satellite without simulating
        // a tile tap.
        function section(name: string): string {
            const valid = ["wifi", "bluetooth", "audio", "energy", "phone"]
            if (valid.indexOf(name) === -1)
                return "CONTROL_CENTER_SECTION_FAILURE"
            root.controlCenterSectionRequested(name)
            return "CONTROL_CENTER_SECTION_SUCCESS"
        }
    }

    property IpcHandler clipboardIpc: IpcHandler {
        target: "clipboard"

        function toggle(): string {
            root.clipboardToggleRequested()
            return "CLIPBOARD_TOGGLE_SUCCESS"
        }

        function open(): string {
            root.clipboardOpenRequested()
            return "CLIPBOARD_OPEN_SUCCESS"
        }

        function close(): string {
            root.clipboardCloseRequested()
            return "CLIPBOARD_CLOSE_SUCCESS"
        }
    }

    property IpcHandler notificationsIpc: IpcHandler {
        target: "notifications"

        function toggle(): string {
            root.notificationsToggleRequested()
            return "NOTIFICATIONS_TOGGLE_SUCCESS"
        }

        function open(): string {
            root.notificationsOpenRequested()
            return "NOTIFICATIONS_OPEN_SUCCESS"
        }

        function close(): string {
            root.notificationsCloseRequested()
            return "NOTIFICATIONS_CLOSE_SUCCESS"
        }
    }

    property IpcHandler sessionPageIpc: IpcHandler {
        target: "session-page"

        function open(): string {
            root.sessionOpenRequested()
            return "SESSION_PAGE_OPEN_SUCCESS"
        }

        function close(): string {
            root.sessionCloseRequested()
            return "SESSION_PAGE_CLOSE_SUCCESS"
        }
    }

    // IPC TARGET RENAMED from "settings" to "island-settings": settings/
    // SettingsWindow.qml (shell.qml, settings-v2) now owns the "settings"
    // target for the real, standalone settings window (spec section 5)
    // -- two IpcHandlers registering the same target name is a real
    // runtime collision, only one wins. This handler opens the island's
    // OWN legacy internal settings page (panels/SettingsPage.qml, still
    // reachable via island/IslandExpanded.qml's settingsOpen) -- kept
    // working under its own name rather than deleted, since replacing it
    // island-side wasn't in scope for this pass.
    property IpcHandler settingsPageIpc: IpcHandler {
        target: "island-settings"

        function open(): string {
            root.settingsOpenRequested("appearance")
            return "SETTINGS_OPEN_SUCCESS"
        }

        function island(): string {
            root.settingsOpenRequested("island")
            return "SETTINGS_ISLAND_OPEN_SUCCESS"
        }

        function idle(): string {
            root.settingsOpenRequested("idle")
            return "SETTINGS_IDLE_OPEN_SUCCESS"
        }

        function displays(): string {
            root.settingsOpenRequested("displays")
            return "SETTINGS_DISPLAYS_OPEN_SUCCESS"
        }

        function notifications(): string {
            root.settingsOpenRequested("notifications")
            return "SETTINGS_NOTIFICATIONS_OPEN_SUCCESS"
        }

        function media(): string {
            root.settingsOpenRequested("media")
            return "SETTINGS_MEDIA_OPEN_SUCCESS"
        }

        function wallpaper(): string {
            root.settingsOpenRequested("wallpaper")
            return "SETTINGS_WALLPAPER_OPEN_SUCCESS"
        }

        function dashboard(): string {
            root.settingsOpenRequested("dashboard")
            return "SETTINGS_DASHBOARD_OPEN_SUCCESS"
        }

        function close(): string {
            root.settingsCloseRequested()
            return "SETTINGS_CLOSE_SUCCESS"
        }
    }

    // impasto card pages (DeskSettings.islandImpastoCards). `card(name)`
    // IMPASTO REMOVED (docs/superpowers/specs/2026-09-23-blob-rebuild-
    // design.md section 1 "Removed"): this used to open one of impasto's 13
    // module detail cards (island/cards/*.qml, deleted) as its own island
    // state. Every impasto card name now opens the dashboard ("overview")
    // instead -- `island card <name>` stays a working, named IPC call
    // rather than silently landing on a blank page, but the per-module
    // detail view itself is gone until phase C's dashboard rebuild lands.
    // "wifi"/"bluetooth" also land on the dashboard here rather than
    // opening their satellite directly -- IPC section 3 of the spec
    // (`island satellite wifi|bluetooth|audio`) is a later phase's job, not
    // this pass's; the dashboard's own quick-strip glyphs still open them.
    // Friendly name -> page id for `island card <name>`. Kept outside the
    // IpcHandler: IPC targets cannot expose var properties.
    readonly property var islandCardPages: ({
        "weather": "overview",
        "calendar": "overview",
        "player": "overview",
        "media": "overview",
        "system": "overview",
        "processor": "overview",
        "memory": "overview",
        "battery": "overview",
        "wifi": "overview",
        "wi-fi": "overview",
        "bluetooth": "overview",
        "claude": "overview",
        "recorder": "overview",
        "pet": "overview",
        "volume": "overview",
        "timer": "overview",
        "github": "overview",
        "tasks": "overview",
        "notes": "overview",
        "board": "overview",
        "session-impasto": "session",
        "session2": "session",
        "keys": "overview",
        "shortcuts": "overview",
        "packages": "overview",
        "updates": "overview",
        "stats-full": "overview",
        "stats2": "overview",
        "overview": "overview",
        "dashboard": "overview"
    })

    property IpcHandler islandCardIpc: IpcHandler {
        target: "island"

        function card(name: string): string {
            const page = root.islandCardPages[(name || "").toLowerCase()]
            if (!page)
                return "ISLAND_CARD_UNSUPPORTED"
            root.pageToggleRequested(page)
            return "ISLAND_CARD_SUCCESS"
        }

        // `island satellite wifi|bluetooth|audio` -- opens the dashboard
        // (if needed) and the named satellite, same pipeline
        // controlCenterIpc's `section()` already uses (kept for back-compat/
        // testability under its older "control-center" target name).
        function satellite(name: string): string {
            const valid = ["wifi", "bluetooth", "audio", "energy", "phone"]
            const normalized = (name || "").toLowerCase()
            if (valid.indexOf(normalized) === -1)
                return "ISLAND_SATELLITE_UNSUPPORTED"
            root.controlCenterSectionRequested(normalized)
            return "ISLAND_SATELLITE_SUCCESS"
        }

        // `island page overview|notes|todo|pet|dashboard` -- direct
        // navigation (not toggle) for scripted dashboard<->subpage testing.
        // "dashboard" is accepted as an alias for "overview" since that's
        // the name the owner/tests know it by; the controller itself only
        // ever uses "overview" (see island/IslandController.qml's
        // dashboardPage).
        function page(name: string): string {
            const valid = ["overview", "notes", "todo", "pet", "dashboard", "messages"]
            const normalized = (name || "").toLowerCase()
            if (valid.indexOf(normalized) === -1)
                return "ISLAND_PAGE_UNSUPPORTED"
            root.islandPageRequested(normalized === "dashboard" ? "overview" : normalized)
            return "ISLAND_PAGE_SUCCESS"
        }
    }

    property IpcHandler insightsIpc: IpcHandler {
        target: "insights"

        function dashboard(): string {
            root.insightOpenRequested("overview")
            return "DASHBOARD_OPEN_SUCCESS"
        }

        // Weather now lives inside the calendar page (screens/calendar-weather.html),
        // so this opens that page; there is no standalone weather page.
        function weather(): string {
            root.insightOpenRequested("calendar")
            return "WEATHER_OPEN_SUCCESS"
        }

        function calendar(): string {
            root.insightOpenRequested("calendar")
            return "CALENDAR_OPEN_SUCCESS"
        }

        function media(): string {
            root.insightOpenRequested("media-center")
            return "MEDIA_OPEN_SUCCESS"
        }

        function system(): string {
            root.insightOpenRequested("system")
            return "SYSTEM_OPEN_SUCCESS"
        }

        function battery(): string {
            root.insightOpenRequested("battery")
            return "BATTERY_OPEN_SUCCESS"
        }

        function wallpaper(): string {
            root.insightOpenRequested("wallpaper")
            return "WALLPAPER_OPEN_SUCCESS"
        }

        // SUPER+W binds to this: wallpaper() above only opens, so a second
        // press would leave the picker up. pageToggleRequested is the same
        // open/dismiss path ShellCompatShortcuts' wallpaperSelectorToggle uses.
        function wallpaperToggle(): string {
            root.pageToggleRequested("wallpaper")
            return "WALLPAPER_TOGGLE_SUCCESS"
        }

        function clipboard(): string {
            root.insightOpenRequested("clipboard")
            return "CLIPBOARD_OPEN_SUCCESS"
        }
    }

    // `qml-rice ipc style set pill|mac`, `style toggle`, `style get`. Writes
    // through SettingsStore, so the choice persists across restarts. The
    // switch is live: the mac surfaces are Loaders bound to uiStyle.
    property IpcHandler styleIpc: IpcHandler {
        target: "style"

        function set(style: string): string {
            return SettingsStore.setUiStyle(style)
                ? "STYLE_SET_SUCCESS" : "STYLE_SET_INVALID"
        }

        function toggle(): string {
            SettingsStore.setUiStyle(Config.appearance.macStyle ? "pill" : "mac")
            return "STYLE_TOGGLE_SUCCESS"
        }

        function get(): string {
            return Config.appearance.uiStyle
        }
    }

    // `qs ipc call timer start <minutes>|pause|stop`. Drives the shared
    // PomodoroService directly, so every island shows the same countdown.
    property IpcHandler timerIpc: IpcHandler {
        target: "timer"

        function start(minutes: string): string {
            const value = parseFloat(minutes)
            if (!(value > 0) || value > 1440)
                return "TIMER_START_INVALID"
            PomodoroService.start(value)
            return "TIMER_START_SUCCESS"
        }

        function pause(): string {
            PomodoroService.pause()
            return "TIMER_PAUSE_SUCCESS"
        }

        function stop(): string {
            PomodoroService.reset()
            return "TIMER_STOP_SUCCESS"
        }
    }
}
