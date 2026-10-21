// Offscreen tests for missioncontrol/MissionControlLayout.js -- the Mission
// Control packing and the Hyprland dispatch-string guards. Pure logic, no
// window. Checks, for each window set: slot count, aspect ratio kept, no
// overlap, everything inside the area, reading order preserved.
import QtQuick
import "missioncontrol/MissionControlLayout.js" as L

Item {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    readonly property real eps: 1e-6

    // Deterministic LCG so the random-looking sets are reproducible.
    function rng(seed) {
        let s = seed >>> 0
        return function () {
            s = (Math.imul(s, 1664525) + 1013904223) >>> 0
            return s / 4294967296
        }
    }

    function randomSet(seed, n) {
        const r = rng(seed)
        const out = []
        for (let i = 0; i < n; i++) {
            const h = 300 + Math.round(r() * 900)
            const w = Math.max(120, Math.round(h * (0.3 + r() * 2.2)))
            out.push({ w: w, h: h })
        }
        return out
    }

    // Returns "" when the layout is valid, otherwise the first problem found.
    function check(items, area, slots) {
        if (slots.length !== items.length)
            return "count " + slots.length + " != " + items.length
        for (let i = 0; i < slots.length; i++) {
            const s = slots[i]
            if (!(s.w > 0 && s.h > 0))
                return "empty slot " + i
            const want = items[i].w / items[i].h
            if (Math.abs(s.w / s.h - want) > 1e-6 * want)
                return "aspect " + i
            if (s.x < area.x - eps || s.y < area.y - eps
                    || s.x + s.w > area.x + area.w + eps || s.y + s.h > area.y + area.h + eps)
                return "out of bounds " + i
        }
        for (let i = 0; i < slots.length; i++) {
            for (let j = i + 1; j < slots.length; j++) {
                const a = slots[i], b = slots[j]
                const ox = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)
                const oy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y)
                if (ox > eps && oy > eps)
                    return "overlap " + i + "/" + j
            }
        }
        // Reading order: a later item is below, or on the same row and to the right.
        for (let i = 0; i < slots.length; i++) {
            for (let j = i + 1; j < slots.length; j++) {
                const a = slots[i], b = slots[j]
                const sameRow = Math.abs(a.y - b.y) < eps
                if (!(a.y < b.y - eps || (sameRow && a.x < b.x)))
                    return "order " + i + "/" + j
            }
        }
        return ""
    }

    function coverage(slots, area) {
        let sum = 0
        for (const s of slots) sum += s.w * s.h
        return sum / (area.w * area.h)
    }

    function runSet(name, items, area, gap) {
        const slots = L.pack(items, area, gap)
        const problem = check(items, area, slots)
        ok(name, problem === "", problem || ("coverage=" + coverage(slots, area).toFixed(3)))
        return slots
    }

    Component.onCompleted: {
        const area = { x: 40, y: 200, w: 1440, h: 760 }
        const gap = 24

        // 1 window.
        runSet("one_window_16x9", [{ w: 1920, h: 1080 }], area, gap)
        ok("one_window_fills_height_or_width",
           (() => {
               const s = L.pack([{ w: 1920, h: 1080 }], area, gap)[0]
               return Math.abs(s.w - area.w) < eps || Math.abs(s.h - area.h) < eps
           })(), "")

        // 2 windows, mixed.
        runSet("two_wide_and_tall", [{ w: 2000, h: 1000 }, { w: 800, h: 1600 }], area, gap)
        runSet("two_equal", [{ w: 1000, h: 800 }, { w: 1000, h: 800 }], area, gap)

        // 5 windows, mixed ratios.
        runSet("five_mixed", [
            { w: 1920, h: 1080 }, { w: 1024, h: 768 }, { w: 1000, h: 1000 },
            { w: 900, h: 1600 }, { w: 3440, h: 1440 }
        ], area, gap)

        // 12 windows: stays within bounds and keeps order.
        const twelve = randomSet(7, 12)
        runSet("twelve_random", twelve, area, gap)

        // Extremes.
        runSet("very_wide_6to1", [{ w: 3000, h: 500 }], area, gap)
        runSet("very_tall_1to6", [{ w: 500, h: 3000 }], area, gap)
        runSet("wide_plus_tall", [{ w: 6000, h: 1000 }, { w: 500, h: 3000 }, { w: 1600, h: 900 }], area, gap)
        const tall12 = []
        for (let i = 0; i < 12; i++) tall12.push({ w: 400, h: 1200 + i * 50 })
        runSet("twelve_tall", tall12, area, gap)
        const wide8 = []
        for (let i = 0; i < 8; i++) wide8.push({ w: 2400 + i * 100, h: 600 })
        runSet("eight_wide", wide8, area, gap)

        // Several seeds, several counts: the property holds generally.
        let seedFails = ""
        for (const n of [1, 2, 3, 4, 5, 7, 9, 12, 16]) {
            for (const seed of [1, 42, 977]) {
                const items = randomSet(seed * 31 + n, n)
                const slots = L.pack(items, area, gap)
                const p = check(items, area, slots)
                if (p !== "" && seedFails === "")
                    seedFails = "n=" + n + " seed=" + seed + " " + p
            }
        }
        ok("property_sweep_n1_to_16", seedFails === "", seedFails)

        // Stability: same input, same output.
        const a1 = JSON.stringify(L.pack(twelve, area, gap))
        const a2 = JSON.stringify(L.pack(twelve, area, gap))
        ok("deterministic", a1 === a2)

        // Empty input and a zero-size area.
        ok("empty_input", L.pack([], area, gap).length === 0)
        const zero = L.pack([{ w: 100, h: 100 }], { x: 0, y: 0, w: 0, h: 0 }, gap)
        ok("zero_area_no_nan", zero.length === 1 && zero[0].w === 0 && zero[0].h === 0)

        // Reading order helper.
        const rects = [
            { x: 900, y: 0, w: 100, h: 100 }, // top right
            { x: 0, y: 0, w: 100, h: 100 },   // top left
            { x: 0, y: 500, w: 100, h: 100 }  // bottom
        ]
        const order = L.readingOrder(rects)
        ok("reading_order", order.join(",") === "1,0,2", order.join(","))

        // Dispatch guards.
        ok("focus_cmd", L.focusCmd("0xabc") === 'hl.dsp.focus({ window = "address:0xabc" })', L.focusCmd("0xabc"))
        ok("focus_rejects_bad_address", L.focusCmd("abc; rm -rf") === "" && L.focusCmd("") === "")
        ok("move_cmd", L.moveCmd("0xabc", 3) === 'hl.dsp.window.move({ workspace = 3, follow = false, window = "address:0xabc" })',
           L.moveCmd("0xabc", 3))
        ok("move_rejects_bad_ws", L.moveCmd("0xabc", 0) === "" && L.moveCmd("0xabc", 2.5) === ""
           && L.moveCmd("0xabc", NaN) === "" && L.moveCmd("bogus", 2) === "")

        console.log("=== test-mission-layout ===")
        for (const line of log) console.log(line)
        Qt.quit()
    }
}
