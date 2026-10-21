.pragma library

// oklch.js -- perceptual colour maths for the glass redesign
// (docs/superpowers/specs/2026-10-06-glass-redesign-design.md, "AdaptiveColor").
//
// The wallpaper changes, so accent fills can't be hand-picked: they are
// computed in OKLCH (Ottosson's OKLab in polar form), where equal L steps look
// equally bright across hues -- HSL "lighten" makes yellow glare and blue
// stay dark. Text/icon colours are chosen with APCA (the WCAG 3 draft
// contrast model, 0.0.98G-4g constants), which, unlike the WCAG 2 ratio,
// knows dark-on-light and light-on-dark are not symmetric.
//
// Colours are plain objects: sRGB {r, g, b} in 0..1, OKLCH {l, c, h} with h
// in degrees.

function _toLinear(c) {
    return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function _toGamma(c) {
    return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
}

function srgbToOklab(rgb) {
    const r = _toLinear(rgb.r), g = _toLinear(rgb.g), b = _toLinear(rgb.b);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return {
        L: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
        a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
        b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    };
}

function oklabToSrgb(lab) {
    const l = Math.pow(lab.L + 0.3963377774 * lab.a + 0.2158037573 * lab.b, 3);
    const m = Math.pow(lab.L - 0.1055613458 * lab.a - 0.0638541728 * lab.b, 3);
    const s = Math.pow(lab.L - 0.0894841775 * lab.a - 1.2914855480 * lab.b, 3);
    return {
        r: _toGamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
        g: _toGamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
        b: _toGamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    };
}

function srgbToOklch(rgb) {
    const lab = srgbToOklab(rgb);
    const c = Math.sqrt(lab.a * lab.a + lab.b * lab.b);
    let h = Math.atan2(lab.b, lab.a) * 180 / Math.PI;
    if (h < 0) h += 360;
    return { l: lab.L, c: c, h: c < 1e-6 ? 0 : h };
}

function oklchToSrgb(lch) {
    const rad = lch.h * Math.PI / 180;
    return oklabToSrgb({ L: lch.l, a: lch.c * Math.cos(rad), b: lch.c * Math.sin(rad) });
}

function inGamut(rgb, eps) {
    const e = eps === undefined ? 1e-4 : eps;
    return rgb.r >= -e && rgb.r <= 1 + e && rgb.g >= -e && rgb.g <= 1 + e
        && rgb.b >= -e && rgb.b <= 1 + e;
}

// Keep L and H, lower C until the colour fits sRGB (bisection). Desaturating
// at constant lightness is what keeps a clamped neon accent looking like the
// same colour instead of clipping to a different hue.
function clampChroma(lch) {
    if (inGamut(oklchToSrgb(lch))) return { l: lch.l, c: lch.c, h: lch.h };
    let lo = 0, hi = lch.c;
    for (let i = 0; i < 24; i++) {
        const mid = (lo + hi) / 2;
        if (inGamut(oklchToSrgb({ l: lch.l, c: mid, h: lch.h }))) lo = mid; else hi = mid;
    }
    return { l: lch.l, c: lo, h: lch.h };
}

function clip(rgb) {
    const f = v => Math.min(1, Math.max(0, v));
    return { r: f(rgb.r), g: f(rgb.g), b: f(rgb.b) };
}

// APCA lightness contrast Lc (about -108..106). Positive = dark text on a
// light background, negative = light on dark. |Lc| 60 is roughly "fine for
// UI text", 75 for body text.
function apca(text, bg) {
    const y = c => 0.2126729 * Math.pow(c.r, 2.4) + 0.7151522 * Math.pow(c.g, 2.4)
                 + 0.0721750 * Math.pow(c.b, 2.4);
    const soft = v => v < 0.022 ? v + Math.pow(0.022 - v, 1.414) : v;
    const yt = soft(y(clip(text))), yb = soft(y(clip(bg)));
    if (Math.abs(yb - yt) < 0.0005) return 0;
    let s;
    if (yb > yt) {
        s = (Math.pow(yb, 0.56) - Math.pow(yt, 0.57)) * 1.14;
        return s < 0.1 ? 0 : (s - 0.027) * 100;
    }
    s = (Math.pow(yb, 0.65) - Math.pow(yt, 0.62)) * 1.14;
    return s > -0.1 ? 0 : (s + 0.027) * 100;
}

const WHITE = { r: 1, g: 1, b: 1 };

// The "on" fill for an active toggle: the wallpaper accent's hue, a light
// shade clearly brighter than what is behind the glass, chroma capped so it
// reads pastel rather than neon. A greyish accent gives a soft white.
function activeFill(accent, backdrop) {
    const a = srgbToOklch(accent);
    const bg = srgbToOklch(backdrop);
    const l = Math.min(0.92, Math.max(0.82, bg.l + 0.25));
    if (a.c < 0.03)
        return clip(oklchToSrgb({ l: 0.95, c: 0, h: 0 }));
    // A light shade, not a neon one: chroma 0.09 at L 0.82 easing to ~0.07
    // at L 0.92 (lighter shades need less chroma to read as the same pastel).
    const cMax = 0.09 - 0.2 * (l - 0.82);
    return clip(oklchToSrgb(clampChroma({ l: l, c: Math.min(a.c, cMax), h: a.h })));
}

// Icon/text colour on a fill: white or a deep shade of the fill's own hue,
// whichever APCA says contrasts more.
function onFill(fill) {
    const f = srgbToOklch(fill);
    const dark = clip(oklchToSrgb(clampChroma({ l: 0.2, c: Math.min(f.c, 0.05), h: f.h })));
    return Math.abs(apca(WHITE, fill)) >= Math.abs(apca(dark, fill)) ? WHITE : dark;
}

// Text directly on glass: white unless the backdrop is light enough that a
// deep neutral reads better.
function glassText(backdrop) {
    const deep = clip(oklchToSrgb({ l: 0.2, c: 0, h: 0 }));
    return Math.abs(apca(WHITE, backdrop)) >= Math.abs(apca(deep, backdrop)) ? WHITE : deep;
}

// Shift `backdrop` toward `accent`'s hue/chroma by `amount`, keeping the
// backdrop's lightness -- used for the glass tint so it harmonises.
function mixToward(backdrop, accent, amount) {
    const b = srgbToOklab(backdrop), a = srgbToOklab(accent);
    return clip(oklabToSrgb({ L: b.L, a: b.a + (a.a - b.a) * amount, b: b.b + (a.b - b.b) * amount }));
}

// The near-clear tint painted on glass: the backdrop nudged toward the
// accent hue, then lifted and softened. Real glass over a dark scene reads
// slightly milky, never darker than what is behind it -- a darker tint is
// the "black slab with frost on top" look the spec forbids.
function glassTint(backdrop, accent) {
    const m = srgbToOklch(mixToward(backdrop, accent, 0.3));
    return clip(oklchToSrgb(clampChroma({ l: Math.min(0.97, m.l + 0.1 + 0.08 * (1 - m.l)), c: m.c * 0.7, h: m.h })));
}

// QML colour <-> {r,g,b} helpers.
function fromColor(c) { return { r: c.r, g: c.g, b: c.b }; }
