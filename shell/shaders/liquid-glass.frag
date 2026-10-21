#version 440

// liquid-glass.frag -- frosted glass for components/LiquidGlass.qml.
//
// Textures, all the size of the glass item:
//   source -- the background directly behind the glass (a sourceRect crop)
//   frosted-- the same crop, heavily blurred and slightly saturated
//   sharp  -- the glass shape, white on transparent (text, pill, circle)
//   soft   -- the shape blurred a little; its alpha is a height map whose
//             0.5 contour is the outline
//
// The body is the frosted background, lifted toward white so the shape reads
// on any wallpaper. Only a thin band just inside the outline bends the
// background (a lens rim, `strength` px at most) and catches light: a bright
// specular line on the edges facing the top-left, a soft shade opposite.
// Thin text strokes are almost all "edge", so heavy refraction across the
// whole shape reads as warped chrome rather than glass; keep it to the rim.
//
// Compile: /usr/lib/qt6/bin/qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
//          -o liquid-glass.frag.qsb liquid-glass.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texel;        // 1 / item size in px
    float strength;    // rim displacement, px
    float milk;        // 0..1, how far the body is lifted toward white
    float rim;         // specular intensity
    float rimWidth;    // 0..1 of the soft ramp treated as rim
    vec4 tint;         // rgb tint, alpha = mix amount
    float outline;     // lit outline strength (0 = none)
    float lineWidth;   // outline width, px
    float radius;      // >= 0: the shape is this rounded rect (exact SDF outline)
    vec2 lightDir;     // direction the light comes FROM, screen space (y down)
};

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D frosted;
layout(binding = 3) uniform sampler2D sharp;
layout(binding = 4) uniform sampler2D soft;

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float cover = texture(sharp, uv).a;
    if (cover < 0.003) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 dx = vec2(texel.x, 0.0);
    vec2 dy = vec2(0.0, texel.y);
    float h = texture(soft, uv).a;
    vec2 g = vec2(texture(soft, uv + dx).a - texture(soft, uv - dx).a,
                  texture(soft, uv + dy).a - texture(soft, uv - dy).a);
    vec2 dir = length(g) > 1e-5 ? normalize(g) : vec2(0.0);

    // 1 at the outline (h = 0.5), falling to 0 by h = 0.5 + rimWidth.
    float band = 1.0 - smoothstep(0.5, 0.5 + rimWidth, h);

    // Rim lens: pull the frosted sample inward, strongest at the outline.
    vec2 off = dir * band * band * strength * texel;
    vec3 body = texture(frosted, uv + off).rgb;

    body = mix(body, tint.rgb, tint.a);
    body = mix(body, vec3(1.0), milk);

    vec2 light = normalize(lightDir);
    float facing = dot(-dir, light);
    float spec = pow(max(facing, 0.0), 1.6) * band;
    float shade = max(-facing, 0.0) * band;
    vec3 col = body + vec3(1.0) * rim * spec;
    col *= 1.0 - shade * 0.18;
    // A faint even line all the way round, so the outline holds on flat areas.
    col += vec3(0.10) * smoothstep(0.35, 1.0, band);

    // Lit outline: a ~1.5px line hugging the shape's own edge, so it follows
    // curves exactly (a Rectangle border goes thin and looks clipped on a
    // capsule's ends). Never fully dark -- the far side keeps 40% -- and
    // brightest where the edge faces the light.
    // Pills/circles pass their radius, so the line comes from an exact
    // signed distance: a crisp, anti-aliased band `lineWidth` px wide just
    // inside the edge, lit by the SDF normal. Other shapes skip it.
    float line = 0.0;
    float lit = 0.4 + 0.6 * pow(max(facing, 0.0), 1.2);
    if (radius >= 0.0) {
        vec2 size = 1.0 / texel;
        vec2 p = uv * size - size * 0.5;
        float r = min(radius, min(size.x, size.y) * 0.5);
        float d = sdRoundBox(p, size * 0.5, r);
        float aa = max(fwidth(d), 1e-4);
        line = smoothstep(-lineWidth - aa, -lineWidth + aa, d) * (1.0 - smoothstep(-aa, aa, d));
        vec2 n = normalize(vec2(dFdx(d), dFdy(d)) + 1e-6);
        lit = 0.4 + 0.6 * pow(max(dot(n, light), 0.0), 1.2);
    }
    col = mix(col, vec3(1.0), clamp(outline * line * lit, 0.0, 1.0));

    fragColor = vec4(clamp(col, 0.0, 1.0), 1.0) * cover * qt_Opacity;
}
