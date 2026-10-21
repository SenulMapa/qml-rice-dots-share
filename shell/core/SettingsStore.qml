pragma Singleton
import QtCore
import QtQuick
import Quickshell.Io
import "../mac/MacFormat.js" as Format

QtObject {
    id: root

    property var values: ({})
    property bool loaded: false
    property string errorMessage: ""

    readonly property var validModes: ["auto", "dark", "light"]
    readonly property var validSchemes: [
        "scheme-content", "scheme-tonal-spot", "scheme-vibrant",
        "scheme-monochrome", "scheme-expressive", "scheme-fidelity",
        "scheme-fruit-salad", "scheme-neutral", "scheme-rainbow"
    ]
    readonly property var validMotionSpeeds: ["quick", "balanced", "calm"]
    readonly property var validDensities: ["compact", "balanced", "airy"]
    readonly property var validCornerStyles: ["subtle", "balanced", "round"]
    readonly property var validMediaHoverModes: ["hidden", "playing", "available"]
    readonly property var validWallpaperTargets: ["current", "all"]
    readonly property var validSatelliteJoinModes: ["joined", "separate"]
    // impasto's transition set (Fade/Wipe/Wave/Circle/Outer/None/Random) maps
    // onto this shell's own naming: expand === Circle (awww 'center', itself
    // an alias for a growing circle), contract === Outer. 'slide' and
    // 'spotlight' are this shell's own additions with no impasto equivalent.
    // 'none' was added porting impasto's "None" -- previously only reachable
    // here via the reduced-motion flag, not as a user-selectable transition.
    readonly property var validWallpaperTransitions: [
        "fade", "slide", "wipe", "wave", "expand", "contract",
        "spotlight", "random",
        // "grow"/"outer"/"none" added for the impasto settings port's
        // WallpaperTransitionPreview tiles (settings-impasto/components):
        // awww's own transition-type vocabulary, distinct from this list's
        // pre-existing renamed set above (which predates that port and stays
        // for back-compat -- "contract" already equals "outer" in
        // scripts/wallpaperctl.sh's effect_args(), "expand" already equals
        // awww's "center" alias of "grow"). "grow" is awww's real growing-
        // circle type (impasto calls the same effect "circle").
        "grow", "outer", "none"
    ]
    readonly property var validIslandPolicies: ["all", "primary"]
    readonly property var validCommandHistorySources: ["auto", "zsh", "bash", "fish"]
    readonly property var validCommandTerminals: [
        "auto", "kitty", "foot", "alacritty", "ghostty"
    ]
    readonly property var validPerformanceTiers: ["auto", "low", "high"]
    // Presentation layer (spec 2026-10-19-mac-style-design.md section 2).
    // "pill" is the ink island and the default; "mac" is the Tahoe style.
    readonly property var validUiStyles: ["pill", "mac"]
    // Font-family SETTING keys this store will accept via setFontFamily().
    // Values themselves are an open (not hardcoded) domain -- validated
    // dynamically against Qt.fontFamilies() below, since the installed font
    // set differs per machine and can't be enumerated as a fixed list the
    // way a mode/scheme/tier can.
    readonly property var validFontFamilyKeys: [
        "fontFamily", "monoFontFamily", "clockFontFamily", "handFontFamily"
    ]
    readonly property var validRestIslandItems: [
        "Weather", "Dnd", "KeepAwake", "PowerProfile"
    ]
    // Also the default hover order: media left of the centred clock, status
    // to its right -- the proto's three zones (art + title | clock + date |
    // status). IslandHover anchors the clock to the pill centre and hangs
    // everything before/after it off its edges.
    readonly property var validHoverIslandItems: [
        "Media", "Clock", "Workspaces", "Audio", "Network", "Dnd",
        "Bluetooth", "KeepAwake", "Battery"
    ]
    // The hover pill's actual DEFAULT set. Workspaces/Audio/Dnd/KeepAwake stay
    // valid above (the order editor can still add them back), but the
    // redesigned hover reads art+title | clock | one status capsule -- not a
    // strip of nine icons -- so they no longer ship on by default.
    readonly property var defaultHoverIslandItems: [
        "Media", "Clock", "Network", "Battery", "Bluetooth"
    ]

    function value(section: string, key: string, fallback): var {
        const group = values?.[section]
        return group && group[key] !== undefined ? group[key] : fallback
    }

    function boolValue(section: string, key: string, fallback: bool): bool {
        const stored = value(section, key, fallback)
        return typeof stored === "boolean" ? stored : fallback
    }

    function numberValue(section: string, key: string, fallback: real,
            minimum: real, maximum: real): real {
        const stored = Number(value(section, key, fallback))
        return Number.isFinite(stored)
            ? Math.max(minimum, Math.min(maximum, stored)) : fallback
    }

    function stringListValue(section: string, key: string, fallback,
            allowedValues): var {
        const stored = value(section, key, fallback)
        if (!Array.isArray(stored))
            return fallback.slice()
        const result = []
        for (const candidate of stored) {
            if (typeof candidate === "string"
                    && allowedValues.indexOf(candidate) >= 0
                    && result.indexOf(candidate) < 0)
                result.push(candidate)
        }
        return result
    }

    function setValue(section: string, key: string, nextValue): void {
        const updated = JSON.parse(JSON.stringify(values || {}))
        if (!updated[section] || typeof updated[section] !== "object")
            updated[section] = {}
        updated[section][key] = nextValue
        values = updated
        save()
    }

    function removeValue(section: string, key: string): void {
        const updated = JSON.parse(JSON.stringify(values || {}))
        if (!updated[section] || updated[section][key] === undefined)
            return
        delete updated[section][key]
        if (Object.keys(updated[section]).length === 0)
            delete updated[section]
        values = updated
        save()
    }

    function setValidatedValue(section: string, key: string, nextValue,
            allowedValues): bool {
        if (allowedValues.indexOf(nextValue) < 0)
            return false
        setValue(section, key, nextValue)
        return true
    }

    // Generic bounded-string setter/getter pair -- for settings whose valid
    // domain isn't a small fixed enum (setValidatedValue) but also isn't
    // free text that needs no validation at all. Trims, rejects empty/
    // oversized/control-character input.
    function setStringValue(section: string, key: string, nextValue: string,
            maxLength: int): bool {
        if (typeof nextValue !== "string")
            return false
        const trimmed = nextValue.trim()
        if (trimmed.length === 0 || trimmed.length > maxLength
                || /[\x00-\x1f\x7f]/.test(trimmed))
            return false
        setValue(section, key, trimmed)
        return true
    }

    function stringValue(section: string, key: string, fallback: string,
            maxLength: int): string {
        const stored = value(section, key, fallback)
        return typeof stored === "string" && stored.length > 0
                && stored.length <= maxLength
            ? stored : fallback
    }

    function setAppearanceMode(mode: string): bool {
        if (validModes.indexOf(mode) < 0)
            return false
        setValue("appearance", "mode", mode)
        return true
    }

    function setSurfaceOpacity(opacity: real): void {
        setValue("appearance", "surfaceOpacity",
            Math.round(Math.max(0.72, Math.min(1, opacity)) * 100) / 100)
    }

    function setAccentOverride(color: string): bool {
        if (typeof color !== "string"
                || !/^#[0-9a-fA-F]{6}$/.test(color))
            return false
        setValue("appearance", "accentOverride", color.toLowerCase())
        return true
    }

    function clearAccentOverride(): void {
        removeValue("appearance", "accentOverride")
    }

    function setReducedMotion(enabled: bool): void {
        setValue("appearance", "reducedMotion", enabled)
    }

    // Ink redesign switch (Config.appearance.ink); false restores the glass look.
    function setInk(enabled: bool): void {
        setValue("appearance", "ink", enabled)
    }

    function setMotionSpeed(speed: string): bool {
        return setValidatedValue("appearance", "motionSpeed", speed,
            validMotionSpeeds)
    }

    function setMotionScale(scale: real): void {
        const numeric = Number(scale)
        if (!Number.isFinite(numeric))
            return
        setValue("motion", "scale",
            Math.round(Math.max(0.8, Math.min(1.2, numeric)) * 100) / 100)
    }

    function setDensity(density: string): bool {
        return setValidatedValue("appearance", "density", density,
            validDensities)
    }

    function setCornerStyle(style: string): bool {
        return setValidatedValue("appearance", "cornerStyle", style,
            validCornerStyles)
    }

    function setClock24Hour(enabled: bool): void {
        setValue("appearance", "use24HourClock", enabled)
    }

    // Font pickers (Settings > Appearance): clock/UI/mono/handwriting.
    // Validated against Qt.fontFamilies() -- the installed set -- rather
    // than a hardcoded list, since that differs per machine.
    function setFontFamily(key: string, family: string): bool {
        if (validFontFamilyKeys.indexOf(key) < 0)
            return false
        if (typeof family !== "string" || family.length === 0
                || family.length > 128)
            return false
        if (Qt.fontFamilies().indexOf(family) < 0)
            return false
        setValue("appearance", key, family)
        return true
    }

    function fontFamilyValue(key: string, fallback: string): string {
        if (validFontFamilyKeys.indexOf(key) < 0)
            return fallback
        const candidate = value("appearance", key, fallback)
        if (typeof candidate !== "string" || candidate.length === 0)
            return fallback
        return Qt.fontFamilies().indexOf(candidate) >= 0 ? candidate : fallback
    }

    function setFontScale(scale: real): void {
        const numeric = Number(scale)
        if (!Number.isFinite(numeric))
            return
        setValue("appearance", "fontScale",
            Math.round(Math.max(0.8, Math.min(1.3, numeric)) * 100) / 100)
    }

    function setDisplayScale(scale: real): void {
        const numeric = Number(scale)
        if (!Number.isFinite(numeric))
            return
        // 0 stays reachable as the "auto" sentinel (the settings toggle's
        // Auto option); any other value is the manual override, bounded to
        // the slider's own 1.0-2.0 range.
        setValue("appearance", "displayScale",
            numeric <= 0 ? 0
                : Math.round(Math.max(1.0, Math.min(2.0, numeric)) * 100) / 100)
    }

    function setPerformanceTierOverride(tier: string): bool {
        return setValidatedValue("appearance", "performanceTierOverride",
            tier, validPerformanceTiers)
    }

    function setIslandMetric(metric: string, nextValue: real): bool {
        const bounds = ({
            topMargin: [0, 16], reservedSpace: [26, 52],
            dormantWidth: [96, 320], hoverWidth: [470, 760],
            expandedWidth: [620, 900], restItemSpacing: [2, 18],
            hoverItemSpacing: [2, 20], autoHideDelay: [500, 10000]
        })
        const range = bounds[metric]
        const numeric = Number(nextValue)
        if (!range || !Number.isFinite(numeric))
            return false
        setValue("island", metric,
            Math.round(Math.max(range[0], Math.min(range[1], numeric))))
        return true
    }

    function setIslandItemVisible(context: string, item: string,
            enabled: bool): bool {
        const allowed = context === "rest" ? validRestIslandItems
            : context === "hover" ? validHoverIslandItems : []
        if (allowed.indexOf(item) < 0)
            return false
        const fallback = context === "rest" ? validRestIslandItems
            : defaultHoverIslandItems
        const current = stringListValue("island", context + "ItemOrder",
            fallback, allowed)
        const next = current.filter(candidate => candidate !== item)
        if (enabled)
            next.push(item)
        return setIslandItemOrder(context, next)
    }

    function setIslandItemOrder(context: string, order): bool {
        const allowed = context === "rest" ? validRestIslandItems
            : context === "hover" ? validHoverIslandItems : []
        if (!Array.isArray(order) || allowed.length === 0)
            return false
        const validated = []
        for (const candidate of order) {
            if (typeof candidate !== "string"
                    || allowed.indexOf(candidate) < 0
                    || validated.indexOf(candidate) >= 0)
                return false
            validated.push(candidate)
        }
        setValue("island", context + "ItemOrder", validated)
        return true
    }

    function setIslandAutoHide(enabled: bool): void {
        setValue("island", "autoHide", enabled)
    }

    function setIslandRevealLip(enabled: bool): void {
        setValue("island", "showRevealLip", enabled)
    }

    function setIslandSatelliteJoin(mode: string): bool {
        return setValidatedValue("island", "satelliteJoin", mode,
            validSatelliteJoinModes)
    }

    // Added for the impasto-settings-full port's island/pill settings tab
    // (settings-impasto/sections/IslandSection.qml): Config.island.
    // hideInFullscreen was a hardcoded `true`, not a stored value, matching
    // every other island/* setting's own SettingsStore.boolValue pattern.
    function setIslandHideInFullscreen(enabled: bool): void {
        setValue("island", "hideInFullscreen", enabled)
    }

    function setIslandContentSync(context: string, enabled: bool): bool {
        if (["rest", "hover"].indexOf(context) < 0)
            return false
        const textKey = context + "TextScale"
        const iconKey = context + "IconScale"
        const updated = JSON.parse(JSON.stringify(values || {}))
        if (!updated.island || typeof updated.island !== "object")
            updated.island = {}
        updated.island[context + "ScaleSynced"] = enabled
        if (enabled) {
            const shared = numberValue("island", textKey, 100, 80, 130)
            updated.island[textKey] = shared
            updated.island[iconKey] = shared
        }
        values = updated
        save()
        return true
    }

    function setIslandContentScale(context: string, channel: string,
            percentage: real): bool {
        if (["rest", "hover"].indexOf(context) < 0
                || ["text", "icon"].indexOf(channel) < 0)
            return false
        const numeric = Number(percentage)
        if (!Number.isFinite(numeric))
            return false
        const bounded = Math.round(Math.max(80, Math.min(130, numeric)))
        const updated = JSON.parse(JSON.stringify(values || {}))
        if (!updated.island || typeof updated.island !== "object")
            updated.island = {}
        updated.island[context + (channel === "text"
            ? "TextScale" : "IconScale")] = bounded
        if (boolValue("island", context + "ScaleSynced", true))
            updated.island[context + (channel === "text"
                ? "IconScale" : "TextScale")] = bounded
        values = updated
        save()
        return true
    }

    function resetIslandAndMotion(): void {
        const updated = JSON.parse(JSON.stringify(values || {}))
        delete updated.island
        if (updated.appearance) {
            delete updated.appearance.motionSpeed
            delete updated.appearance.density
            delete updated.appearance.cornerStyle
            delete updated.appearance.reducedMotion
            if (Object.keys(updated.appearance).length === 0)
                delete updated.appearance
        }
        values = updated
        save()
    }

    function setPowerSoundsEnabled(enabled: bool): void {
        setValue("idle", "powerSoundsEnabled", enabled)
    }

    function setIdleScreenOffTimeout(minutes: real): bool {
        const numeric = Number(minutes)
        if (!Number.isFinite(numeric))
            return false
        setValue("idle", "screenOffTimeoutMinutes",
            Math.round(Math.max(0, Math.min(60, numeric))))
        return true
    }

    function setIdleLockTimeout(minutes: real): bool {
        const numeric = Number(minutes)
        if (!Number.isFinite(numeric))
            return false
        setValue("idle", "lockTimeoutMinutes",
            Math.round(Math.max(0, Math.min(120, numeric))))
        return true
    }

    function setIdleSuspendTimeout(minutes: real): bool {
        const numeric = Number(minutes)
        if (!Number.isFinite(numeric))
            return false
        setValue("idle", "suspendTimeoutMinutes",
            Math.round(Math.max(0, Math.min(240, numeric))))
        return true
    }

    function setIslandMonitorPolicy(policy: string): bool {
        return setValidatedValue("displays", "islandPolicy", policy,
            validIslandPolicies)
    }

    function setPrimaryMonitor(monitorName: string): bool {
        if (typeof monitorName !== "string"
                || !/^(auto|[A-Za-z0-9._:-]+)$/.test(monitorName))
            return false
        setValue("displays", "primaryMonitor", monitorName)
        return true
    }

    function resetDisplays(): void {
        resetSection("displays")
    }

    function setNotificationToggle(key: string, enabled: bool): bool {
        if (["showPopups", "allowCriticalAlerts", "doNotDisturb"]
                .indexOf(key) < 0)
            return false
        setValue("notifications", key, enabled)
        return true
    }

    function setNotificationDuration(key: string, milliseconds: real): bool {
        const bounds = ({ timeout: [2000, 10000], criticalTimeout: [4000, 15000] })
        const range = bounds[key]
        const numeric = Number(milliseconds)
        if (!range || !Number.isFinite(numeric))
            return false
        setValue("notifications", key, Math.round(Math.max(range[0],
            Math.min(range[1], numeric)) / 1000) * 1000)
        return true
    }

    function setNotificationHistoryLimit(limit: real): bool {
        const numeric = Number(limit)
        if (!Number.isFinite(numeric))
            return false
        setValue("notifications", "historyLimit",
            Math.round(Math.max(20, Math.min(100, numeric))))
        return true
    }

    function resetNotifications(): void {
        resetSection("notifications")
    }

    function setMediaToggle(key: string, enabled: bool): bool {
        if (["enabled", "preferPlaying"].indexOf(key) < 0)
            return false
        setValue("media", key, enabled)
        return true
    }

    function setMediaPresentationTimeout(milliseconds: real): bool {
        const numeric = Number(milliseconds)
        if (!Number.isFinite(numeric))
            return false
        setValue("media", "presentationTimeout", Math.round(Math.max(2000,
            Math.min(10000, numeric)) / 1000) * 1000)
        return true
    }

    function setMediaHoverMode(mode: string): bool {
        return setValidatedValue("media", "hoverMode", mode,
            validMediaHoverModes)
    }

    function resetMedia(): void {
        resetSection("media")
    }

    function setWallpaperTarget(target: string): bool {
        return setValidatedValue("wallpaper", "target", target,
            validWallpaperTargets)
    }

    function setWallpaperGalleryColumns(columns: real): bool {
        const numeric = Number(columns)
        if (!Number.isFinite(numeric))
            return false
        setValue("wallpaper", "galleryColumns",
            Math.round(Math.max(2, Math.min(4, numeric))))
        return true
    }

    function setWallpaperRefreshOnOpen(enabled: bool): void {
        setValue("wallpaper", "refreshOnOpen", enabled)
    }

    function setWallpaperVideoOnBattery(enabled: bool): void {
        setValue("wallpaper", "videoOnBattery", enabled)
    }

    function setWallpaperTransition(transition: string): bool {
        return setValidatedValue("wallpaper", "transition", transition,
            validWallpaperTransitions)
    }

    function setWallpaperTransitionDuration(duration: real): bool {
        const numeric = Number(duration)
        if (!Number.isFinite(numeric))
            return false
        // Store a stable tenth-second value so awww never sees unbounded UI noise.
        setValue("wallpaper", "transitionDuration", Math.round(
            Math.max(0.3, Math.min(4.0, numeric)) * 10) / 10)
        return true
    }

    function setWallpaperDither(enabled: bool): void {
        setValue("wallpaper", "dither", enabled)
    }

    function setWallpaperDitherDotSize(size: real): bool {
        const numeric = Number(size)
        if (!Number.isFinite(numeric))
            return false
        setValue("wallpaper", "ditherDotSize", Math.round(
            Math.max(2.0, Math.min(8.0, numeric)) * 10) / 10)
        return true
    }

    function setWallpaperDitherWave(enabled: bool): void {
        setValue("wallpaper", "ditherWave", enabled)
    }

    function setWallpaperDitherBlackPoint(value: real): bool {
        const numeric = Number(value)
        if (!Number.isFinite(numeric))
            return false
        setValue("wallpaper", "ditherBlackPoint", Math.round(
            Math.max(0.0, Math.min(0.5, numeric)) * 100) / 100)
        return true
    }

    function setWallpaperDitherImage(path: string): void {
        setValue("wallpaper", "ditherImage", path)
    }

    function resetWallpaper(): void {
        const updated = JSON.parse(JSON.stringify(values || {}))
        const scheme = updated.wallpaper?.scheme
        if (scheme === undefined)
            delete updated.wallpaper
        else
            updated.wallpaper = ({ scheme: scheme })
        values = updated
        save()
    }

    function setDashboardSection(section: string, enabled: bool): bool {
        if (["showHero", "showMedia", "showSystem", "showQuickStrip"]
                .indexOf(section) < 0)
            return false
        if (!enabled && ((section === "showMedia"
                && !boolValue("dashboard", "showSystem", true))
                || (section === "showSystem"
                    && !boolValue("dashboard", "showMedia", true))))
            return false
        setValue("dashboard", section, enabled)
        return true
    }

    function resetDashboard(): void {
        resetSection("dashboard")
    }

    function setCommandHistorySource(source: string): bool {
        return setValidatedValue("commandLauncher", "historySource", source,
            validCommandHistorySources)
    }

    function setCommandTerminal(terminal: string): bool {
        return setValidatedValue("commandLauncher", "terminal", terminal,
            validCommandTerminals)
    }

    function setCommandHistorySuggestions(enabled: bool): void {
        setValue("commandLauncher", "historySuggestions", enabled)
    }

    function setWeatherLocation(locationName: string, latitude,
            longitude): bool {
        const name = typeof locationName === "string"
            ? locationName.trim() : ""
        const latitudeNumber = Number(latitude)
        const longitudeNumber = Number(longitude)
        if (name.length === 0 || name.length > 100
                || !Number.isFinite(latitudeNumber)
                || latitudeNumber < -90 || latitudeNumber > 90
                || !Number.isFinite(longitudeNumber)
                || longitudeNumber < -180 || longitudeNumber > 180)
            return false
        const updated = JSON.parse(JSON.stringify(values || {}))
        updated.weather = ({
            locationName: name,
            latitude: latitudeNumber,
            longitude: longitudeNumber
        })
        values = updated
        save()
        return true
    }

    function clearWeatherLocation(): void {
        resetSection("weather")
    }

    function resetSection(section: string): void {
        const updated = JSON.parse(JSON.stringify(values || {}))
        if (updated[section] === undefined)
            return
        delete updated[section]
        values = updated
        save()
    }

    function setWallpaperPaletteEnabled(enabled: bool): void {
        setValue("appearance", "wallpaperPaletteEnabled", enabled)
    }

    function setRepaintApps(enabled: bool): void {
        setValue("appearance", "repaintApps", enabled)
    }

    // Presentation style switch (Config.appearance.uiStyle). Live: every mac
    // surface is a Loader bound to this value, so no restart is needed.
    function setUiStyle(style: string): bool {
        return setValidatedValue("appearance", "uiStyle", style, validUiStyles)
    }

    // Keeps the pill in mac skin for live activities (music, timer, call in
    // progress, recording). Only read while uiStyle is "mac".
    function setMacLiveActivities(enabled: bool): void {
        setValue("appearance", "macLiveActivities", enabled)
    }

    // Which screen mac surfaces open on (Config.appearance.macScreen):
    // "focused" (default) or an output name. Unknown shapes are refused.
    function validMacScreen(value): bool {
        return Format.macScreenValid(value)
    }

    function setMacScreen(screen: string): bool {
        if (!validMacScreen(screen))
            return false
        setValue("appearance", "macScreen", screen)
        return true
    }

    // Mac text/geometry scale override (Config.appearance.macScale). 0 = auto
    // (outputWidth / 1440). Clamped to the same range as the auto value.
    function setMacScale(scale: real): void {
        setValue("appearance", "macScale", Math.max(0, Math.min(1.6, Number(scale) || 0)))
    }

    function setScheme(scheme: string): bool {
        if (validSchemes.indexOf(scheme) < 0)
            return false
        setValue("wallpaper", "scheme", scheme)
        return true
    }

    function save(): void {
        if (!loaded)
            return
        settingsFile.setText(JSON.stringify({
            version: 1,
            settings: values
        }, null, 2))
    }

    function load(raw: string): void {
        try {
            const parsed = JSON.parse(raw)
            values = parsed?.settings && typeof parsed.settings === "object"
                ? parsed.settings : ({})
            errorMessage = ""
        } catch (error) {
            values = ({})
            errorMessage = "Settings could not be read"
            console.warn("Odyssey SettingsStore:", error)
        }
        loaded = true
    }

    property FileView settingsFile: FileView {
        path: StandardPaths.writableLocation(StandardPaths.GenericStateLocation)
            + "/odyssey/settings.json"
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text())
        onFileChanged: reload()
        onLoadFailed: error => {
            root.loaded = true
            if (error !== FileViewError.FileNotFound) {
                root.errorMessage = "Settings could not be loaded"
                console.warn("Odyssey SettingsStore:",
                    FileViewError.toString(error))
            }
        }
        onSaveFailed: error => {
            root.errorMessage = "Settings could not be saved"
            console.warn("Odyssey SettingsStore:",
                FileViewError.toString(error))
        }
    }
}
