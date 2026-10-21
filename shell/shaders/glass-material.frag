#version 440

// glass-material.frag -- the glass look for components/GlassMaterial.qml
// (docs/superpowers/specs/2026-10-06-glass-redesign-design.md, Phase 1).
//
// On the desktop the blur itself comes from Hyprland (layer rule blur,
// ignore_alpha 0.19), so this only paints what sits ON the blur, all from one
// exact rounded-rect distance field:
//   tint     -- near-clear (alpha ~0.24, which also keeps the pixel above
//               ignore_alpha so Hyprland blurs behind it)
//   rim      -- specular band on the edges facing a fixed top-left light
//   shade    -- a soft inner darkening on the far edges
//   outline  -- a lit line just inside the edge, never fully dark
//   shadow   -- soft, offset down, kept below ignore_alpha so it is never
//               blurred into a halo
// The item is the shape plus `pad` px on every side for the shadow.
//
// Compile: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
//          -o glass-material.frag.qsb glass-material.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // item size, px (shape + 2 * pad)
    float pad;          // shadow margin, px
    float radius;       // corner radius, px
    vec4 tint;          // rgb + alpha
    float rim;          // specular strength
    float rimWidth;     // px
    float outline;      // lit outline strength
    float outlineWidth; // px
    float shadow;       // max shadow alpha (keep < 0.19)
    float shadowSpread; // px
};

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 p = qt_TexCoord0 * size - size * 0.5;
    vec2 half_ = size * 0.5 - pad;
    float r = min(radius, min(half_.x, half_.y));
    float d = sdRoundBox(p, half_, r);
    float aa = max(fwidth(d), 1e-4);
    float inside = 1.0 - smoothstep(-aa, aa, d);

    vec2 n = normalize(vec2(dFdx(d), dFdy(d)) + 1e-6);
    vec2 light = normalize(vec2(-0.55, -0.85));
    float facing = dot(n, light);

    // Glass body.
    float band = 1.0 - smoothstep(0.0, rimWidth, -d);
    vec3 col = tint.rgb;
    float a = tint.a;
    float spec = rim * pow(max(facing, 0.0), 1.6) * band;
    float shade = 0.22 * max(-facing, 0.0) * band;
    col = mix(col, vec3(1.0), spec);
    a = a + spec * (1.0 - a);
    col *= 1.0 - shade;
    a = a + shade * 0.25 * (1.0 - a);

    float line = smoothstep(-outlineWidth - aa, -outlineWidth + aa, d) * (1.0 - smoothstep(-aa, aa, d));
    float lit = outline * (0.4 + 0.6 * pow(max(facing, 0.0), 1.2)) * line;
    col = mix(col, vec3(1.0), lit / max(a + lit * (1.0 - a), 1e-4));
    a = a + lit * (1.0 - a);

    vec4 body = vec4(col * a, a) * inside;

    // Shadow under everything, outside the shape only.
    float ds = sdRoundBox(p - vec2(0.0, shadowSpread * 0.25), half_, r);
    float s = shadow * pow(1.0 - smoothstep(0.0, shadowSpread, ds), 2.0) * (1.0 - inside);
    vec4 sh = vec4(0.0, 0.0, 0.0, s);

    fragColor = (body + sh * (1.0 - body.a)) * qt_Opacity;
}
