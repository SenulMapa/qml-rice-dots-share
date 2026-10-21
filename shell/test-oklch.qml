// Unit tests for core/oklch.js -- the OKLCH/APCA colour maths behind the glass
// redesign's adaptive fills (spec 2026-10-06-glass-redesign-design.md,
// "AdaptiveColor"). Pure logic, no window.
import QtQuick
import "core/oklch.js" as K

Item {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    function rgb(hex) {
        const n = parseInt(hex.slice(1), 16);
        return { r: (n >> 16 & 255) / 255, g: (n >> 8 & 255) / 255, b: (n & 255) / 255 };
    }
    function close(a, b, eps) { return Math.abs(a - b) <= eps; }

    Component.onCompleted: {
        // 1. Round trips.
        for (const hex of ["#000000", "#ffffff", "#ff0000", "#0a84ff", "#7f6a3c", "#c0ffee"]) {
            const c = rgb(hex);
            const back = K.oklchToSrgb(K.srgbToOklch(c));
            ok("roundtrip_" + hex, close(c.r, back.r, 1e-3) && close(c.g, back.g, 1e-3) && close(c.b, back.b, 1e-3),
               JSON.stringify(back));
        }

        // 2. Reference points.
        const w = K.srgbToOklch(rgb("#ffffff"));
        ok("white_L1_C0", close(w.l, 1, 1e-3) && w.c < 1e-3, JSON.stringify(w));
        const red = K.srgbToOklch(rgb("#ff0000"));
        ok("red_reference", close(red.l, 0.628, 2e-3) && close(red.c, 0.2577, 2e-3) && close(red.h, 29.23, 0.5),
           JSON.stringify(red));

        // 3. APCA reference values (0.0.98G-4g).
        const bw = K.apca(rgb("#000000"), rgb("#ffffff"));
        const wb = K.apca(rgb("#ffffff"), rgb("#000000"));
        ok("apca_black_on_white", close(bw, 106.04, 0.5), bw.toFixed(2));
        ok("apca_white_on_black", close(wb, -107.88, 0.5), wb.toFixed(2));
        ok("apca_same_is_zero", K.apca(rgb("#777777"), rgb("#777777")) === 0);

        // 4. Gamut clamping.
        const magenta = K.clampChroma({ l: 0.85, c: 0.4, h: 328 });
        ok("clamp_magenta_in_gamut", K.inGamut(K.oklchToSrgb(magenta)) && magenta.c < 0.4, JSON.stringify(magenta));
        const fine = K.clampChroma({ l: 0.6, c: 0.05, h: 200 });
        ok("clamp_leaves_in_gamut_alone", close(fine.c, 0.05, 1e-9));

        // 5. activeFill over representative backdrop/accent pairs.
        const pairs = [
            ["#101014", "#7aa2f7"], ["#0b1e2d", "#3fb6a8"], ["#2a0f3d", "#ff4d6d"], ["#1b1b1b", "#e0af68"],
            ["#f5f5f5", "#0a84ff"], ["#eae3d2", "#9c6644"], ["#dfe9f3", "#5e5ce6"], ["#3b4252", "#88c0d0"],
            ["#4a1942", "#ff00ff"], ["#0f2b12", "#7dff5a"], ["#808080", "#ff9f0a"], ["#ffffff", "#30d158"]
        ];
        for (const [bg, acc] of pairs) {
            const f = K.activeFill(rgb(acc), rgb(bg));
            const fl = K.srgbToOklch(f);
            const on = K.onFill(f);
            const lc = Math.abs(K.apca(on, f));
            ok("fill_" + bg + "_" + acc,
               fl.l >= 0.82 - 1e-3 && fl.l <= 0.92 + 1e-3 && K.inGamut(f) && fl.c <= 0.12 + 1e-6 && lc >= 60,
               "L=" + fl.l.toFixed(3) + " C=" + fl.c.toFixed(3) + " Lc=" + lc.toFixed(1));
        }

        // 6. Grey accent -> soft white, not mud.
        const grey = K.srgbToOklch(K.activeFill(rgb("#8a8a8a"), rgb("#202020")));
        ok("grey_accent_soft_white", grey.c < 0.01 && grey.l > 0.9, JSON.stringify(grey));

        // 7. Fill is always brighter than the backdrop it sits on.
        const dark = K.srgbToOklch(K.activeFill(rgb("#7aa2f7"), rgb("#101014")));
        ok("fill_brighter_than_dark_bg", dark.l > K.srgbToOklch(rgb("#101014")).l + 0.25);

        // 8. glassText stays readable over its backdrop.
        for (const bg of ["#101014", "#808080", "#f5f5f5", "#ffd60a"]) {
            const t = K.glassText(rgb(bg));
            const lc = Math.abs(K.apca(t, rgb(bg)));
            ok("glass_text_" + bg, lc >= 60, "Lc=" + lc.toFixed(1));
        }

        // 9. mixToward keeps the backdrop's lightness and moves hue.
        const m = K.srgbToOklch(K.mixToward(rgb("#202020"), rgb("#0a84ff"), 0.5));
        ok("mixToward_keeps_L", close(m.l, K.srgbToOklch(rgb("#202020")).l, 0.02), JSON.stringify(m));

        // 10. Glass tint is never darker than its backdrop (no black slab).
        for (const bg of ["#101014", "#1c1b3d", "#65518f", "#e7f0f9"]) {
            const t = K.srgbToOklch(K.glassTint(rgb(bg), rgb("#7aa2f7")));
            ok("tint_not_darker_" + bg, t.l >= K.srgbToOklch(rgb(bg)).l - 1e-3, "L=" + t.l.toFixed(3));
        }

        console.log("=== test-oklch ===");
        for (const line of log) console.log(line);
        Qt.quit();
    }
}
