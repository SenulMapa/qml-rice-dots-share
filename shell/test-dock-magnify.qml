// Unit tests for dock/magnify.js -- the pure maths behind the dock's
// magnification, pointer smoothing and launch bounce. No window.
import QtQuick
import Quickshell
import "dock/magnify.js" as Mag

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) { log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : "")) }
    function close(a, b, eps) { return Math.abs(a - b) <= eps }

    readonly property var m: ({ peakScale: 2.0, radiusPx: 150, falloff: "cosine" })
    readonly property var mg: ({ peakScale: 2.0, radiusPx: 150, falloff: "gauss" })
    readonly property var mb: ({ bouncePeriod: 0.6, bounceRestFraction: 0.1, bounceHeight: 0.5 })

    function layout(n, w) {
        const widths = [], c = []
        let x = 100
        for (let i = 0; i < n; i++) { widths.push(w); c.push(x + w / 2); x += w }
        return { widths: widths, centers: c }
    }

    Component.onCompleted: {
        const L = layout(11, 54)

        // bell shape
        for (const shape of ["cosine", "gauss"]) {
            ok("bell_peak_" + shape, close(Mag.bell(0, shape), 1, 1e-12))
            ok("bell_edge_" + shape, Mag.bell(1, shape) === 0 && Mag.bell(2, shape) === 0)
            let mono = true, prev = 1
            for (let t = 0.001; t < 1; t += 0.001) { const b = Mag.bell(t, shape); if (b > prev + 1e-12) mono = false; prev = b }
            ok("bell_monotonic_" + shape, mono)
            ok("bell_even_" + shape, close(Mag.bell(0.37, shape), Mag.bell(-0.37, shape), 1e-12))
        }

        // peak at pointer, symmetry
        const mid = L.centers[5]
        const r = Mag.magnify(mid, L.centers, L.widths, m)
        ok("peak_scale_at_pointer", close(r.scales[5], 2.0, 1e-9), "" + r.scales[5])
        let sym = true
        for (let k = 1; k <= 5; k++) if (!close(r.scales[5 - k], r.scales[5 + k], 1e-9)) sym = false
        ok("scales_symmetric", sym)
        let sx = true
        for (let k = 1; k <= 5; k++)
            if (!close(r.centers[5] - r.centers[5 - k], r.centers[5 + k] - r.centers[5], 1e-9)) sx = false
        ok("positions_symmetric_about_pointer_item", sx)
        ok("dock_stays_centred", close((r.left + r.left + r.widths.reduce((a, b) => a + b, 0)) / 2,
            (L.centers[0] - 27 + L.centers[10] + 27) / 2, 1e-9))
        ok("peak_is_max", Math.max.apply(null, r.scales) === r.scales[5])

        // monotonic falloff away from the pointer
        let fall = true
        for (let k = 1; k <= 5; k++) if (r.scales[5 + k] > r.scales[5 + k - 1] + 1e-12) fall = false
        ok("monotonic_falloff", fall)

        // outside radius -> exactly 1
        ok("beyond_radius_is_1", r.scales.every((s, i) => Math.abs(L.centers[i] - mid) < 150 || s === 1) && r.scales[8] === 1 && r.scales[7] > 1)
        const far = Mag.magnify(mid, L.centers, L.widths, { peakScale: 2, radiusPx: 40, falloff: "cosine" })
        ok("scale_1_outside_radius", far.scales.filter((s, i) => i !== 5).every(s => s === 1))

        // no pointer -> rest
        for (const p of [null, NaN, undefined]) {
            const q = Mag.magnify(p, L.centers, L.widths, m)
            ok("no_pointer_rest_" + p, q.scales.every(s => s === 1) && q.extra === 0 && q.offsets.every(o => Math.abs(o) < 1e-9))
        }
        const q0 = Mag.magnify(mid, L.centers, L.widths, m, null, 0)
        ok("amount_zero_is_rest", q0.scales.every(s => s === 1))
        const qh = Mag.magnify(mid, L.centers, L.widths, m, null, 0.5)
        ok("amount_half_is_half_peak", close(qh.scales[5], 1.5, 1e-9))

        // width growth == sum of extra sizes
        let sumExtra = 0
        for (let i = 0; i < 11; i++) sumExtra += 54 * (r.scales[i] - 1)
        const total = r.widths.reduce((a, b) => a + b, 0)
        ok("width_growth_matches_extra", close(total - 11 * 54, sumExtra, 1e-9) && close(r.extra, sumExtra, 1e-9),
           "extra=" + r.extra.toFixed(2))
        let contig = true
        for (let i = 1; i < 11; i++)
            if (!close(r.centers[i] - r.widths[i] / 2, r.centers[i - 1] + r.widths[i - 1] / 2, 1e-9)) contig = false
        ok("slots_contiguous", contig)

        // continuity: tiny pointer steps never jump
        let maxStep = 0, prevS = null
        for (let x = 80; x <= 720; x += 0.25) {
            const q = Mag.magnify(x, L.centers, L.widths, m)
            if (prevS) for (let i = 0; i < 11; i++) {
                maxStep = Math.max(maxStep, Math.abs(q.scales[i] - prevS.scales[i]), Math.abs(q.centers[i] - prevS.centers[i]) / 54)
            }
            prevS = q
        }
        ok("continuous_in_pointer", maxStep < 0.02, "max step " + maxStep.toFixed(4))
        // C1: bell derivative is 0 at the radius (no kink where magnification starts)
        ok("no_kink_at_radius", Math.abs(Mag.scaleAt(149.99, m) - 1) < 1e-6)

        // never-magnify flags (separator)
        const fl = L.centers.map((c, i) => i !== 5)
        const rf = Mag.magnify(mid, L.centers, L.widths, m, fl)
        ok("flagged_slot_stays_1", rf.scales[5] === 1 && rf.scales[4] > 1)

        // gauss variant behaves
        const rg = Mag.magnify(mid, L.centers, L.widths, mg)
        ok("gauss_peak_and_symmetry", close(rg.scales[5], 2, 1e-9) && close(rg.scales[4], rg.scales[6], 1e-9))

        // rest layout
        const rl = Mag.restLayout([10, 20, 30], 5)
        ok("restLayout", rl.centers[0] === 10 && rl.centers[1] === 25 && rl.centers[2] === 50 && rl.total === 60)

        // smoothDamp: converges, no overshoot, frame-rate independent
        let a = [0, 0], over = false
        for (let i = 0; i < 600; i++) { a = Mag.smoothDamp(a[0], 100, a[1], 30, 1 / 120); if (a[0] > 100 + 1e-9) over = true }
        ok("smoothDamp_converges", close(a[0], 100, 1e-3))
        ok("smoothDamp_no_overshoot", !over)
        let b = [0, 0]
        for (let i = 0; i < 60; i++) b = Mag.smoothDamp(b[0], 100, b[1], 30, 1 / 60)
        let c = [0, 0]
        for (let i = 0; i < 240; i++) c = Mag.smoothDamp(c[0], 100, c[1], 30, 1 / 240)
        ok("smoothDamp_framerate_independent", close(b[0], c[0], 1e-9), b[0].toFixed(6) + " vs " + c[0].toFixed(6))
        let t95 = 0, d = [0, 0]
        while (d[0] < 95) { d = Mag.smoothDamp(d[0], 100, d[1], 34, 0.001); t95 += 0.001 }
        ok("follow_settles_fast", t95 < 0.2, "95% in " + (t95 * 1000).toFixed(0) + " ms")

        // bounce
        ok("bounce_starts_on_ground", Mag.bounce(0, mb) === 0)
        ok("bounce_peak_height", close(Mag.bounce(0.6 * 0.9 / 2, mb), 0.5, 1e-9))
        ok("bounce_periodic", close(Mag.bounce(0.21, mb), Mag.bounce(0.21 + 0.6 * 3, mb), 1e-9))
        ok("bounce_rests_on_ground", Mag.bounce(0.58, mb) === 0)
        let bmax = 0, bneg = false
        for (let t = 0; t < 3; t += 0.001) { const h = Mag.bounce(t, mb); bmax = Math.max(bmax, h); if (h < 0) bneg = true }
        ok("bounce_bounds", bmax <= 0.5 + 1e-9 && !bneg)
        // ease-out up: faster at the start of the rise than near the top
        const up1 = Mag.bounce(0.027, mb) - Mag.bounce(0.0, mb), up2 = Mag.bounce(0.270, mb) - Mag.bounce(0.243, mb)
        ok("rise_is_ease_out", up1 > up2 * 5)
        const dn1 = Mag.bounce(0.297, mb) - Mag.bounce(0.27, mb), dn2 = Mag.bounce(0.54, mb) - Mag.bounce(0.513, mb)
        ok("fall_is_ease_in", Math.abs(dn2) > Math.abs(dn1) * 5)
        ok("bounce_negative_t", Mag.bounce(-1, mb) === 0)

        // slot index
        ok("slotIndexAt", Mag.slotIndexAt(0, L.centers, L.widths) === 0 && Mag.slotIndexAt(5000, L.centers, L.widths) === 10
            && Mag.slotIndexAt(L.centers[4] + 1, L.centers, L.widths) === 4)

        console.log("=== test-dock-magnify ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.startsWith("FAIL")).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.callLater(function () { Qt.quit() })   // deferred: quitting inside onCompleted has no receiver yet
    }
}
