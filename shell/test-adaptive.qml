// AdaptiveColor's outputs must equal core/oklch.js applied to its inputs,
// with overrides pinning accent/backdrop (no wallpaper needed).
import QtQuick
import "services"
import "core/oklch.js" as K

Item {
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    function same(a, b) {
        return Math.abs(a.r - b.r) < 0.004 && Math.abs(a.g - b.g) < 0.004 && Math.abs(a.b - b.b) < 0.004
    }
    Component.onCompleted: {
        AdaptiveColor.overrideAccent = "#ff4d6d"
        AdaptiveColor.overrideBackdrop = "#2a0f3d"
        const acc = K.fromColor(AdaptiveColor.accent), bg = K.fromColor(AdaptiveColor.backdrop)
        ok("accent_override", same(AdaptiveColor.accent, Qt.color("#ff4d6d")))
        ok("activeFill_matches_maths", same(AdaptiveColor.activeFill, K.activeFill(acc, bg)))
        const want = K.onFill(K.fromColor(AdaptiveColor.activeFill))
        ok("activeFillText_matches_maths", same(AdaptiveColor.activeFillText, want), AdaptiveColor.activeFillText + " vs " + JSON.stringify(want))
        ok("glassText_white_on_dark", same(AdaptiveColor.glassText, { r: 1, g: 1, b: 1 }))
        AdaptiveColor.overrideBackdrop = "#f2f2f2"
        ok("glassText_dark_on_light", AdaptiveColor.glassText.r < 0.3, AdaptiveColor.glassText.toString())
        ok("fill_tracks_backdrop", K.srgbToOklch(K.fromColor(AdaptiveColor.activeFill)).l > 0.9)
        // Sampling cost gate: the 4s screen poll runs only on AC with an
        // island on screen; on battery sampling is event-driven, debounced.
        const lp = BatteryService.onBattery
        ok("lowpower_tracks_battery", AdaptiveColor._lowPower === lp, "onBattery=" + lp)
        ok("periodic_gated", AdaptiveColor._screenPeriodic.running === (!lp && !AdaptiveColor._nothingShown))
        ok("debounce_rate", AdaptiveColor._screenDebounce.interval === (lp ? 1000 : 250))
        console.log("=== test-adaptive ===")
        for (const line of log) console.log(line)
        Qt.quit()
    }
}
