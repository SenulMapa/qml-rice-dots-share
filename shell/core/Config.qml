pragma Singleton
import QtQuick
import Quickshell
import "../mac/MacFormat.js" as Format
import "../services"

QtObject {
    id: root

    readonly property QtObject appearance: QtObject {
        readonly property string mode: {
            const candidate = SettingsStore.value("appearance", "mode", "dark")
            return SettingsStore.validModes.indexOf(candidate) >= 0
                ? candidate : "dark"
        }
        // Typography. These two keys drive ~330 font.family references across
        // the shell, which is why the entire typographic identity is two
        // lines. All faces are OFL and ship in assets/fonts.
        //   ui      Geist            — tiles, body, controls
        //   data    Geist Mono       — numerals, ids, durations (always tabular)
        //   display Instrument Serif — panel titles; carries the identity
        //   clock   Bitcount Single  — the one element on screen at all times
        // All four faces below are user-pickable from Settings > Appearance
        // (panels/SettingsPage.qml's font pickers, SettingsStore.setFontFamily)
        // -- these string literals are only the FALLBACK when nothing is
        // saved yet, or the saved family is no longer installed.
        //
        // fontFamily is the shell's ONE general-UI typography token --
        // pill/island/dashboard/satellites/launcher/notifications/OSD/
        // settings text all already route through it (nothing hardcodes a
        // family string per file), so this single default is the owner's
        // expressive-but-serious rebrand: Bricolage Grotesque everywhere
        // EXCEPT the three clocks, which deliberately use their OWN separate
        // tokens (clockFontFamily below, and displayFontFamily for the
        // dashboard hour numeral -- panels/DashboardHeroRow.qml) and so are
        // unaffected by this default changing. Numerals that must stay
        // tabular (percentages, timers, durations) already route through
        // monoFontFamily instead, also unaffected.
        // Glass redesign (6 Oct 2026): Poppins is the default for UI,
        // display and clock alike -- one geometric family reads calm on
        // frosted glass where the serif/pixel/grotesque mix read busy.
        // Still user-pickable; these are only the fallbacks.
        readonly property string fontFamily: SettingsStore.fontFamilyValue(
            "fontFamily", "Poppins")
        readonly property string monoFontFamily: SettingsStore.fontFamilyValue(
            "monoFontFamily", "Geist Mono")
        readonly property string displayFontFamily: "Poppins"
        readonly property string clockFontFamily: SettingsStore.fontFamilyValue(
            "clockFontFamily", "Poppins")
        readonly property int clockFontWeight: 600
        // Owner's Figma "Now Playing" card (node 9:3) only -- NOW PLAYING
        // label, title and the centred lyrics area. Nowhere else.
        readonly property string handFontFamily: SettingsStore.fontFamilyValue(
            "handFontFamily", "Poppins")
        // Global type-scale multiplier (Settings > Appearance). Feeds
        // Theme's shared text/icon size tokens (core/Theme.qml) live --
        // NOT a per-literal sweep of the ~330 font.pixelSize call sites,
        // which route through those tokens or their own local values.
        // Default 1.0: Bricolage Grotesque's larger x-height reads clear
        // at this shell's usual 8-14px sizes. Still user-adjustable down
        // to 0.8 or up to 1.3.
        readonly property real fontScale: SettingsStore.numberValue(
            "appearance", "fontScale", 1.0, 0.8, 1.3)
        // Settings > Appearance "Display scale" (core/DisplayScale.qml).
        // 0 is the sentinel for "auto" (DisplayScale.forScreen computes it
        // from the screen's physical PPI); the settings slider itself only
        // offers 1.0-2.0, matching DisplayScale's own auto ceiling of 1.75
        // plus headroom for a deliberate manual bump past it.
        readonly property real displayScale: SettingsStore.numberValue(
            "appearance", "displayScale", 0, 0, 2.0)
        // "auto" (default) defers to services/PerformanceService.qml's own
        // battery/iGPU detection; "low"/"high" force a tier from Settings
        // instead of only the QMLRICE_PERFORMANCE_TIER env var.
        readonly property string performanceTierOverride: {
            const candidate = SettingsStore.value("appearance",
                "performanceTierOverride", "auto")
            return SettingsStore.validPerformanceTiers.indexOf(candidate) >= 0
                ? candidate : "auto"
        }
        // Micro-labels are set UPPERCASE with positive tracking. That single
        // treatment does as much work as the display serif: it turns a value
        // into instrumentation instead of a settings-list entry.
        readonly property real trackMicro: 0.10
        readonly property real trackDisplay: -0.02
        readonly property string stateRoot: {
            const configured = Quickshell.env("XDG_STATE_HOME") || ""
            return configured.length > 0 ? configured
                : Quickshell.env("HOME") + "/.local/state"
        }
        // This shell's own scratch space -- never ~/.config, never another
        // rice's state directory. Only PaletteAutoService writes here.
        readonly property string cacheRoot: {
            const configured = Quickshell.env("XDG_CACHE_HOME") || ""
            return (configured.length > 0 ? configured
                : Quickshell.env("HOME") + "/.cache") + "/qml-rice"
        }
        // Runtime palettes are mutable user state; this packaged file is fallback only.
        readonly property string activePalettePath: stateRoot + "/odyssey/palette.json"
        // A matugen palette this shell generated for itself from whatever
        // wallpaper it could find read-only (services/PaletteAutoService.qml)
        // -- the fallback below activePalettePath (the interactive wallpaper
        // picker's own committed output) and above the hardcoded Material
        // defaults in Theme.qml's fallbackDark/fallbackLight.
        readonly property string fallbackPalettePath: cacheRoot + "/palette.json"
        readonly property real surfaceOpacity: SettingsStore.numberValue(
            "appearance", "surfaceOpacity", 0.96, 0.72, 1)
        readonly property string accentOverride: {
            const candidate = SettingsStore.value("appearance",
                "accentOverride", "")
            return typeof candidate === "string"
                    && /^#[0-9a-fA-F]{6}$/.test(candidate)
                ? candidate.toLowerCase() : ""
        }
        readonly property bool reducedMotion: SettingsStore.boolValue(
            "appearance", "reducedMotion", false)
        readonly property string motionSpeed: {
            const candidate = SettingsStore.value("appearance", "motionSpeed",
                "balanced")
            return SettingsStore.validMotionSpeeds.indexOf(candidate) >= 0
                ? candidate : "balanced"
        }
        readonly property real motionScale: motionSpeed === "quick" ? 0.76
            : motionSpeed === "calm" ? 1.28 : 1
        readonly property real motionSpeedMultiplier: SettingsStore.numberValue(
            "motion", "scale", 1.0, 0.8, 1.2)
        readonly property string density: {
            const candidate = SettingsStore.value("appearance", "density",
                "balanced")
            return SettingsStore.validDensities.indexOf(candidate) >= 0
                ? candidate : "balanced"
        }
        readonly property real densityScale: density === "compact" ? 0.86
            : density === "airy" ? 1.12 : 1
        readonly property string cornerStyle: {
            const candidate = SettingsStore.value("appearance", "cornerStyle",
                "balanced")
            return SettingsStore.validCornerStyles.indexOf(candidate) >= 0
                ? candidate : "balanced"
        }
        readonly property real cornerScale: cornerStyle === "subtle" ? 0.72
            : cornerStyle === "round" ? 1.22 : 1
        readonly property bool wallpaperPaletteEnabled: SettingsStore.boolValue(
            "appearance", "wallpaperPaletteEnabled", true)
        readonly property bool use24HourClock: SettingsStore.boolValue(
            "appearance", "use24HourClock", true)
        // Read by desktop/services/DeskTheme.qml: true gives every ported
        // impasto surface (desktop widgets, dashboard, island cards) impasto's
        // own flat near-black grounds and iOS accents, which is what its
        // screenshots show; false hands them back to this shell's adaptive
        // Material palette, whose wallpaper-derived primary reads as a wash
        // rather than an accent on those designs.
        readonly property bool impastoPalette: SettingsStore.boolValue(
            "appearance", "impastoPalette", true)
        // Ink redesign (spec 2026-10-08-ink-redesign-design.md): the island
        // and its pages become opaque #000 with a 1px ink rim, Geist/Instrument
        // Serif type and the showcase radii. false restores the glass look
        // in every QML file that branches on it.
        readonly property bool ink: SettingsStore.boolValue(
            "appearance", "ink", true)
        // Ported from impasto's ThemeService.pushTerminal()/theme_manager.py
        // (kitty/foot palette push): OFF by default. Unlike everything else
        // in the repaint pipeline (which only ever touches
        // Config.appearance.cacheRoot, ~/.cache/qml-rice), turning this on
        // lets WallpaperService run scripts/repaint-terminals.sh with
        // --apply on every wallpaper change, which DOES write into
        // ~/.config (a kitty/foot include the user's own config has to
        // `include`) -- opt-in only, and only the shell (never this agent)
        // runs it.
        readonly property bool repaintApps: SettingsStore.boolValue(
            "appearance", "repaintApps", false)
        // Presentation style (spec 2026-10-19-mac-style-design.md section 2).
        // "pill": the ink island presents everything (default). "mac": the
        // Tahoe surfaces under shell/mac/ present notification banners, the
        // NC, the launcher and the ringing call; see the routing guards in
        // island/IslandController.qml (macRoute, showNotification, syncPhoneCall).
        // Unknown stored values fall back to "pill".
        readonly property string uiStyle: {
            const candidate = SettingsStore.value("appearance", "uiStyle", "pill")
            return SettingsStore.validUiStyles.indexOf(candidate) >= 0
                ? candidate : "pill"
        }
        readonly property bool macStyle: uiStyle === "mac"
        // Only read while uiStyle is "mac": keeps the pill (music, timer,
        // active call, recording) in mac skin. The skin lands with MacPillSkin.
        readonly property bool macLiveActivities: SettingsStore.boolValue(
            "appearance", "macLiveActivities", true)
        // Screen the mac surfaces (banners, NC, Control Center, Spotlight,
        // call card) open on: "focused" (the Hyprland focused monitor, default)
        // or a pinned output name. Read by mac/MacScreen.qml when a surface is
        // created. Only read while uiStyle is "mac".
        readonly property string macScreen: SettingsStore.validMacScreen(
            SettingsStore.value("appearance", "macScreen", "focused"))
            ? SettingsStore.value("appearance", "macScreen", "focused") : "focused"
        // Scale for every mac geometry, font and inset (mac/MacTokens.s()).
        // Auto = primary output width / 1440 (Tahoe's reference width), clamped
        // 1.0-1.6. A positive "macScale" setting overrides it.
        readonly property real macScale: Format.macScaleFor(
            SettingsStore.numberValue("appearance", "macScale", 0, 0, 1.6),
            (Quickshell.screens.find(s => s.name === HyprlandService.primaryMonitorName)
                || Quickshell.screens[0] || { width: 1440 }).width)
        // Mac style with live activities switched off: the pill window is hidden
        // entirely (island/Island.qml `visible`), so music, timer, call and
        // recording pills are not shown at all. Pill style is never affected.
        readonly property bool pillHidden: macStyle && !macLiveActivities
    }

    readonly property QtObject island: QtObject {
        // DisplayScale.primary (core/DisplayScale.qml): every raw-px
        // geometry setting in this QtObject is wrapped in it below. These
        // are stored/edited UNSCALED (Settings sliders read/write the base
        // value via SettingsStore.numberValue's own default/bounds) --
        // DisplayScale is applied once, here, at the point every island
        // geometry consumer (IslandController.qml's targetWidth/
        // targetHeight, island/Island.qml's implicitHeight/exclusiveZone/
        // margins.top) actually reads it. This was the gap Theme.u()/
        // BlobLayout.unit() closed for design-unit-derived sizes but not for
        // these -- they're independent pixel literals, so the pill silently
        // stayed the same physical size on this laptop's high-PPI panel
        // even after unit()/Theme.u() started scaling.
        readonly property int topMargin: Math.round(SettingsStore.numberValue(
            "island", "topMargin", 5, 0, 16) * DisplayScale.primary)
        // topMargin + reservedSpace keeps four pixels below the 26 px pill.
        readonly property int reservedSpace: Math.round(SettingsStore.numberValue(
            "island", "reservedSpace", 30, 26, 52) * DisplayScale.primary)
        readonly property int dormantWidth: Math.round(SettingsStore.numberValue(
            "island", "dormantWidth", 104, 96, 320) * DisplayScale.primary)
        readonly property int dormantHeight: Math.round(28 * DisplayScale.primary)
        readonly property bool restScaleSynced: SettingsStore.boolValue(
            "island", "restScaleSynced", true)
        // DisplayScale.primary folded in here too (kept `real`, no rounding
        // at this level -- every call site below already Math.round()s its
        // own literal * this scale). These are THE multiplier every pill
        // font/icon size actually uses (IslandRestItem, WorkspacePillRow,
        // RecordingIndicator, IslandHoverItem, IslandHover, CompactStatus),
        // so without this the geometry could grow (previous commit) while
        // the text/icons inside stayed the old physical size. Settings
        // sliders for these four read the BASE (unscaled) value via
        // SettingsStore.numberValue directly -- see panels/SettingsPage.qml.
        readonly property real restTextScale: SettingsStore.numberValue(
            "island", "restTextScale", 100, 80, 130) / 100 * DisplayScale.primary
        readonly property real restIconScale: SettingsStore.numberValue(
            "island", "restIconScale", 100, 80, 130) / 100 * DisplayScale.primary
        readonly property real restContentScale: Math.max(
            restTextScale, restIconScale)
        readonly property int restItemSpacing: Math.round(SettingsStore.numberValue(
            "island", "restItemSpacing", 8, 2, 18) * DisplayScale.primary)
        // AT REST THE ISLAND SHOWS THE CLOCK AND NOTHING ELSE.
        //
        // Upstream defaulted to every available item, which put ten things on
        // screen permanently. The resting state is the one you see all day and
        // never asked to see, so it is the state that decides whether a shell
        // feels calm or noisy. Everything removed here is still one hover
        // away -- the hover state keeps the full set.
        //
        // Still user-configurable; only the DEFAULT changed.
        readonly property var restItemOrder: SettingsStore.stringListValue(
            "island", "restItemOrder", [],
            SettingsStore.validRestIslandItems)
        readonly property bool restShowWeather: restItemOrder.indexOf("Weather") >= 0
        readonly property bool restShowDnd: restItemOrder.indexOf("Dnd") >= 0
        readonly property bool restShowKeepAwake:
            restItemOrder.indexOf("KeepAwake") >= 0
        readonly property bool restShowPowerProfile:
            restItemOrder.indexOf("PowerProfile") >= 0
        // The resting pill HUGS its content. Upstream floored it at 214px, which
        // with only a clock inside rendered as a long empty bar -- the same
        // complaint made about ChillPill's default state. 104 keeps the
        // reference pill's measured aspect ratio (185:50 = 3.7) at this
        // island's 28px height: 28 x 3.7 = 104.
        // restContentScale now already carries DisplayScale.primary (see its
        // own comment above) -- do NOT multiply by it again here.
        readonly property int restMinimumWidth: Math.round(
            104 * restContentScale)
        readonly property bool hoverScaleSynced: SettingsStore.boolValue(
            "island", "hoverScaleSynced", true)
        // DisplayScale.primary folded in -- see restTextScale/restIconScale's
        // own comment above.
        readonly property real hoverTextScale: SettingsStore.numberValue(
            "island", "hoverTextScale", 100, 80, 130) / 100 * DisplayScale.primary
        readonly property real hoverIconScale: SettingsStore.numberValue(
            "island", "hoverIconScale", 100, 80, 130) / 100 * DisplayScale.primary
        readonly property real hoverContentScale: Math.max(
            hoverTextScale, hoverIconScale)
        readonly property int hoverItemSpacing: Math.round(SettingsStore.numberValue(
            "island", "hoverItemSpacing", 8, 2, 20) * DisplayScale.primary)
        readonly property var hoverItemOrder: SettingsStore.stringListValue(
            "island", "hoverItemOrder", SettingsStore.defaultHoverIslandItems,
            SettingsStore.validHoverIslandItems)
        readonly property bool hoverShowWorkspaces:
            hoverItemOrder.indexOf("Workspaces") >= 0
        readonly property bool hoverShowClock: hoverItemOrder.indexOf("Clock") >= 0
        readonly property bool hoverShowMedia: hoverItemOrder.indexOf("Media") >= 0
        readonly property bool hoverShowAudio: hoverItemOrder.indexOf("Audio") >= 0
        readonly property bool hoverShowNetwork:
            hoverItemOrder.indexOf("Network") >= 0
        readonly property bool hoverShowDnd: hoverItemOrder.indexOf("Dnd") >= 0
        readonly property bool hoverShowBluetooth:
            hoverItemOrder.indexOf("Bluetooth") >= 0
        readonly property bool hoverShowKeepAwake:
            hoverItemOrder.indexOf("KeepAwake") >= 0
        readonly property bool hoverShowBattery:
            hoverItemOrder.indexOf("Battery") >= 0
        // hoverContentScale now already carries DisplayScale.primary --
        // same note as restMinimumWidth above.
        readonly property int hoverMinimumWidth: Math.round(
            470 * hoverContentScale)
        readonly property int hoverMediaMinimumWidth: hoverMinimumWidth
        readonly property int hoverWidth: Math.round(SettingsStore.numberValue(
            "island", "hoverWidth", 470, 470, 760) * DisplayScale.primary)
        readonly property int hoverHeight: Math.round(54 * DisplayScale.primary)
        readonly property int expandedWidth: Math.round(SettingsStore.numberValue(
            "island", "expandedWidth", 789, 620, 900) * DisplayScale.primary)
        readonly property int expandedHeight: Math.round(300 * DisplayScale.primary)
        // Unused dead settings (superseded by IslandController.qml's own
        // Theme.u(7.44)/Theme.u(1.2) OSD pill sizing, per that file's own
        // comment) -- scaled anyway for consistency, costs nothing.
        readonly property int osdWidth: Math.round(360 * DisplayScale.primary)
        readonly property int osdHeight: Math.round(72 * DisplayScale.primary)
        readonly property int mediaWidth: Math.round(460 * DisplayScale.primary)
        readonly property int mediaHeight: Math.round(88 * DisplayScale.primary)
        // Grace period between the pointer LEAVING the hover pill and the
        // shrink-back-to-dormant collapse starting. Short on purpose -- this
        // is not a settle duration, it exists only to swallow the cursor
        // skimming the island's edge on its way past. 420 ms read as
        // outright lag (a real, deliberate mouse-away read as unresponsive
        // for almost half a second); 90 ms is still enough to absorb a skim
        // without the collapse visibly starting mid-flicker.
        readonly property int collapseDelay: 90
        readonly property bool autoHide: SettingsStore.boolValue(
            "island", "autoHide", false)
        readonly property int autoHideDelay: SettingsStore.numberValue(
            "island", "autoHideDelay", 1800, 500, 10000)
        readonly property bool showRevealLip: SettingsStore.boolValue(
            "island", "showRevealLip", true)
        readonly property int revealHeight: Math.round(4 * DisplayScale.primary)
        // Blob-engine satellite neck fusion (docs/superpowers/specs/
        // 2026-09-23-blob-rebuild-design.md section 1): "joined" fuses an
        // open satellite to the pill with a wide neck; "separate" collapses
        // the neck to near-zero. Settable via SettingsStore.setIslandSatelliteJoin().
        readonly property string satelliteJoin: {
            const candidate = SettingsStore.value("island", "satelliteJoin",
                "joined")
            return SettingsStore.validSatelliteJoinModes.indexOf(candidate) >= 0
                ? candidate : "joined"
        }
        // Proto value -- not a user setting.
        readonly property int osdTimeout: 1500
        // Was a hardcoded `true`; now a real stored setting (see
        // SettingsStore.setIslandHideInFullscreen(), added for the
        // impasto-settings-full port's island/pill settings tab).
        readonly property bool hideInFullscreen: SettingsStore.boolValue(
            "island", "hideInFullscreen", true)
    }

    readonly property QtObject idle: QtObject {
        readonly property bool powerSoundsEnabled: SettingsStore.boolValue(
            "idle", "powerSoundsEnabled", false)
        // Real timeouts enforced by services/IdleService.qml's own
        // Quickshell.Wayland IdleMonitor instances (ext-idle-notify-v1,
        // not a hypridle config file this shell doesn't own -- see
        // HANDOVER.md's "impasto desktop port" section on why packaged
        // hypridle was dropped). Minutes; 0 means "never".
        readonly property int screenOffTimeoutMinutes: SettingsStore.numberValue(
            "idle", "screenOffTimeoutMinutes", 5, 0, 60)
        readonly property int lockTimeoutMinutes: SettingsStore.numberValue(
            "idle", "lockTimeoutMinutes", 10, 0, 120)
        readonly property int suspendTimeoutMinutes: SettingsStore.numberValue(
            "idle", "suspendTimeoutMinutes", 0, 0, 240)
    }

    readonly property QtObject audio: QtObject {
        readonly property int maxVolumePercent: 100
    }

    // Edge-scroll volume (edge/VolumeEdge.qml) -- thin invisible strips on
    // each screen's OUTER edge only (core/EdgeGeometry.qml decides which
    // edges qualify from live screen geometry). step is the percent change
    // per accumulated wheel notch; 1-10 keeps a runaway touchpad from
    // slamming volume in one gesture.
    readonly property QtObject volumeEdge: QtObject {
        readonly property bool enabled: SettingsStore.boolValue(
            "volumeEdge", "enabled", true)
        readonly property int step: SettingsStore.numberValue(
            "volumeEdge", "step", 2, 1, 10)
    }

    readonly property QtObject controlCenter: QtObject {
        readonly property int levelConfirmationTimeout: 600
        // Wi-Fi/Bluetooth/Audio satellites: dwell surfaces beside the island,
        // not inside it, so opening them never grows the control centre.
        // Width is Theme.u(6.8) and the height cap is Theme.u(9.5), both set
        // at the satellite call sites in island/Island.qml, not here -- this
        // file stays Theme-independent.
        readonly property int satelliteGap: Math.round(16 * DisplayScale.primary)
    }

    readonly property QtObject nightLight: QtObject {
        // Applied via `hyprctl hyprsunset temperature <K>`; identity (off)
        // is any read below 5500 K.
        readonly property int warmTemperature: 4000
    }

    readonly property QtObject system: QtObject {
        readonly property int metricsInterval: 2000
        readonly property int temperatureInterval: 5000
        readonly property int storageInterval: 30000
        readonly property string temperaturePath: "/sys/class/thermal/thermal_zone0/temp"
        readonly property string storagePath: "/"
    }

    readonly property QtObject animations: QtObject {
        readonly property int fast: root.appearance.reducedMotion ? 1
            : Math.round(150 * root.appearance.motionScale)
        readonly property int normal: root.appearance.reducedMotion ? 1
            : Math.round(220 * root.appearance.motionScale)
        readonly property int large: root.appearance.reducedMotion ? 1
            : Math.round(300 * root.appearance.motionScale)
        // Matches the island surface spring's own settle time (see
        // island/Island.qml's morphT omega comment) -- this is how long
        // IslandController's dismissSurfaceTimer waits before clearing
        // `dismissing`, so it should track what the spring actually needs,
        // not guess independently.
        readonly property int surfaceMorph: root.appearance.reducedMotion ? 1
            : Math.round(260 * root.appearance.motionScale)
        readonly property int profileMorph: root.appearance.reducedMotion ? 1
            : Math.round(340 * root.appearance.motionScale)
        readonly property int profileFeedbackRise: root.appearance.reducedMotion ? 1
            : Math.round(220 * root.appearance.motionScale)
        readonly property int profileFeedbackHold: root.appearance.reducedMotion ? 1
            : Math.round(300 * root.appearance.motionScale)
        readonly property int profileFeedbackSettle: root.appearance.reducedMotion ? 1
            : Math.round(260 * root.appearance.motionScale)
        readonly property int profileFeedbackFade: root.appearance.reducedMotion ? 1
            : Math.round(480 * root.appearance.motionScale)
    }

    readonly property QtObject insights: QtObject {
        readonly property int width: root.island.expandedWidth
        readonly property int height: Math.round(440 * DisplayScale.primary)
        readonly property int pageTransition: 220
        readonly property int hourlyPreviewCount: 12
        readonly property int dailyPreviewCount: 7
    }

    readonly property QtObject dashboard: QtObject {
        readonly property int width: root.island.expandedWidth
        readonly property int height: Math.round(440 * DisplayScale.primary)
        readonly property int transition: 220
        readonly property bool showHero: SettingsStore.boolValue(
            "dashboard", "showHero", true)
        readonly property bool showMedia: SettingsStore.boolValue(
            "dashboard", "showMedia", true)
        readonly property bool showSystem: SettingsStore.boolValue(
            "dashboard", "showSystem", true) || !showMedia
        readonly property bool showQuickStrip: SettingsStore.boolValue(
            "dashboard", "showQuickStrip", true)
    }

    readonly property QtObject notifications: QtObject {
        readonly property bool enabled: true
        readonly property bool takeOverServer: true
        readonly property bool showPopups: SettingsStore.boolValue(
            "notifications", "showPopups", true)
        readonly property bool allowCriticalAlerts: SettingsStore.boolValue(
            "notifications", "allowCriticalAlerts", true)
        readonly property int timeout: SettingsStore.numberValue(
            "notifications", "timeout", 5000, 2000, 10000)
        readonly property int criticalTimeout: SettingsStore.numberValue(
            "notifications", "criticalTimeout", 9000, 4000, 15000)
        readonly property int historyLimit: SettingsStore.numberValue(
            "notifications", "historyLimit", 50, 20, 100)
        readonly property bool doNotDisturb: SettingsStore.boolValue(
            "notifications", "doNotDisturb", false)
        readonly property int width: root.island.expandedWidth
        readonly property int height: Math.round(440 * DisplayScale.primary)
    }

    readonly property QtObject phone: QtObject {
        readonly property bool enabled: SettingsStore.boolValue(
            "phone", "enabled", false)
        readonly property bool lockOnLeave: SettingsStore.boolValue(
            "phone", "lockOnLeave", false)
        readonly property string phonectl: String(SettingsStore.value(
            "phone", "phonectl", "phonectl"))
    }

    readonly property QtObject launcher: QtObject {
        readonly property int width: root.island.expandedWidth
        readonly property int height: Math.round(440 * DisplayScale.primary)
        readonly property int resultLimit: 24
    }

    readonly property QtObject commandLauncher: QtObject {
        readonly property string historySource: {
            const candidate = SettingsStore.value("commandLauncher",
                "historySource", "auto")
            return SettingsStore.validCommandHistorySources.indexOf(candidate) >= 0
                ? candidate : "auto"
        }
        readonly property string terminal: {
            const candidate = SettingsStore.value("commandLauncher",
                "terminal", "auto")
            return SettingsStore.validCommandTerminals.indexOf(candidate) >= 0
                ? candidate : "auto"
        }
        readonly property bool historySuggestions: SettingsStore.boolValue(
            "commandLauncher", "historySuggestions", true)
    }

    readonly property QtObject hyprland: QtObject {
        // Matches the numeric workspace bindings discovered on this machine.
        readonly property int workspaceCount: 10
    }

    readonly property QtObject displays: QtObject {
        readonly property string islandPolicy: {
            const candidate = SettingsStore.value("displays", "islandPolicy", "all")
            return SettingsStore.validIslandPolicies.indexOf(candidate) >= 0
                ? candidate : "all"
        }
        readonly property string primaryMonitor: {
            const candidate = SettingsStore.value("displays", "primaryMonitor", "auto")
            return typeof candidate === "string"
                && /^(auto|[A-Za-z0-9._:-]+)$/.test(candidate)
                ? candidate : "auto"
        }
    }

    readonly property QtObject media: QtObject {
        readonly property bool enabled: SettingsStore.boolValue(
            "media", "enabled", true)
        readonly property bool preferPlaying: SettingsStore.boolValue(
            "media", "preferPlaying", true)
        readonly property int presentationTimeout: SettingsStore.numberValue(
            "media", "presentationTimeout", 4200, 2000, 10000)
        readonly property string hoverMode: {
            const candidate = SettingsStore.value("media", "hoverMode", "playing")
            return SettingsStore.validMediaHoverModes.indexOf(candidate) >= 0
                ? candidate : "playing"
        }
        readonly property int positionInterval: 1000

        // ---- lyrics in the resting pill ---------------------------------
        // Synced lines from LRCLIB. Per the design, the pill shows only the
        // meter and clock for the first lyricsRevealDelay ms of a song, then
        // widens and places the lyrics BETWEEN the meter and the clock.
        readonly property bool lyricsEnabled: SettingsStore.boolValue(
            "media", "lyricsEnabled", true)
        readonly property int lyricsRevealDelay: SettingsStore.numberValue(
            "media", "lyricsRevealDelay", 5000, 0, 30000)
        // A FIXED band: the pill must not resize on every line change.
        // Widened by a full design unit over the original 220 (Theme.u(5))
        // per owner feedback that the resting pill read too short with
        // lyrics on -- Theme.u(6) so it stays a whole-unit multiple.
        // Settable now (it was a hardcoded Theme.u(6) = 264px): on a
        // portrait monitor that band plus its gap made the resting pill
        // ~280px wider than the pill itself, which reads as an enormous bar
        // across the top of the screen. 4 units keeps a readable marquee at
        // a much smaller footprint; "media.lyricsBandWidth" in settings.json
        // takes any value from 2 to 8 units, and "media.lyricsEnabled":
        // false removes the band (and the extra width) entirely.
        readonly property int lyricsBandWidth: Theme.u(
            SettingsStore.numberValue("media", "lyricsBandUnits", 4, 2, 8))
        // The gutter between the lyric text and the clock that follows it.
        // Was a bare "6" (a leftover meter-gap value repurposed here); tuned
        // by measurement to a real, deliberate gap.
        readonly property int lyricsBandGap: Theme.u(0.36)
        // Show a line this far ahead of its timestamp, so it lands as it is
        // sung rather than just after.
        readonly property int lyricsLeadMs: 150
        readonly property int lyricsRequestTimeout: 8
    }

    readonly property QtObject clipboard: QtObject {
        readonly property int historyLimit: 100
        readonly property int width: root.island.expandedWidth
        readonly property int height: Math.round(440 * DisplayScale.primary)
        // Presentation-only limits. These are intentionally not user settings:
        // clipboard previews are sensitive, short-lived, and bounded.
        readonly property int previewLimit: 12
        readonly property int previewMaxBytes: 8 * 1024 * 1024
        readonly property int previewMaxDimension: 4096
        readonly property int previewMaxPixels: 16 * 1000 * 1000
        readonly property int thumbnailWidth: 160
        readonly property int thumbnailHeight: 100
    }

    readonly property QtObject session: QtObject {
        readonly property int width: root.island.expandedWidth
        readonly property int height: Math.round(440 * DisplayScale.primary)
        readonly property int shellClearDelay: 520
    }

    readonly property QtObject settings: QtObject {
        readonly property int width: root.island.expandedWidth
        readonly property int height: Math.round(500 * DisplayScale.primary)
    }

    readonly property QtObject wallpaper: QtObject {
        readonly property string backend: "awww"
        // ON by default (13 Sep 2026): the owner wants a chosen wallpaper to
        // actually persist across restarts on this rig, which means the shell
        // has to reconcile its saved wallpaper/monitor assignments into awww
        // on every launch, not just when the picker is used. The picker still
        // works the same way on top of this.
        readonly property bool manageOnStartup: SettingsStore.boolValue(
            "wallpaper", "manageOnStartup", true)
        readonly property string target: {
            const candidate = SettingsStore.value("wallpaper", "target", "all")
            return SettingsStore.validWallpaperTargets.indexOf(candidate) >= 0
                ? candidate : "all"
        }
        readonly property string scheme: {
            const candidate = SettingsStore.value("wallpaper", "scheme",
                "scheme-content")
            return SettingsStore.validSchemes.indexOf(candidate) >= 0
                ? candidate : "scheme-content"
        }
        readonly property var directories: [
            "wallpaper",
            "Pictures/Wallpapers",
            "Pictures/wallpapers"
        ]
        readonly property int width: root.island.expandedWidth
        readonly property int height: Math.round(440 * DisplayScale.primary)
        readonly property int galleryColumns: SettingsStore.numberValue(
            "wallpaper", "galleryColumns", 3, 2, 4)
        readonly property bool refreshOnOpen: SettingsStore.boolValue(
            "wallpaper", "refreshOnOpen", false)
        // Default false: on battery, hold the still frame instead of
        // decoding video -- the UHD 620 laptop is the reason this whole
        // pipeline exists, and idle video decode on battery is exactly the
        // drain it should avoid.
        readonly property bool videoOnBattery: SettingsStore.boolValue(
            "wallpaper", "videoOnBattery", false)
        // Cap encode/playback framerate for the transcoded proxy. Kept as a
        // setting (not a literal) since a 60Hz-only laptop panel gains
        // nothing from more.
        readonly property int videoMaxFps: SettingsStore.numberValue(
            "wallpaper", "videoMaxFps", 60, 15, 240)
        readonly property string transition: {
            const candidate = SettingsStore.value("wallpaper", "transition", "wave")
            return SettingsStore.validWallpaperTransitions.indexOf(candidate) >= 0
                ? candidate : "fade"
        }
        readonly property real transitionDuration: SettingsStore.numberValue(
            "wallpaper", "transitionDuration", 3.0, 0.3, 4.0)
        readonly property int cardHeight: 126
        readonly property string fitMode: "cover"
        // wallpaper.dither -- settings/SettingsWindow.qml's "Enable dither"
        // toggle read this straight off Config.wallpaper.dither, but no such
        // property existed here (every other wallpaper/* SettingsStore key
        // has one); it silently evaluated to undefined/false, so the switch
        // never reflected the real persisted/IPC-toggled state and re-
        // toggling it from the settings window would stomp the value right
        // back to false. shell.qml's own DitherWallpaper Loader already
        // reads SettingsStore.boolValue("wallpaper", "dither", false)
        // directly, so this just gives the settings UI the same live value.
        readonly property bool dither: SettingsStore.boolValue(
            "wallpaper", "dither", false)
        // Dither cell pitch in texel space (shaders/dither.frag `cellSize`),
        // not a Theme.unit-scaled UI size -- see DitherWallpaper.qml. Default
        // changed from the old ordered-dither-only 3.5 to DitherVeil's own
        // "pixelSize 2" default as part of the DitherVeil port -- 2px cells
        // read as crisp fine dots at the pattern's new higher default
        // levels/contrast instead of a coarse dot grid.
        readonly property real ditherDotSize: SettingsStore.numberValue(
            "wallpaper", "ditherDotSize", 2.0, 1.0, 8.0)
        // ---- DitherVeil port: pattern, grade, palette, reveal, edge -------
        // Dither pattern algorithm. bayer/noise/lines are computed live in
        // shaders/dither.frag from the two static baked textures
        // (wallpaper/textures/bayer8.png, noise64.png); floyd/atkinson are
        // CPU error-diffused per-wallpaper by tools/dither-bake.py (run via
        // Process on wallpaper/screen-size/setting change) into a cells
        // texture cached under ~/.local/cache/qml-rice/dither/ -- see
        // DitherWallpaper.qml's bake-management Process. Falls back to
        // "bayer" while a floyd/atkinson bake is missing or in flight.
        readonly property string ditherPattern: {
            const candidate = SettingsStore.value("wallpaper", "ditherPattern", "floyd")
            return ["bayer", "noise", "lines", "floyd", "atkinson"].indexOf(candidate) >= 0
                ? candidate : "floyd"
        }
        // Quantization levels per channel/luma bucket for the ordered
        // (bayer/noise) and diffused (floyd/atkinson) patterns. "lines" is
        // always a binary (2-level) threshold pattern regardless of this.
        // Default is 2 -- pure 1-bit ink/paper, matching the React Bits
        // DitherVeil default. The owner has explicitly complained before
        // about "grey-level dither dots vs pure white": with levels > 2 the
        // quantizer produces intermediate ink/paper blends (visible as grey
        // cells, not just black/white), which is exactly that complaint.
        readonly property int ditherLevels: SettingsStore.numberValue(
            "wallpaper", "ditherLevels", 2, 2, 8)
        // Pre-dither grade: pow(clamp((luma-0.5)*contrast+0.5+brightness,0,1), 1.6).
        readonly property real ditherContrast: SettingsStore.numberValue(
            "wallpaper", "ditherContrast", 1.0, 0.5, 2.0)
        readonly property real ditherBrightness: SettingsStore.numberValue(
            "wallpaper", "ditherBrightness", 0.0, -0.3, 0.3)
        // "duotone" mixes a single ink/paper pair by quantized level;
        // "rgb" quantizes each colour channel independently against the same
        // ordered-dither threshold, for a coloured dot pattern. Note: for the
        // floyd/atkinson patterns the CPU bake only diffuses luma (a 3-
        // channel bake would triple bake time/cache size for a effect this
        // subtle at typical wallpaper viewing distance) -- "rgb" with
        // floyd/atkinson falls back to the same single-channel level as
        // "duotone".
        readonly property string ditherPaletteMode: {
            const candidate = SettingsStore.value("wallpaper", "ditherPaletteMode", "duotone")
            return ["duotone", "rgb"].indexOf(candidate) >= 0 ? candidate : "duotone"
        }
        // Explicit hex overrides. Empty (default) derives ink/paper from
        // this shell's own Theme palette instead -- see DitherWallpaper.qml's
        // themeInk/themePaper (darkest Theme.surface/surfaceText pair, so it
        // reads correctly in both the dark and light Theme.dark modes).
        readonly property string ditherInk: {
            const candidate = SettingsStore.value("wallpaper", "ditherInk", "")
            return typeof candidate === "string"
                    && /^#[0-9a-fA-F]{6}$/.test(candidate) ? candidate : ""
        }
        readonly property string ditherPaper: {
            const candidate = SettingsStore.value("wallpaper", "ditherPaper", "")
            return typeof candidate === "string"
                    && /^#[0-9a-fA-F]{6}$/.test(candidate) ? candidate : ""
        }
        // Reveal mask geometry (shaders/trail.frag capsule stroke + hold band).
        // On-screen px radius around the cursor -- scaled like every other
        // island/media geometry literal in this file (see core/island's own
        // header comment) so the reveal circle keeps the same PHYSICAL size
        // on a high-PPI panel instead of reading smaller relative to the
        // pointer.
        readonly property real ditherRevealRadius: Math.round(SettingsStore.numberValue(
            "wallpaper", "ditherRevealRadius", 200, 50, 500) * DisplayScale.primary)
        readonly property real ditherSoftness: SettingsStore.numberValue(
            "wallpaper", "ditherSoftness", 0.6, 0.1, 1.0)
        readonly property real ditherLinger: SettingsStore.numberValue(
            "wallpaper", "ditherLinger", 1.0, 0.2, 3.0)
        // true shows the dithered pattern INSIDE the reveal and the photo
        // outside it (inverted "veil" look) instead of the default photo-
        // inside/dither-outside.
        readonly property bool ditherReverse: SettingsStore.boolValue(
            "wallpaper", "ditherReverse", false)
        // Dissolving rim band width (fraction of the bayer(cell.yx) order
        // spread) between the dither pattern and the full-colour reveal.
        // 0 (default) disables the rim entirely -- a hard dither/photo edge.
        readonly property real ditherRim: SettingsStore.numberValue(
            "wallpaper", "ditherRim", 0.0, 0.0, 0.3)
        // Empty (default) uses Theme.primary.
        readonly property string ditherRimColor: {
            const candidate = SettingsStore.value("wallpaper", "ditherRimColor", "")
            return typeof candidate === "string"
                    && /^#[0-9a-fA-F]{6}$/.test(candidate) ? candidate : ""
        }
        // Idle UV-warp ripple toggle (shaders/dither.frag `waveOn`).
        readonly property bool ditherWave: SettingsStore.boolValue(
            "wallpaper", "ditherWave", true)
        // Levels black point (shaders/dither.frag `blackPoint`) applied
        // before dithering -- source luminance at/below this maps to 0, so
        // JPEG-grain "black" dithers to flat ink instead of a visible dot
        // grid. 0.12 tuned by eye against dither-hands.jpg's background.
        readonly property real ditherBlackPoint: SettingsStore.numberValue(
            "wallpaper", "ditherBlackPoint", 0.12, 0.0, 0.5)
        // Overrides the awww-managed wallpaper for the dither effect only
        // when explicitly set by the user. Default is "" -- unset means the
        // dither layer shows WallpaperService.currentStill (the applied
        // wallpaper), same as awww underneath it. Defaulting this to a
        // fixed image (previously dither-hands.jpg) meant every screen
        // showed that image forever instead of whatever the user applied.
        readonly property string ditherImage: {
            const stored = SettingsStore.value("wallpaper", "ditherImage", "")
            return typeof stored === "string" ? stored : ""
        }
        // Looping liquid-warp domain displacement on the wallpaper (shaders/warp.frag).
        // Enabled by default; when off, the warp ShaderEffect is not rendered.
        readonly property bool warp: SettingsStore.boolValue(
            "wallpaper", "warp", true)
        // Warp UV displacement amplitude as a fraction of screen dimension.
        // Typical: 0.006 (~0.6% at 1920px width, ~12px absolute displacement).
        // Higher values create more dramatic warping (keep <= 0.02 to avoid obvious distortion).
        readonly property real warpStrength: SettingsStore.numberValue(
            "wallpaper", "warpStrength", 0.006, 0.001, 0.02)
        // Warp animation speed/frequency. 1.0 is the default ~30s loop period.
        readonly property real warpSpeed: SettingsStore.numberValue(
            "wallpaper", "warpSpeed", 1.0, 0.2, 3.0)
    }

    // Bottom-edge cava "rollercoaster track" visualizer -- see
    // visualizer/EdgeVisualizer.qml. On by default; edgeHeight is a ratio
    // of screen height (0.09 ~= a slim band, not a takeover of the bottom
    // of the desktop).
    readonly property QtObject visualizer: QtObject {
        readonly property bool edge: SettingsStore.boolValue(
            "visualizer", "edge", true)
        readonly property real edgeHeight: SettingsStore.numberValue(
            "visualizer", "edgeHeight", 0.09, 0.03, 0.3)
    }

    readonly property QtObject weather: QtObject {
        readonly property bool enabled: true
        readonly property string provider: "open-meteo"
        readonly property string locationName: {
            const candidate = SettingsStore.value("weather", "locationName", "")
            return typeof candidate === "string" ? candidate.trim() : ""
        }
        readonly property real latitude: coordinate("latitude", -90, 90)
        readonly property real longitude: coordinate("longitude", -180, 180)
        readonly property string temperatureUnit: "celsius"
        readonly property int refreshInterval: 1200000
        readonly property int requestTimeout: 8
        readonly property int headerSlotWidth: 56

        function coordinate(key: string, minimum: real, maximum: real): real {
            const stored = SettingsStore.value("weather", key, "")
            if ((typeof stored !== "number" && typeof stored !== "string")
                    || (typeof stored === "string" && stored.trim().length === 0))
                return NaN
            const numeric = Number(stored)
            return Number.isFinite(numeric) && numeric >= minimum
                && numeric <= maximum ? numeric : NaN
        }
    }

    readonly property QtObject glass: QtObject {
        // true only when the owner has loaded the qmlrice-glass Hyprland
        // plugin (tools/glass-plugin) and enabled it. The compositor then draws
        // the real rim refraction + specular behind the matching layer surfaces,
        // and TahoeGlass should drop its faked rim and keep just the light tint.
        // Default false: without the plugin the shell must paint its own rim.
        readonly property bool compositor: SettingsStore.boolValue(
            "glass", "compositor", false)
    }

    readonly property QtObject ai: QtObject {
        readonly property bool enabled: false
        readonly property string provider: ""
        readonly property string model: ""
        readonly property string endpoint: ""
    }
}
