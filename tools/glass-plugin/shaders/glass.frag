#version 300 es
precision highp float;

// qmlrice-glass: liquid-glass body + rim for one layer surface.
//
// Two shape modes, chosen by `alphaMode`:
//   0  rounded rect: the shape is the box with `radius` corners (surface == window).
//   1  surface alpha: the shape is the layer surface's own alpha. Glass is drawn only where the
//      surface paints (alpha >= alphaThreshold and on the solid side of the 50% contour), so
//      each module or card gets its own rim and gaps and shadows stay clear.
//
// Backdrop copies cover the box plus `pad` pixels on every side, same UV mapping:
//   sharpTex  full-resolution backdrop, used at the rim so the lens stays clear
//   blurTex   downscaled Gaussian copy, the frosted body
//   sharpAlphaTex  the surface's alpha at box size (alpha mode, exact silhouette, in .r)
//   alphaTex  blurred surface alpha, padded, half-res (alpha mode). Its 0.5 contour is the edge;
//             depth = sigma * logit(alpha / local alpha) / 1.702 is the edge distance in px
//             (the logistic approximation of a Gaussian-blurred step, Phi(d / sigma)).
//             The normal is the negated gradient of the blurred alpha.
//
// Rim lens (monotone, no fold-over):
//   The backdrop sample is taken `shift` px further inside the edge, along the inward normal,
//   with shift(t) = bezel/2 * refraction * (1 - t)^2, t = depth / bezel. Its derivative keeps
//   the sample position non-decreasing across the bezel (refraction <= 1), so content inside
//   the bezel is compressed, never mirrored. Zero value and zero slope where the rim meets the
//   body, so text over the body is never warped.
// Body (t >= 1) is blurTex, undistorted. No tint and no dark fill.

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform sampler2D sharpTex;   // unit 0
uniform sampler2D blurTex;    // unit 1
uniform sampler2D sharpAlphaTex; // unit 2, alpha mode
uniform sampler2D alphaTex;   // unit 3, alpha mode

uniform vec2  boxSize;        // surface size, framebuffer px
uniform float pad;            // padding of the sample textures, px
uniform float radius;         // corner radius, px (rect mode)
uniform float bezel;          // refracting edge band, px
uniform float refraction;     // 0..1, edge shift as a fraction of bezel / 2
uniform float dispersion;     // RGB split, 0..2 (applied on the outer 40% of the bezel only)
uniform float specular;       // 0..1
uniform float lightAngle;     // radians, counter-clockwise from +x, pi/2 = light from above
uniform float alpha;          // surface alpha for this frame
uniform int   alphaMode;      // 0 rounded rect, 1 surface alpha
uniform float alphaThreshold; // alpha mode: surface alpha below this gets no glass
uniform float alphaSigma;     // alpha mode: blur sigma of alphaTex, px
uniform vec2  alphaTexel;     // alpha mode: uv size of one alphaTex texel
uniform int   featherMode;    // 1: feather (soft blur mask, no lens); 0: normal glass
uniform float featherGain;    // feather: blur weight = clamp(surface alpha * featherGain, 0, 1)

vec2 toUV(vec2 p) {
    return clamp((p + vec2(pad)) / (boxSize + vec2(2.0 * pad)), vec2(0.0), vec2(1.0));
}

void main() {
    vec2 p = v_texcoord * boxSize;
    vec2 half_ = 0.5 * boxSize;

    // Feather: the surface alpha is a soft blur weight. Alpha 0 leaves the backdrop sharp, and
    // the blur rises smoothly with alpha. sharpAlphaTex is box-sized (v_texcoord), blurTex is the
    // padded copy (toUV), the same mapping the alpha path uses. No lens, rim, specular or dispersion.
    if (featherMode == 1) {
        float m = clamp(texture(sharpAlphaTex, v_texcoord).r * featherGain, 0.0, 1.0);
        float a = m * alpha;
        vec3 col = texture(blurTex, toUV(p)).rgb;
        fragColor = vec4(col * a, a);
        return;
    }

    float cover;  // 0..1 coverage of the glass shape at this pixel
    float depth;  // px inside the edge, >= 0
    float bz;     // bezel used for this pixel's rim
    vec2  n;      // outward unit normal

    if (alphaMode == 1) {
        float aS = texture(sharpAlphaTex, v_texcoord).r;
        if (aS < alphaThreshold) {
            fragColor = vec4(0.0);
            return;
        }
        // Silhouette: the 50% contour of the surface's own alpha. Soft shadows sit below it.
        cover = smoothstep(0.35, 0.65, aS);
        if (cover <= 0.0) {
            fragColor = vec4(0.0);
            return;
        }

        bz = max(bezel, 1.0);
        vec2 uvA = toUV(p);
        // Normalise by the local alpha (interior pixels carry the surface's plateau alpha).
        float c = clamp(texture(alphaTex, uvA).r / max(aS, 1e-3), 0.002, 0.998);
        depth = max(alphaSigma * log(c / (1.0 - c)) / 1.702, 0.0);

        n = vec2(0.0);
        if (depth < bz) {
            float gx = texture(alphaTex, uvA + vec2(alphaTexel.x, 0.0)).r - texture(alphaTex, uvA - vec2(alphaTexel.x, 0.0)).r;
            float gy = texture(alphaTex, uvA + vec2(0.0, alphaTexel.y)).r - texture(alphaTex, uvA - vec2(0.0, alphaTexel.y)).r;
            float gl = length(vec2(gx, gy));
            if (gl > 1e-6)
                n = -vec2(gx, gy) / gl;  // alpha falls off outward
        }
    } else {
        // Rounded-rect signed distance (negative inside) and its outward normal.
        vec2 pc = p - half_;
        float r = clamp(radius, 0.0, min(half_.x, half_.y));
        vec2 q = abs(pc) - (half_ - vec2(r));
        vec2 qp = max(q, vec2(0.0));
        float d = length(qp) + min(max(q.x, q.y), 0.0) - r;
        vec2 s = vec2(pc.x < 0.0 ? -1.0 : 1.0, pc.y < 0.0 ? -1.0 : 1.0);
        n = (qp.x + qp.y > 0.0) ? s * normalize(qp)
                                : (q.x > q.y ? vec2(s.x, 0.0) : vec2(0.0, s.y));
        cover = clamp(0.5 - d, 0.0, 1.0);
        if (cover <= 0.0) {
            fragColor = vec4(0.0);
            return;
        }
        depth = max(-d, 0.0);
        bz = max(min(bezel, min(r, min(half_.x, half_.y)) - 1.0), 1.0);
    }

    float t = clamp(depth / bz, 0.0, 1.0);
    float e = 1.0 - t;

    // Monotone shift, px (see header). Capped at bz/2 by construction for refraction <= 1.
    float ref = clamp(refraction, 0.0, 1.0);
    float shift = 0.5 * bz * ref * e * e;

    // RGB dispersion only on the outer 40% of the bezel, fading in smoothly toward the edge.
    float dfade = 1.0 - smoothstep(0.0, 0.4, t);
    float disp = clamp(dispersion, 0.0, 2.0) * dfade;
    float kR = 1.0 + 0.22 * disp;
    float kG = 1.0 + 0.11 * disp;

    // Sharp backdrop only partly at the very edge (max 35%); the rest is the blurred copy.
    // Keeps the rim a lens of light rather than a legible, folded copy of the text behind it.
    float rimBlend = 0.35 * e * e * e;

    vec3 col;
    for (int c = 0; c < 3; c++) {
        float k = (c == 0) ? kR : (c == 1 ? kG : 1.0);
        vec2 uv = toUV(p - n * shift * k);
        float bl = texture(blurTex, uv)[c];
        float sh = texture(sharpTex, uv)[c];
        col[c] = mix(bl, sh, rimBlend);
    }

    // (d) Body: a slightly brighter, more saturated frosted glass. Applied before the rim
    // light so the highlights stay white on top of it. Luminance +6%, saturation x1.15.
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(lum), col, 1.15);
    col *= 1.06;

    // (c') Inner edge darkening: a faint denser band just inside the edge, giving thickness.
    // Starts one px in (so the bright lip below is not dimmed), fades out by ~0.6 bezel.
    float band = smoothstep(0.5, 2.0, depth) * (1.0 - smoothstep(3.0, max(bz * 0.6, 4.0), depth));
    col *= 1.0 - 0.12 * band;

    // Rim light, from the alpha-derived normal n and the light direction L (above by default).
    vec2 L = vec2(cos(lightAngle), -sin(lightAngle));
    float top = max(dot(n, L), 0.0);            // 1 on a top edge, ~0.7 on the top-left corner
    // (a) crisp top-lit line: ~1 px wide at the edge, bright, falling off around the sides.
    float line = (1.0 - smoothstep(0.3, 1.3, depth)) * pow(top, 2.0);
    // (a') softer top-lit spill inward over the top of the bezel.
    float spill = (1.0 - smoothstep(0.0, bz * 0.3, depth)) * pow(top, 2.5);
    // (b) thin bright lip all round the outer edge, weaker on the underside.
    float lip = (1.0 - smoothstep(0.0, 1.0, depth)) * (0.35 + 0.65 * top);
    col += vec3(specular * (1.0 * line + 0.15 * spill + 0.25 * lip));

    col = clamp(col, 0.0, 1.0);
    float a = cover * clamp(alpha, 0.0, 1.0);
    fragColor = vec4(col * a, a);   // premultiplied, Hyprland blends ONE, 1-src_alpha
}
