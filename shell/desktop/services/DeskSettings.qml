// Desktop settings singleton
// Stores desktop widget configuration and theme preferences in the shell's
// own state-dir JSON convention (see core/SettingsStore.qml,
// services/WidgetStore.qml), in its own file so it never collides with
// either of those.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Same env-var-first resolution as services/WidgetStore.qml: NOT
    // StandardPaths.GenericStateLocation (that's core/SettingsStore's own
    // "odyssey/settings.json" file, a different store entirely).
    readonly property string stateDirectory:
        (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
        + "/qml-rice"

    // Desktop widget layout: array of { id, key, col, row, family, theme?, style?, opacity? }
    // or { id, key, edge, notes } for deck entries
    readonly property alias desktopWidgets: config.desktopWidgets

    // Theme: "modern" or "analogue"
    readonly property alias desktopTheme: config.desktopTheme

    // Style: how widget capsules are drawn ("capsule", "outline", "bare", "accent")
    readonly property alias desktopStyle: config.desktopStyle

    // Opacity in percent, desktop default
    readonly property alias desktopOpacity: config.desktopOpacity

    // Clock face format (impasto's own setting, distinct from the shell's
    // island clock -- desktop clock widgets can show seconds/format
    // independently of the bar).
    readonly property alias clockFormat: config.clockFormat
    readonly property alias clockShowsSeconds: config.clockShowsSeconds

    // Notes deck: hide it unless the active workspace has no windows.
    readonly property alias deckOnEmpty: config.deckOnEmpty

    // GitHub contributions module: a public username, opt-in (empty by
    // default so DeskGithubService.available stays false until set).
    readonly property alias githubUser: config.githubUser

    // impasto's greeting scene id ("lava"|"critters"|"koi"|"invaders"|
    // "random"|"none"), ported here per the impasto-settings-full brief so
    // a separate lock/greeting branch has a stable key to read. This shell
    // has no renderer wired to it yet (see settings-impasto/components/
    // GreetingPreview.qml's header) -- this property only records the
    // choice. Default "none": unlike upstream impasto (default "random"),
    // nothing in this shell paints a greeting scene until that renderer
    // lands, so defaulting to an active scene would silently promise a
    // feature this branch doesn't deliver.
    readonly property var validGreetingScenes:
        ["lava", "critters", "koi", "invaders", "random", "none"]
    readonly property alias greetingScene: config.greetingScene
    function setGreetingScene(scene: string): bool {
        if (validGreetingScenes.indexOf(scene) < 0)
            return false
        config.greetingScene = scene
        return true
    }

    // Pinned ("kept") launcher application ids, ported from impasto's own
    // dock-owned pin list (services/DockService.qml's `pinned`) since this
    // shell has no dock to own one -- see settings-impasto/sections/
    // LauncherSection.qml's own header. Ids match
    // ApplicationService.applications[].id (DesktopEntries' own id).
    readonly property alias pinnedLauncherApps: config.pinnedLauncherApps
    function isPinnedLauncherApp(id: string): bool {
        return config.pinnedLauncherApps.indexOf(id) >= 0
    }
    function addPinnedLauncherApp(id: string): void {
        if (!id || root.isPinnedLauncherApp(id))
            return
        config.pinnedLauncherApps = config.pinnedLauncherApps.concat([id])
    }
    function removePinnedLauncherApp(id: string): void {
        config.pinnedLauncherApps = config.pinnedLauncherApps.filter(
            entry => entry !== id)
    }

    // Which Hyprland window-open/close animation curve is applied via
    // `hyprctl keyword bezier`/`animation` (see settings-impasto/sections/
    // AppearanceSection.qml's Motion tab and desktop/services/
    // DeskHyprctlService.qml). Runtime-only, like every other
    // DeskHyprctlService write -- reverts on the next `hyprctl reload`
    // unless a Lua module also sets it, which this port does not do.
    readonly property var validWindowAnimationPresets:
        ["smooth", "snappy", "springy", "slide", "none"]
    readonly property alias windowAnimationPreset: config.windowAnimationPreset
    function setWindowAnimationPreset(preset: string): bool {
        if (validWindowAnimationPresets.indexOf(preset) < 0)
            return false
        config.windowAnimationPreset = preset
        return true
    }

    // Keyboard/pointer settings, applied live via `hyprctl keyword
    // input:...` (DeskHyprctlService.qml) and persisted here so the value
    // survives a shell restart, though (like every DeskHyprctlService
    // write) it reverts to hypr/modules/input.lua's own default on the
    // next `hyprctl reload` -- this port does not touch that Lua module.
    // See settings-impasto/sections/InputSection.qml.
    readonly property alias inputKbLayout: config.inputKbLayout
    function setInputKbLayout(layout: string): bool {
        if (typeof layout !== "string" || layout.trim() === "")
            return false
        config.inputKbLayout = layout.trim()
        return true
    }

    readonly property var validInputKbOptions:
        ["", "grp:alt_shift_toggle", "grp:win_space_toggle", "grp:caps_toggle"]
    readonly property alias inputKbOptions: config.inputKbOptions
    function setInputKbOptions(options: string): bool {
        if (validInputKbOptions.indexOf(options) < 0)
            return false
        config.inputKbOptions = options
        return true
    }

    readonly property alias inputRepeatRate: config.inputRepeatRate
    function setInputRepeatRate(rate: real): bool {
        const numeric = Number(rate)
        if (!Number.isFinite(numeric))
            return false
        config.inputRepeatRate = Math.round(Math.max(10, Math.min(60, numeric)))
        return true
    }

    readonly property alias inputSensitivity: config.inputSensitivity
    function setInputSensitivity(value: real): bool {
        const numeric = Number(value)
        if (!Number.isFinite(numeric))
            return false
        config.inputSensitivity = Math.max(-1, Math.min(1, numeric))
        return true
    }

    readonly property alias inputCursorSize: config.inputCursorSize
    function setInputCursorSize(size: real): bool {
        const numeric = Number(size)
        if (!Number.isFinite(numeric))
            return false
        config.inputCursorSize = Math.round(Math.max(16, Math.min(48, numeric)))
        return true
    }

    // Window decoration, applied live via `hyprctl keyword decoration:.../
    // general:...` (DeskHyprctlService.qml) and persisted here -- same
    // runtime-only, reverts-on-reload contract as every other
    // DeskHyprctlService write. See settings-impasto/sections/
    // AppearanceSection.qml's Windows tab.
    readonly property alias windowRounding: config.windowRounding
    function setWindowRounding(px: real): bool {
        const numeric = Number(px)
        if (!Number.isFinite(numeric))
            return false
        config.windowRounding = Math.round(Math.max(0, Math.min(30, numeric)))
        return true
    }

    readonly property alias windowBorderWidth: config.windowBorderWidth
    function setWindowBorderWidth(px: real): bool {
        const numeric = Number(px)
        if (!Number.isFinite(numeric))
            return false
        config.windowBorderWidth = Math.round(Math.max(0, Math.min(6, numeric)))
        return true
    }

    readonly property alias windowGapsIn: config.windowGapsIn
    function setWindowGapsIn(px: real): bool {
        const numeric = Number(px)
        if (!Number.isFinite(numeric))
            return false
        config.windowGapsIn = Math.round(Math.max(0, Math.min(30, numeric)))
        return true
    }

    readonly property alias windowGapsOut: config.windowGapsOut
    function setWindowGapsOut(px: real): bool {
        const numeric = Number(px)
        if (!Number.isFinite(numeric))
            return false
        config.windowGapsOut = Math.round(Math.max(0, Math.min(40, numeric)))
        return true
    }

    readonly property alias windowInactiveOpacity: config.windowInactiveOpacity
    function setWindowInactiveOpacity(value: real): bool {
        const numeric = Number(value)
        if (!Number.isFinite(numeric))
            return false
        config.windowInactiveOpacity = Math.max(0.3, Math.min(1, numeric))
        return true
    }

    readonly property alias windowBlurSize: config.windowBlurSize
    function setWindowBlurSize(px: real): bool {
        const numeric = Number(px)
        if (!Number.isFinite(numeric))
            return false
        config.windowBlurSize = Math.round(Math.max(0, Math.min(20, numeric)))
        return true
    }

    // Feature gate read by shell.qml: true instantiates the impasto Desktop
    // (this port) per screen and skips the legacy widgets/WidgetLayer;
    // false keeps the old Pixel-style layer and never creates a Desktop at
    // all. Defaults on -- this replaces WidgetLayer as the default desktop,
    // per the port's brief -- but stays a one-line settings.json edit
    // ("desktopEnabled": false) to fall back without a rebuild.
    readonly property alias enabled: config.desktopEnabled

    // Feature gate read by island/IslandExpanded.qml: true swaps the
    // dashboard/ (impasto island control-centre) port in as the "overview"
    // page's content instead of the shell's original panels/Dashboard.qml.
    // Defaults on per the dashboard port's brief, but stays a one-line
    // settings.json edit ("dashboardImpasto": false) to fall back without a
    // rebuild -- panels/Dashboard.qml and its DashboardHeroRow/QuickStrip/
    // MediaCard/SystemCard siblings are untouched either way.
    readonly property alias dashboardImpasto: config.dashboardImpasto

    // Feature gate read by island/IslandController.qml and
    // island/IslandExpanded.qml: true opens impasto's own per-module detail
    // cards (island/cards/) as dedicated island states -- reached via
    // entry-point taps (media/Wi-Fi/Bluetooth/battery/clock, see
    // island/IslandHover.qml and island/IslandDormant.qml) or the
    // `island card <name>` IPC target (core/ShellActions.qml) -- instead of
    // the old satellite popouts and dashboard tabs. This is purely about
    // which CONTENT the island's existing surface hosts: the island's own
    // shape, position and morph are unchanged (this shell is not impasto's
    // notch -- see HANDOVER.md). Defaults on, but stays a one-line
    // settings.json edit ("islandImpastoCards": false) to fall back to the
    // pre-existing satellites/dashboard-only entry points with no rebuild --
    // neither those files nor the cards are deleted by this gate.
    readonly property alias islandImpastoCards: config.islandImpastoCards

    // Feature gate read by dashboard/DashControlsPanel.qml: true hosts
    // impasto's own freeform draggable/resizable control-centre block grid
    // (dashboard/services/DashBlocksService.qml + dashboard/controls/
    // {Block,BlockFace,BlockInspector,ControlsTray}.qml, ported verbatim from
    // bar/island/{ControlsPanel,controls/*}.qml) instead of the earlier
    // fixed scrolling column. Defaults on per this port's brief, but stays a
    // one-line settings.json edit ("dashboardBlockGrid": false) to fall back
    // to the fixed column with no rebuild -- DashControlsPanel keeps both
    // paths.
    readonly property alias dashboardBlockGrid: config.dashboardBlockGrid

    // Control-centre block grid layout: array of { key, id, col, row, size,
    // toggles? } rows, same shape as impasto's own `centreBlocks` setting.
    // Absent (null) means "use the shipped default layout" -- see
    // DashBlocksService.qml's `defaultBlocks` -- so catalogue additions
    // reach anyone who never customised it.
    readonly property alias dashboardBlocks: config.dashboardBlocks

    // Feature gate read by lock/LockScreen.qml: true swaps in impasto's own
    // lock-screen visual (lock/ImpastoLockSurface.qml -- blurred desktop,
    // clock, avatar, password pill, power row) instead of this shell's
    // pre-existing lock/LockSurface.qml (quote-diffusion + island-pill-fly
    // unlock choreography). Bound to the SAME lock/LockContext.qml/PAM path
    // either way -- this gate only swaps which Item draws the surface, via
    // a Loader that falls back to the classic surface on any load error
    // (see LockScreen.qml's `surfaceLoader`). Defaults on per this port's
    // brief, but stays a one-line settings.json edit ("lockImpasto": false)
    // to fall back with no rebuild. SUPERSEDED by lockStyle below -- kept
    // only so old settings.json files with this key still parse; nothing
    // reads it for routing anymore (see lockStyle's own comment).
    readonly property alias lockImpasto: config.lockImpasto

    // Which per-screen lock surface lock/LockScreen.qml's Loader loads:
    // "glass" (default since 6 Oct 2026 -- lock/GlassLockSurface.qml, the
    // liquid-glass surface with the 3D clock) | "ascii"
    // (lock/AsciiLockSurface.qml, the waving-ASCII-clock
    // surface built on ReactBits' ASCIIText effect) | "classic"
    // (lock/LockSurface.qml, the pre-existing quote-diffusion + island-pill
    // choreography) | "impasto" (lock/ImpastoLockSurface.qml, the blurred-
    // desktop-screenshot port this replaces by default per the owner's "we
    // need to stop using impastos"). Deliberately a plain string, not a
    // bool, now that there are three surfaces instead of two -- and it
    // alone decides routing: the legacy `lockImpasto` bool above is never
    // consulted, even if some old settings.json still has it set true, so
    // there is exactly one source of truth for which surface loads.
    readonly property alias lockStyle: config.lockStyle
    // Control-centre top-row door ids, left to right (impasto's own
    // SettingsService.centreButtons). Absent (null) means "use
    // DashBlocksService.defaultButtons" -- see that file's `doors`
    // catalogue.
    readonly property alias dashboardDoors: config.dashboardDoors

    // State
    property bool arrived: false

    // ── STORAGE ─────────────────────────────────────────────────────────────

    readonly property FileView file: FileView {
        path: `${root.stateDirectory}/desktop.json`
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        printErrors: false

        onFileChanged: reload()
        onAdapterUpdated: saver.restart()
        onLoaded: root.arrived = true
        onLoadFailed: error => {
            root.arrived = true
            if (error !== FileViewError.FileNotFound)
                console.warn("qml-rice DeskSettings:", FileViewError.toString(error))
        }
        onSaveFailed: error => console.warn("qml-rice DeskSettings:",
            FileViewError.toString(error))

        // Debounced write: several mutations in one drag/resize coalesce
        // into a single disk write. Callers that need a tighter debounce
        // (e.g. DeskDesktopService's own 120ms coalescing timer around
        // desktopWidgets) restart their own timer and call set() once;
        // this one just guarantees the *file* write itself isn't
        // one-syscall-per-property-set.
        readonly property Timer saver: Timer {
            interval: 150
            onTriggered: root.file.writeAdapter()
        }

        Store {
            id: config
        }
    }

    // ── API ──────────────────────────────────────────────────────────────────

    function set(key: string, value: var): void {
        if (key in config)
            config[key] = value
    }

    // ── SCHEMA ──────────────────────────────────────────────────────────────

    component Store: JsonAdapter {
        property bool desktopEnabled: true
        property var desktopWidgets: []
        property string desktopTheme: "modern"
        property string desktopStyle: "capsule"
        property int desktopOpacity: 100
        property string clockFormat: "hh:mm"
        property bool deckOnEmpty: false
        property bool clockShowsSeconds: false
        property string githubUser: ""
        property bool dashboardImpasto: true
        property bool islandImpastoCards: true
        property bool dashboardBlockGrid: true
        property var dashboardBlocks: null
        property bool lockImpasto: true
        property string lockStyle: "glass"
        property var dashboardDoors: null
        property string greetingScene: "none"
        property string windowAnimationPreset: "smooth"
        property string inputKbLayout: "us"
        property string inputKbOptions: ""
        property int inputRepeatRate: 25
        property real inputSensitivity: 0
        property int inputCursorSize: 24
        property int windowRounding: 10
        property int windowBorderWidth: 2
        property int windowGapsIn: 5
        property int windowGapsOut: 10
        property real windowInactiveOpacity: 1
        property int windowBlurSize: 6
        property var pinnedLauncherApps: []
    }
}
