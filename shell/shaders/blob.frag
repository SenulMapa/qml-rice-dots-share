#version 440

// blob.frag -- the one-pill blob engine's fill shader
// (docs/superpowers/specs/2026-09-23-blob-rebuild-design.md section 1).
//
// Up to 4 bodies (pill, left satellite, right satellite, spare), each a
// rounded-box SDF in window-local pixel space, merged with a polynomial
// smooth-min. neckK.x fuses body1 (left satellite) into body0 (pill),
// neckK.y fuses body2 (right satellite). A near-zero k reads as two
// separate shapes with a gap ("separate" satelliteJoin); a large k reads
// as one continuous liquid shape ("joined", the default). Body3 (spare) is
// a hard union -- nothing currently targets it, so it has no neck.
//
// SUPERSEDED 6 Oct 2026 (owner reversal, glass redesign spec
// 2026-10-06-glass-redesign-design.md): the fill is now a near-clear glass
// tint over Hyprland's blur, lit by rim/outline from the SDF below. The
// paragraph that follows records the 13 Sep look it replaced.
//
// Fill matches components/Surface.qml's CURRENT look: solid opaque colour,
// Theme.radiusLarge corners, no gradient/sheen/hairline (those were
// explicitly removed by the owner on 13 Sep 2026 -- "no translucency, no
// light falloff, no sheen. One opaque wallpaper-derived fill.").
// Antialiased against the SDF's own screen-space derivative (fwidth), so
// the edge stays crisp at any body size or DPI without a fixed pixel budget.
//
// A body with w<=0 or h<=0 (absent -- eg. a closed satellite) is pushed to
// signed distance +1e6, i.e. it never contributes to the merged shape or to
// fwidth's local derivative estimate near the visible edge.

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 rect0;      // pill:            x, y, w, h (window-local px)
    vec4 rect1;      // left satellite:  x, y, w, h
    vec4 rect2;      // right satellite: x, y, w, h
    vec4 rect3;      // spare:           x, y, w, h
    vec4 radius;     // corner radius per body: r0, r1, r2, r3
    vec2 neckK;      // smooth-min k: body1->body0, body2->body0
    vec2 resolution; // item size in px, for qt_TexCoord0 -> px conversion
    vec4 fillColor;  // straight (non-premultiplied) rgba
    float rim;          // specular strength on light-facing edges
    float rimWidth;     // px
    float outline;      // lit outline strength
    float outlineWidth; // px
    float shadow;       // max shadow alpha, kept below Hyprland's ignore_alpha
    float ring;         // ink: alpha of an even 1px white ring just OUTSIDE the edge, unlit
};

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// Canonical Inigo Quilez rounded-box SDF: `b` is the box's FULL half-extent
// (not pre-reduced by r) -- the `-b+r` here is what insets the flat sides
// before the corner circle of radius r is added back via `-r` below. This
// shipped ONCE with `b` pre-reduced by r in bodySdf AND a redundant `+r`
// here, which double-applied r and rendered every body roughly 2r smaller
// (and positioned as if inset by r on every side) than its real rect --
// visible as bodies that never actually touch/overlap the way their fed-in
// rects said they should, so smoothMin's neck never had enough overlap to
// bridge (caught via a static two-body harness capture: two bodies
// specified to overlap by 30px still rendered as two separate shapes with
// a visible gap).
float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

float bodySdf(vec2 p, vec4 rect, float r) {
    if (rect.z <= 0.0 || rect.w <= 0.0)
        return 1.0e6;
    vec2 center = rect.xy + rect.zw * 0.5;
    vec2 halfExtent = rect.zw * 0.5;
    // sdRoundBox's `b - r` term (inside sdRoundBox) must stay >= 0 on both
    // axes, or the "flat" box the corner circle is unioned onto degenerates
    // -- on the SHORT axis in particular (a wide, short pill has a small
    // halfExtent.y), an r bigger than that axis's half-extent turns the
    // rounded box into a diamond/lens with POINTED ends instead of a
    // rounded pill. r is already meant to be <= half the shorter side by
    // construction (core/BlobLayout.qml derives it that way), but this is
    // the shader's own belt-and-suspenders clamp against any caller that
    // doesn't.
    float rc = min(r, min(halfExtent.x, halfExtent.y));
    return sdRoundBox(p - center, halfExtent, rc);
}

// Polynomial smooth-min (Inigo Quilez). k<=0 degenerates to a hard min, so
// callers don't need a separate branch for "no neck" bodies.
float smoothMin(float a, float b, float k) {
    if (k <= 0.0001)
        return min(a, b);
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

void main() {
    vec2 p = qt_TexCoord0 * resolution;

    float d0 = bodySdf(p, rect0, radius.x);
    float d1 = bodySdf(p, rect1, radius.y);
    float d2 = bodySdf(p, rect2, radius.z);
    float d3 = bodySdf(p, rect3, radius.w);

    float d = d0;
    d = smoothMin(d, d1, neckK.x);
    d = smoothMin(d, d2, neckK.y);
    d = min(d, d3);

    float aa = max(fwidth(d), 1.0e-4);
    float alpha = 1.0 - smoothstep(-aa, aa, d);

    // Glass lighting from the SDF itself (glass redesign, 6 Oct 2026): the
    // gradient of d is the outward normal, so the rim, shade and outline
    // follow every body and neck through the morph for free.
    vec2 n = normalize(vec2(dFdx(d), dFdy(d)) + 1.0e-6);
    vec2 light = normalize(vec2(-0.55, -0.85));
    float facing = dot(n, light);
    float band = 1.0 - smoothstep(0.0, rimWidth, -d);

    vec3 col = fillColor.rgb;
    float a = fillColor.a;
    float spec = rim * pow(max(facing, 0.0), 1.6) * band;
    col = mix(col, vec3(1.0), spec);
    a = a + spec * (1.0 - a);
    col *= 1.0 - 0.22 * max(-facing, 0.0) * band;

    float line = smoothstep(-outlineWidth - aa, -outlineWidth + aa, d) * (1.0 - smoothstep(-aa, aa, d));
    float lit = outline * (0.4 + 0.6 * pow(max(facing, 0.0), 1.2)) * line;
    col = mix(col, vec3(1.0), lit / max(a + lit * (1.0 - a), 1.0e-4));
    a = a + lit * (1.0 - a);

    a *= alpha * qt_Opacity;
    vec4 body = vec4(col * a, a);

    // Ink ring (8 Oct 2026): the lit `outline` above sits INSIDE the edge and
    // swings with `facing`, which read as a patchy grey arc on a black pill.
    // This is a uniform 1px band at d in (0, 1] px outside the edge, with no
    // lighting, so it follows bodies and necks evenly through every morph.
    float ringA = ring * smoothstep(-aa, aa, d) * (1.0 - smoothstep(1.0 - aa, 1.0 + aa, d)) * qt_Opacity;
    vec4 over = body + vec4(vec3(ringA), ringA) * (1.0 - body.a);

    // Soft shadow just outside, offset down a little.
    float s = shadow * pow(1.0 - smoothstep(0.0, 16.0, d - 3.0 * n.y), 2.0) * (1.0 - alpha) * qt_Opacity;
    fragColor = over + vec4(0.0, 0.0, 0.0, s) * (1.0 - over.a);
}
