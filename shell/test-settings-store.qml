// Unit test for core/SettingsStore.qml's generic string/enum setting
// support (added for the Settings font pickers and the performance-tier
// override -- panels/SettingsPage.qml, services/PerformanceService.qml).
//
// SettingsStore is a real singleton backed by a real file
// (StandardPaths GenericStateLocation + "/odyssey/settings.json" --
// this machine's actual live shell settings). There is no test seam to
// redirect that path, so this test: snapshots the real `values` before
// touching anything, exercises the setters/getters against the real
// singleton, and -- as its LAST action, unconditionally -- restores the
// exact original snapshot and saves it back. Every assertion here only
// READS derived getters or checks return values; nothing here is left
// mutated once run() finishes.
import QtQuick
import Quickshell
import "core"

ShellRoot {
    id: root
    property var log: []
    property var originalValues: ({})
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    // blockLoading: true on SettingsStore's FileView means the load is
    // synchronous at construction, but give the singleton one tick to
    // finish either way before trusting `loaded`.
    Timer {
        interval: 30; running: true; repeat: false
        onTriggered: root.waitForLoad()
    }

    property int waitTicks: 0
    function waitForLoad() {
        if (!SettingsStore.loaded && root.waitTicks < 20) {
            root.waitTicks++
            loadWait.restart()
            return
        }
        root.run()
    }
    Timer { id: loadWait; interval: 20; onTriggered: root.waitForLoad() }

    function run() {
        root.originalValues = JSON.parse(JSON.stringify(SettingsStore.values || {}))

        // ---- font family: dynamic-domain string setting ----------------
        const families = Qt.fontFamilies()
        root.ok("host_has_installed_fonts_to_test_against", families.length > 0,
            "" + families.length)
        if (families.length > 0) {
            const familyA = families[0]
            const familyB = families[families.length - 1]

            root.ok("setFontFamily_accepts_installed_family",
                SettingsStore.setFontFamily("fontFamily", familyA))
            root.ok("fontFamilyValue_roundtrips",
                SettingsStore.fontFamilyValue("fontFamily", "Geist") === familyA,
                SettingsStore.fontFamilyValue("fontFamily", "Geist"))

            root.ok("setFontFamily_rejects_unknown_family",
                !SettingsStore.setFontFamily("fontFamily", "Definitely Not Installed XYZ 42"))
            root.ok("rejected_family_leaves_value_unchanged",
                SettingsStore.fontFamilyValue("fontFamily", "Geist") === familyA)

            root.ok("setFontFamily_rejects_unknown_key",
                !SettingsStore.setFontFamily("notARealFontKey", familyA))

            // Changing role is independent of other roles.
            root.ok("setFontFamily_second_role_roundtrips",
                SettingsStore.setFontFamily("monoFontFamily", familyB)
                    && SettingsStore.fontFamilyValue("monoFontFamily", "Geist Mono") === familyB)
            root.ok("first_role_unaffected_by_second",
                SettingsStore.fontFamilyValue("fontFamily", "Geist") === familyA)
        }

        // ---- performance tier: fixed-enum setting -----------------------
        root.ok("setPerformanceTierOverride_accepts_low",
            SettingsStore.setPerformanceTierOverride("low"))
        root.ok("performanceTierOverride_roundtrips_through_Config",
            Config.appearance.performanceTierOverride === "low",
            Config.appearance.performanceTierOverride)
        root.ok("setPerformanceTierOverride_rejects_bogus",
            !SettingsStore.setPerformanceTierOverride("ludicrous"))
        root.ok("rejected_tier_leaves_value_unchanged",
            Config.appearance.performanceTierOverride === "low")
        root.ok("setPerformanceTierOverride_accepts_auto",
            SettingsStore.setPerformanceTierOverride("auto")
                && Config.appearance.performanceTierOverride === "auto")

        // ---- generic bounded string setting -----------------------------
        root.ok("setStringValue_trims_and_roundtrips",
            SettingsStore.setStringValue("testSection", "testKey", "  Hello World  ", 64)
                && SettingsStore.stringValue("testSection", "testKey", "fallback", 64)
                    === "Hello World")
        root.ok("setStringValue_rejects_empty",
            !SettingsStore.setStringValue("testSection", "testKey2", "   ", 64))
        root.ok("setStringValue_rejects_control_chars",
            !SettingsStore.setStringValue("testSection", "testKey3", "bad\x01value", 64))
        root.ok("setStringValue_rejects_over_max_length",
            !SettingsStore.setStringValue("testSection", "testKey4",
                "x".repeat(65), 64))
        root.ok("stringValue_falls_back_when_unset",
            SettingsStore.stringValue("testSection", "neverSet", "fallback-ok", 64)
                === "fallback-ok")

        // ---- font scale: bounded number setting, read back through Config
        SettingsStore.setFontScale(5)
        root.ok("setFontScale_clamps_high",
            Config.appearance.fontScale === 1.3, "" + Config.appearance.fontScale)
        SettingsStore.setFontScale(0.1)
        root.ok("setFontScale_clamps_low",
            Config.appearance.fontScale === 0.8, "" + Config.appearance.fontScale)
        SettingsStore.setFontScale(1.05)
        root.ok("setFontScale_roundtrips_in_band",
            Config.appearance.fontScale === 1.05, "" + Config.appearance.fontScale)

        finish()
    }

    // Unconditional restore -- runs whatever happened above.
    function finish() {
        SettingsStore.values = JSON.parse(JSON.stringify(root.originalValues))
        SettingsStore.save()

        console.log("=== SETTINGS STORE TEST ===")
        for (const line of root.log)
            console.log(line)
        const failed = root.log.filter(l => l.startsWith("FAIL")).length
        console.log("=== " + (root.log.length - failed) + "/"
            + root.log.length + " passed ===")
        Qt.quit()
    }
}
