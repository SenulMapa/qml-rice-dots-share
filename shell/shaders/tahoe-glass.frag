#version 440

// tahoe-glass.frag -- the macOS 26 "Tahoe" liquid-glass rim for
// components/TahoeGlass.qml. Paints only what sits ON the compositor blur:
//   body     -- a light white tint (tintAlpha ~0.12), never a dark fill
//   rim      -- ~1 px specular band, brightest on the edge facing the light
//               (lightAngle, default straight down from the top), fading
//               to rimSide on the sides and bottom
//   glow     -- a soft inner glow ~6 px wide, innerGlow -> 0, so the glass
//               reads as thick; it doubles as the fake rim lens (the real
//               backdrop refraction is a later compositor job)
//   shadow   -- a wide soft black drop shadow outside the shape, offset by
//               shadowY, which lifts the shape off the wallpaper
// The item is the shape plus `pad` px on every side (the shadow margin).
//
// Compile: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
//          -o tahoe-glass.frag.qsb tahoe-glass.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;          // item size px (shape + 2 * pad)
    float pad;          // margin around the shape for the shadow, px
    float radius;       // corner radius, px
    float tintAlpha;    // white body alpha, ~0.10-0.14 on the dock
    float rimTop;       // rim strength on the edge facing the light
    float rimSide;      // rim strength on the sides and bottom
    float innerGlow;    // inner glow alpha at the edge (fades to 0)
    float lightAngle;   // radians; direction TOWARD the light (-PI/2 = from above)
    float shadowAlpha;  // peak drop-shadow alpha, black
    float shadowBlur;   // drop-shadow falloff distance, px
    float shadowY;      // drop-shadow y offset, px (positive = down)
};

const float RIM_WIDTH = 1.2;    // px, the specular band
const float GLOW_WIDTH = 6.0;   // px, the inner glow falloff

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

    // Outward normal from the distance field (central differences), so the
    // rim does not depend on derivative quality at the edge.
    const float e = 0.5;
    vec2 g = vec2(sdRoundBox(p + vec2(e, 0.0), half_, r) - sdRoundBox(p - vec2(e, 0.0), half_, r),
                  sdRoundBox(p + vec2(0.0, e), half_, r) - sdRoundBox(p - vec2(0.0, e), half_, r));
    vec2 n = g / max(length(g), 1e-6);
    vec2 toLight = vec2(cos(lightAngle), sin(lightAngle));
    float facing = max(dot(n, toLight), 0.0);

    float depth = -d;   // px inside the edge (>0 inside)
    float glow = innerGlow * pow(clamp(1.0 - depth / GLOW_WIDTH, 0.0, 1.0), 2.0);
    float band = clamp(1.0 - depth / RIM_WIDTH, 0.0, 1.0);
    float rim = mix(rimSide, rimTop, facing) * band;

    // White body with the glow and rim composited over it (source-over).
    float a = tintAlpha;
    a = a + glow * (1.0 - a);
    a = a + rim * (1.0 - a);
    vec4 body = vec4(vec3(a), a) * inside;

    // Soft drop shadow outside the shape only.
    float ds = sdRoundBox(p - vec2(0.0, shadowY), half_, r);
    float s = shadowAlpha * pow(1.0 - smoothstep(0.0, shadowBlur, ds), 2.0) * (1.0 - inside);
    vec4 sh = vec4(0.0, 0.0, 0.0, s);

    fragColor = (body + sh * (1.0 - body.a)) * qt_Opacity;
}
