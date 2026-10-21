pragma Singleton
import QtQuick
import Quickshell
import "."

/**
 * GlassBlurProfile -- laptop-only battery trade-off for the glass layers.
 *
 * With xray=false the compositor re-blurs whatever redraws under the island,
 * which costs roughly +2 W during video and +1.3 W with a busy terminal
 * underneath. On a laptop (BatteryService.available) running on battery this
 * sets xray=true for the glass layers, so the glass shows the blurred
 * wallpaper instead of the live app behind it. That relaxes the glass spec's
 * hard rule 1 on battery only (battery-first programme); on AC xray=false
 * is restored. Desktops (no battery) are never touched.
 *
 * Later layer rules override earlier ones, so a runtime `hyprctl eval` of
 * hl.layer_rule wins over the static config. Applied once at startup and on
 * every onBattery change, debounced so a flapping AC state cannot spam
 * hyprctl.
 */
QtObject {
    id: root

    // Must match glassLayers in hypr/hyprland/rules.lua. The ink island is
    // opaque, so it is not a glass layer. No Config read here: core/ imports
    // services/, and importing ../core from a services singleton is a cycle
    // that fails the whole config load.
    readonly property string glassNamespaces:
        "^qml-rice:(workspace-toast|volume-edge.*|edge-visualizer)$"

    readonly property bool _laptop: BatteryService.available
    readonly property bool _xray: BatteryService.onBattery

    function start(): void { _apply.restart(); }

    function _applyNow(): void {
        if (!_laptop) return;
        Quickshell.execDetached(["hyprctl", "eval",
            `hl.layer_rule({ match = { namespace = "${glassNamespaces}" }, xray = ${_xray} })`]);
    }

    on_XrayChanged: _apply.restart()
    on_LaptopChanged: _apply.restart()

    property Timer _apply: Timer {
        interval: 2000
        onTriggered: root._applyNow()
    }
}
