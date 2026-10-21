pragma Singleton
import QtQuick
import Quickshell
import "../services"
import "."

/**
 * DisplayScale — shell-only DPI scale factor.
 *
 * SCOPE. Owner's call: scale THIS SHELL's own UI (Theme.u()/font tokens,
 * BlobLayout.unit()), never touch app windows -- there is no Hyprland
 * `monitor { scale }` change here, only this file's factor feeding this
 * shell's own size tokens. Apps stay exactly as sized as before.
 *
 * WHY. BlobLayout.unit(screen) = clamp(min(w,h)*44/1080, 30, 64) is
 * screen-RESOLUTION-based, not DPI-based -- a 1080p 24" desktop monitor and
 * a 1080p 14" laptop panel compute the identical pixel unit despite the
 * laptop's pixels being physically ~59% the size (157 PPI vs the desktop's
 * ~92 PPI), so every token built from that unit renders 59% of its
 * intended physical size on this machine. Theme.u()/font tokens have the
 * same problem: no code read DPI at all before this file.
 *
 * DESIGN PPI. 92.6 -- the same reference core/Theme.qml's own Phase A unit
 * comment cites (`unit: 44 * densityScale`, 44 = 50 * 92.6/109: the HTML
 * prototype was authored at 109 PPI, the owner's desktop HDMI-A-1 runs
 * 92.6 PPI). forScreen() at 92.6 PPI returns 1.0 -- the desktop is
 * unchanged by this file existing. This laptop panel (1920x1080 @
 * 310x170mm physical, confirmed via `hyprctl monitors -j`) computes to
 * ~157 PPI -> ~1.36.
 *
 * WHY x0.8. A straight physical-size match (factor = ppi/92.6) would
 * overshoot: a 14" laptop panel sits much closer to the eyes than a 24"
 * desktop monitor, so matching millimetre size does not match apparent
 * (visual-angle) size the way it would at equal viewing distance. 0.8 is
 * a flat "laptops are viewed closer" correction, not itself a
 * measurement -- there is no per-machine viewing-distance sensor here.
 *
 * CLAMP [1.0, 1.75]. 1.0 floor: this file must never shrink the desktop's
 * existing tokens. 1.75 ceiling: caps how far a very high-PPI panel can
 * blow out the layout sight unseen; the settings override below can still
 * go higher (up to 2.0) if a user deliberately asks for it.
 */
QtObject {
    id: root

    readonly property real designPpi: 92.6
    readonly property real minScale: 1.0
    readonly property real maxScale: 1.75
    readonly property real viewingDistanceFactor: 0.8

    function forScreen(screen): real {
        const density = screen ? screen.physicalPixelDensity : 0
        const ppi = density * 25.4
        if (!(ppi > 0) || !Number.isFinite(ppi))
            return 1.0

        // Settings > Appearance "Display scale" override -- 0 means auto
        // (SettingsStore.numberValue/Config.appearance.displayScale, same
        // pattern as densityScale/fontScale). Deliberately NOT re-clamped
        // to [minScale, maxScale] here: the settings slider already bounds
        // it to 1.0-2.0, and a user picking a value above the AUTO ceiling
        // is doing so on purpose.
        const override = Config.appearance.displayScale
        if (override > 0)
            return override

        const auto = (ppi / root.designPpi) * root.viewingDistanceFactor
        const clamped = Math.max(root.minScale, Math.min(root.maxScale, auto))
        return Math.round(clamped * 100) / 100
    }

    /**
     * primary — the single global factor Theme.qml/BlobLayout.qml's
     * non-per-screen call sites (Theme.u(), font tokens) read.
     *
     * SCREEN CHOICE. Mirrors island/Island.qml's own presentation logic:
     * each Island instance is per-Quickshell.screens-entry and asks
     * HyprlandService.shouldPresentOn()/monitorIsPrimary() which one is
     * "the" island's screen. Theme/BlobLayout are global singletons with
     * no per-instance screen of their own, so this resolves the SAME
     * primary monitor HyprlandService already tracks (services/
     * HyprlandService.qml's primaryMonitorName) to a Quickshell.screens
     * entry by name and scales from that.
     *
     * LIMITATION -- single global factor. On a real mixed-PPI multi-
     * monitor rig (this laptop panel docked next to an external desktop
     * display, say), Theme.u()/font tokens still only ever get ONE factor
     * shell-wide -- there is no per-screen Theme. Only forScreen()
     * (BlobLayout.unit(), called per-screen already) is actually
     * per-monitor correct. If primaryMonitorName cannot be resolved to a
     * live screen (Hyprland not ready yet, name mismatch), fall back to
     * the MAX factor across every connected screen rather than an
     * arbitrary one, so nothing under-scales.
     */
    readonly property real primary: _computePrimary()

    function _computePrimary(): real {
        const screens = Quickshell.screens || []
        if (screens.length === 0)
            return 1.0

        const primaryName = HyprlandService.primaryMonitorName
        if (primaryName) {
            for (const candidate of screens) {
                if (candidate.name === primaryName)
                    return root.forScreen(candidate)
            }
        }

        let maxFactor = 1.0
        for (const candidate of screens) {
            const factor = root.forScreen(candidate)
            if (factor > maxFactor) maxFactor = factor
        }
        return maxFactor
    }

    Component.onCompleted: console.info(
        "DisplayScale: primary factor =", root.primary,
        "(designPpi=" + root.designPpi + ")")
}
