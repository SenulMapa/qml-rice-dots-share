pragma Singleton
import QtQuick
import "../core"

QtObject {
    id: root

    property bool changingScheme: false
    property string pendingScheme: ""
    property string statusMessage: ""
    property string errorMessage: ""

    function setMode(mode: string): void {
        if (SettingsStore.setAppearanceMode(mode))
            statusMessage = "Theme mode updated"
    }

    function setSurfaceOpacity(opacity: real): void {
        SettingsStore.setSurfaceOpacity(opacity)
    }

    function setAccentOverride(color: string): void {
        if (SettingsStore.setAccentOverride(color))
            statusMessage = "Accent override updated"
    }

    function clearAccentOverride(): void {
        SettingsStore.clearAccentOverride()
        statusMessage = "Wallpaper accent restored"
    }

    function setReducedMotion(enabled: bool): void {
        SettingsStore.setReducedMotion(enabled)
        statusMessage = enabled ? "Reduced motion enabled" : "Full motion enabled"
    }

    function setMotionSpeed(speed: string): void {
        if (SettingsStore.setMotionSpeed(speed))
            statusMessage = "Motion speed updated"
    }

    function setDensity(density: string): void {
        if (SettingsStore.setDensity(density))
            statusMessage = "Surface density updated"
    }

    function setCornerStyle(style: string): void {
        if (SettingsStore.setCornerStyle(style))
            statusMessage = "Corner style updated"
    }

    function setIslandMetric(metric: string, value: real): void {
        if (SettingsStore.setIslandMetric(metric, value))
            statusMessage = "Island geometry updated"
    }

    function resetIslandAndMotion(): void {
        SettingsStore.resetIslandAndMotion()
        statusMessage = "Island and motion defaults restored"
    }

    function setOdysseyPaletteEnabled(enabled: bool): void {
        SettingsStore.setWallpaperPaletteEnabled(enabled)
        statusMessage = enabled ? "The shell follows the wallpaper palette"
            : "The shell uses its built-in semantic palette"
    }

    function setScheme(scheme: string): void {
        if (changingScheme || SettingsStore.validSchemes.indexOf(scheme) < 0
                || scheme === Config.wallpaper.scheme)
            return
        if (!WallpaperService.currentWallpaper) {
            errorMessage = "Choose a wallpaper before changing its palette style"
            return
        }
        pendingScheme = scheme
        changingScheme = true
        errorMessage = ""
        statusMessage = "Generating palette…"
        WallpaperService.changeScheme(scheme)
    }

    property Connections schemeCompletion: Connections {
        target: WallpaperService
        function onOperationStateChanged() {
            if (!root.changingScheme || WallpaperService.operationState === "changingScheme")
                return
            root.changingScheme = false
            if (WallpaperService.errorMessage.length === 0
                    && Config.wallpaper.scheme === root.pendingScheme) {
                root.statusMessage = "Palette style updated"
                root.errorMessage = ""
            } else {
                root.statusMessage = ""
                root.errorMessage = WallpaperService.errorMessage || "Palette generation failed"
            }
            root.pendingScheme = ""
        }
    }
}
