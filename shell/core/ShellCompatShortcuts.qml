import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../services"

// ShellCompatShortcuts -- registers the subset of end4-pC's `quickshell:*`
// Hyprland global shortcuts (see `hyprctl globalshortcuts`, and the owner's
// own ~/.config/hypr/hyprland/keybinds.lua / general.lua) that this shell can
// meaningfully serve, so the owner's EXISTING binds keep working once
// qml-rice is the only shell running -- without editing a single line of
// ~/.config/hypr. Instantiated once from shell.qml.
//
// Every name below is registered with the default appid "quickshell" --
// the same one end4-pC uses (confirmed: Quickshell's own GlobalShortcut
// C++ default is "quickshell", not derived from our config name) -- because
// that IS the point: the owner's Hyprland binds dispatch
// `quickshell:<name>` by that exact literal string, with no knowledge of
// which shell answers it.
//
// GATING IS MANDATORY. See the measured probe result in HANDOVER
// ("Task A"): registering a duplicate {appid, name} on this Hyprland build
// did NOT disconnect either client or raise the documented `already_taken`
// protocol error -- both processes stayed up and `hyprctl globalshortcuts`
// listed the name twice. That is a real, surprising finding, but it does
// NOT make duplicate registration safe: which of two registrants actually
// receives a given keypress once both are registered was deliberately never
// tested (triggering a shortcut is exactly the synthetic-input this task
// forbids), so registering `quickshell:lock` (or any of the others) while
// end4-pC is still holding it risks silently breaking or double-firing the
// owner's existing bind for that name, including the idle/before-sleep
// lock path. The gate below exists regardless of whether duplicates turned
// out to be fatal.
//
//   QMLRICE_COMPAT_SHORTCUTS=off  -> never active. Nothing below is ever
//                                    registered.
//   QMLRICE_COMPAT_SHORTCUTS=on   -> always active immediately, skipping
//                                    both safety checks below. For testing
//                                    only when you KNOW nothing else holds
//                                    these names.
//   unset / anything else (auto) -> starts INACTIVE. Every 15s, checks:
//     (a) `pgrep -af '^(qs|quickshell)( .*)? -c '` (excluding our own
//         config name, in case this is ever installed as `-c qml-rice`
//         instead of always running via `-p`) finds no other named
//         quickshell/qs config running -- end4-pC is exactly
//         `qs -c end4-pC`, which this matches; our own process is always
//         `qs -p .../shell.qml`, which this pattern never matches, so no
//         self-exclusion is actually needed today, only defensively kept.
//     (b) `hyprctl globalshortcuts` no longer lists `quickshell:lock`.
//     Once both are true, activates once and stops polling. Does NOT
//     re-deactivate if some other shell starts again afterwards -- this is
//     a one-way latch, matching "activate once it's gone" literally; if
//     the owner starts end4-pC again after qml-rice's compat shortcuts have
//     activated, restart qml-rice to re-gate. (Starting end4-pC in that
//     situation duplicates every name below at the protocol level -- see
//     the Task A note above.)
QtObject {
    id: root

    readonly property string mode: (Quickshell.env("QMLRICE_COMPAT_SHORTCUTS") || "auto").toLowerCase()
    property bool active: mode === "on"

    // The launcher's press-arm / release-toggle / interrupt state machine,
    // mirroring end4-pC's modules/ii/overview/Overview.qml exactly:
    // searchToggleRelease arms on press and toggles on release UNLESS
    // searchToggleReleaseInterrupt disarmed it in between (bound, on the
    // owner's end, to a submap catch-all so pressing any other key while
    // Super is held cancels the tap-to-search gesture).
    property bool searchReleaseArmed: true

    function log(line: string): void {
        console.log("ShellCompatShortcuts: " + line)
    }

    Component.onCompleted: {
        if (mode === "off") {
            log("disabled (QMLRICE_COMPAT_SHORTCUTS=off)")
            return
        }
        if (mode === "on") {
            log("forced active (QMLRICE_COMPAT_SHORTCUTS=on) -- skipping the running-shell and quickshell:lock checks")
            return
        }
        log("inactive at startup (auto mode) -- polling every 15s until no other named quickshell/qs config is running and quickshell:lock is free")
        gateTimer.start()
    }

    property Timer gateTimer: Timer {
        interval: 15000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.pollGate()
    }

    function pollGate(): void {
        if (root.active || otherShellCheck.running || lockGlobalCheck.running)
            return
        otherShellCheck.running = true
    }

    // Super+H / Super+` reach RunningApps through the apps IPC (ShellActions.appsIpc).
    property Connections appsWatcher: Connections {
        target: ShellActions
        function onAppsHideFocusedRequested(): void { RunningApps.hideFocused() }
        function onAppsCycleRequested(): void { RunningApps.cycle() }
    }

    property Process otherShellCheck: Process {
        // Anchored so it only matches a *named-config* invocation
        // ("qs -c end4-pC"), never our own always-"-p"-flagged process, and
        // never the wl-paste/cliphist watchers (execs.lua) whose command
        // lines start with "wl-paste", not "qs"/"quickshell".
        command: ["pgrep", "-af", "^(qs|quickshell)( .*)? -c "]
        stdout: StdioCollector {
            onStreamFinished: {
                const otherShellRunning = text.split("\n")
                    .map(line => line.trim())
                    .some(line => line.length > 0 && line.indexOf("qml-rice") === -1)
                root.finishOtherShellCheck(otherShellRunning)
            }
        }
    }

    function finishOtherShellCheck(otherShellRunning: bool): void {
        if (otherShellRunning) {
            // Already known to be unsafe -- skip the hyprctl round trip.
            root.evaluateGate(true, true)
            return
        }
        lockGlobalCheck.running = true
    }

    property Process lockGlobalCheck: Process {
        command: ["hyprctl", "globalshortcuts"]
        stdout: StdioCollector {
            onStreamFinished: root.evaluateGate(false, text.indexOf("quickshell:lock") !== -1)
        }
    }

    function evaluateGate(otherShellRunning: bool, lockGlobalPresent: bool): void {
        if (root.active)
            return
        if (!otherShellRunning && !lockGlobalPresent) {
            root.active = true
            gateTimer.stop()
            log("activating -- no other named quickshell/qs config is running and quickshell:lock is free")
        }
    }

    property LazyLoader shortcutsLoader: LazyLoader {
        active: root.active

        Item {
            // -- Lock / after-sleep refocus ----------------------------------
            // Engage our own lock/LockScreen.qml first; services/LockService.qml
            // owns the "fall back to hyprlock" decision (failedToLock, or not
            // secure within 2s) so this and services/SessionService.qml's own
            // lock path share exactly one fallback policy.
            GlobalShortcut {
                appid: "quickshell"
                name: "lock"
                onPressed: LockService.engage()
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "lockFocus"
                // hyprlock manages its own input focus; registered purely so
                // hypridle.conf's after_sleep_cmd dispatch has a listener.
            }

            // -- Launcher (search) -------------------------------------------
            GlobalShortcut {
                appid: "quickshell"
                name: "searchToggle"
                onPressed: ShellActions.launcherToggleRequested()
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "searchToggleRelease"
                onPressed: root.searchReleaseArmed = true
                onReleased: {
                    if (!root.searchReleaseArmed) {
                        root.searchReleaseArmed = true
                        return
                    }
                    ShellActions.launcherToggleRequested()
                }
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "searchToggleReleaseInterrupt"
                onPressed: root.searchReleaseArmed = false
            }

            // -- Overview / Dashboard -----------------------------------------
            GlobalShortcut {
                appid: "quickshell"
                name: "overviewWorkspacesToggle"
                onPressed: ShellActions.pageToggleRequested("overview")
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "sidebarLeftToggle"
                onPressed: ShellActions.pageToggleRequested("overview")
            }

            // -- Mission Control (missioncontrol/). F3 binds this in
            // hypr/hyprland/mac-mission.lua. The gestures branch may call the same
            // name for a 3-finger swipe up: quickshell:missionControlToggle.
            GlobalShortcut {
                appid: "quickshell"
                name: "missionControlToggle"
                onPressed: ShellActions.missionControlToggleRequested()
            }

            // -- Clipboard ------------------------------------------------------
            GlobalShortcut {
                appid: "quickshell"
                name: "overviewClipboardToggle"
                onPressed: ShellActions.clipboardToggleRequested()
            }

            // -- Session --------------------------------------------------------
            GlobalShortcut {
                appid: "quickshell"
                name: "sessionToggle"
                onPressed: ShellActions.pageToggleRequested("session")
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "sessionOpen"
                onPressed: ShellActions.sessionOpenRequested()
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "sessionClose"
                onPressed: ShellActions.sessionCloseRequested()
            }

            // -- Notification Center (mac style; Super+N) ---------------------
            GlobalShortcut {
                appid: "quickshell"
                name: "notificationCenterToggle"
                onPressed: ShellActions.macSurfaceRequested("notifications", "toggle")
            }

            // -- Control centre / settings / wallpaper / media -----------------
            GlobalShortcut {
                appid: "quickshell"
                name: "sidebarRightToggle"
                onPressed: ShellActions.controlCenterToggleRequested()
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "settingsToggle"
                onPressed: ShellActions.pageToggleRequested("settings")
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "wallpaperSelectorToggle"
                onPressed: ShellActions.pageToggleRequested("wallpaper")
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "mediaControlsToggle"
                onPressed: ShellActions.pageToggleRequested("media-center")
            }

            // -- Brightness / volume OSD ----------------------------------------
            GlobalShortcut {
                appid: "quickshell"
                name: "brightnessIncrease"
                onPressed: BrightnessService.setBrightness(BrightnessService.percentage + 5)
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "brightnessDecrease"
                onPressed: BrightnessService.setBrightness(BrightnessService.percentage - 5)
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "osdVolumeTrigger"
                onPressed: ShellActions.osdVolumeTriggerRequested()
            }

            // -- Region screenshot / OCR -----------------------------------------
            // Exactly the owner's own fallback commands
            // (~/.config/hypr/hyprland/keybinds.lua:~68-81), guarded the same
            // way theirs is (`pidof slurp ||`) so a concurrent manual slurp
            // invocation from that same fallback bind doesn't double-fire.
            GlobalShortcut {
                appid: "quickshell"
                name: "regionScreenshot"
                onPressed: Quickshell.execDetached(["sh", "-c",
                    "pidof slurp >/dev/null || hyprshot --freeze --clipboard-only --mode region --silent"])
            }
            GlobalShortcut {
                appid: "quickshell"
                name: "regionOcr"
                onPressed: Quickshell.execDetached(["sh", "-c",
                    "pidof slurp >/dev/null || " +
                    "grim -g \"$(slurp $SLURP_ARGS)\" \"/tmp/ocr_image.png\" && " +
                    "tesseract \"/tmp/ocr_image.png\" stdout -l " +
                    "$(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\n' '+' | sed 's/\\+$/\\n/') " +
                    "| wl-copy && rm \"/tmp/ocr_image.png\""])
            }

            // -- Not registered (see HANDOVER "unserved") ------------------------
            // wallpaperSelectorRandom, toggleLightDark: skipped on purpose --
            // neither WallpaperService nor AppearanceService already exposes
            // a random-wallpaper/mode-toggle function, and this task does not
            // authorize adding one just for this. emoji/symbols/osk/overlay/
            // cheatsheet/bar/workspaceNumber/regionSearch/screenTranslate/
            // regionRecord*/panelFamilyCycle/centeredWallpaperToggle: this
            // shell has no equivalent surface at all.
        }
    }
}
