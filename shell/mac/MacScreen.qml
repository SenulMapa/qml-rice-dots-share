pragma Singleton
import QtQuick
import Quickshell
import "../core"
import "../services"
import "MacFormat.js" as Format

/**
 * MacScreen -- which screen a NEW mac surface opens on. Reads
 * Config.appearance.macScreen ("focused" or a pinned output name) and the
 * Hyprland focus, through the pure Format.macScreenFor(). Called when a
 * surface is created: the layer windows keep the screen they were given, so
 * banners already on screen stay where they are.
 */
QtObject {
    function choose(): var {
        return Format.macScreenFor(
            Config.appearance.macScreen, Quickshell.screens,
            HyprlandService.focusedMonitor?.name ?? "",
            HyprlandService.primaryMonitorName)
    }
}
