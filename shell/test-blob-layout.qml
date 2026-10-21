// Unit test for core/BlobLayout.qml -- every state must fit inside the
// screen (no body exceeds screen bounds) with no negative sizes, across
// the screen sizes the owner actually has (docs/superpowers/specs/
// 2026-09-23-blob-rebuild-design.md testing section).
import QtQuick
import Quickshell
import "core"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    Timer {
        interval: 0; running: true; repeat: false
        onTriggered: root.run()
    }

    function run() {
        const screens = [
            { name: "1920x1080", width: 1920, height: 1080 },
            { name: "1080x1920 (rotated)", width: 1080, height: 1920 },
            { name: "2560x1440", width: 2560, height: 1440 },
            { name: "1280x800", width: 1280, height: 800 }
        ]
        const states = ["rest", "hover", "media", "osd", "notification",
            "dashboard", "subpage", "settings"]
        const ctxVariants = [
            { label: "closed", ctx: {} },
            { label: "wifi", ctx: { wifiOpen: true } },
            { label: "bt", ctx: { bluetoothOpen: true } },
            { label: "both-separate", ctx: { wifiOpen: true, bluetoothOpen: true, satelliteJoin: "separate" } }
        ]

        let allFit = true
        let noNegative = true
        let unitBounded = true
        let sampleDetail = ""

        for (const screen of screens) {
            const u = BlobLayout.unit(screen)
            if (u < BlobLayout.minUnit - 1e-6 || u > BlobLayout.maxUnit + 1e-6)
                unitBounded = false

            for (const state of states) {
                for (const cv of ctxVariants) {
                    const t = BlobLayout.targets(state, screen, cv.ctx)
                    for (let i = 0; i < t.bodies.length; i++) {
                        const b = t.bodies[i]
                        if (b.w < 0 || b.h < 0 || b.r < 0) {
                            noNegative = false
                            sampleDetail = screen.name + " " + state + " " + cv.label
                                + " body" + i + " w=" + b.w + " h=" + b.h + " r=" + b.r
                        }
                        if (b.w <= 0 || b.h <= 0)
                            continue // absent body, nothing to bound-check
                        const withinX = b.x >= -0.5 && (b.x + b.w) <= screen.width + 0.5
                        const withinY = b.y >= -0.5 && (b.y + b.h) <= screen.height + 0.5
                        if (!withinX || !withinY) {
                            allFit = false
                            sampleDetail = screen.name + " " + state + " " + cv.label
                                + " body" + i + " x=" + b.x + " y=" + b.y
                                + " w=" + b.w + " h=" + b.h
                        }
                    }
                }
            }
        }

        root.ok("unit_stays_within_30_64", unitBounded)
        root.ok("no_negative_sizes", noNegative, sampleDetail)
        root.ok("every_body_fits_on_screen", allFit, sampleDetail)

        // 1080p reproduces the historical 44px unit exactly.
        root.ok("1080p_unit_is_44", Math.abs(BlobLayout.unit({ width: 1920, height: 1080 }) - 44) < 1e-6,
            "" + BlobLayout.unit({ width: 1920, height: 1080 }))

        // Rotated portrait monitor: min(w,h) is still 1080, so the unit
        // (and every k*unit size) matches the landscape screen exactly --
        // only the width clamp differs.
        const uLandscape = BlobLayout.unit({ width: 1920, height: 1080 })
        const uPortrait = BlobLayout.unit({ width: 1080, height: 1920 })
        root.ok("portrait_unit_matches_landscape", Math.abs(uLandscape - uPortrait) < 1e-6,
            "landscape " + uLandscape + " portrait " + uPortrait)

        // maxHeight(screen) is at least as tall as every individual state's
        // pill height, for each test screen -- the invariant the one fixed
        // never-resized PanelWindow actually depends on.
        let maxHeightOk = true
        for (const screen of screens) {
            const mh = BlobLayout.maxHeight(screen)
            for (const state of states) {
                const t = BlobLayout.targets(state, screen, { wifiOpen: true, bluetoothOpen: true })
                for (const b of t.bodies) {
                    if (b.h > mh + 0.5) maxHeightOk = false
                }
            }
        }
        root.ok("max_height_covers_every_state", maxHeightOk)

        // Bodies 2/3 (satellites) are present exactly when requested, and
        // otherwise report zero area (the "absent" contract BlobSurface
        // relies on).
        const closedT = BlobLayout.targets("hover", screens[0], {})
        root.ok("satellites_absent_by_default",
            closedT.bodies[1].w === 0 && closedT.bodies[1].h === 0
                && closedT.bodies[2].w === 0 && closedT.bodies[2].h === 0)
        const openT = BlobLayout.targets("hover", screens[0], { wifiOpen: true, bluetoothOpen: true })
        root.ok("satellites_present_when_requested",
            openT.bodies[1].w > 0 && openT.bodies[1].h > 0
                && openT.bodies[2].w > 0 && openT.bodies[2].h > 0)

        console.log("=== BLOB LAYOUT TEST ===")
        for (const line of root.log) console.log(line)
        const failed = root.log.filter(l => l.startsWith("FAIL")).length
        console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
