pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "../core"

/**
 * PerformanceService — one shell-wide "how expensive can we afford to look"
 * tier, so the laptop target (Intel UHD 620 iGPU, CPU capped ~1.3GHz/10W)
 * gets a cheaper visual budget automatically, without hand-editing Config
 * per machine and without changing the design at the high tier.
 *
 * auto (default) picks "low" when EITHER signal below is true:
 *   - a battery exists. Reuses BatteryService.available (real UPower device
 *     enumeration) rather than re-parsing /sys/class/power_supply -- that
 *     detection already exists and is more reliable than a sysfs guess.
 *   - the GPU is an Intel iGPU, detected the literal way the owner asked
 *     for: each /sys/class/drm/card-N/device/vendor file (glob below)
 *     containing 0x8086. This is a ONE-SHOT read at startup (not a poll)
 *     via a shell glob, since FileView can't glob and card indices aren't
 *     stable across machines.
 *
 * Overridable via QMLRICE_PERFORMANCE_TIER=low|high|auto (env -- still
 * honoured, useful for testing without touching persisted state) OR the
 * Settings > Appearance > "Performance tier" choice (persisted via
 * SettingsStore.setPerformanceTierOverride / Config.appearance
 * .performanceTierOverride). The env var wins if both are set to a
 * non-"auto" value, since it's the more explicit, session-scoped signal.
 */
QtObject {
    id: root

    readonly property bool hasBattery: BatteryService.available

    property bool intelIGpuDetected: false
    property Process gpuVendorProbe: Process {
        command: ["sh", "-c",
            "cat /sys/class/drm/card*/device/vendor 2>/dev/null"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                if (data.indexOf("0x8086") !== -1)
                    root.intelIGpuDetected = true
            }
        }
    }

    readonly property string envOverride: Quickshell.env("QMLRICE_PERFORMANCE_TIER") || "auto"
    readonly property string settingOverride: Config.appearance.performanceTierOverride
    readonly property bool autoLow: root.hasBattery || root.intelIGpuDetected
    readonly property string tier: {
        if (root.envOverride === "low" || root.envOverride === "high")
            return root.envOverride
        if (root.settingOverride === "low" || root.settingOverride === "high")
            return root.settingOverride
        return root.autoLow ? "low" : "high"
    }
    readonly property bool low: root.tier === "low"
}
