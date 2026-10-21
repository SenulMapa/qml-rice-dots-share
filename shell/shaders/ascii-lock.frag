#version 440

// Single-pass fragment shader for lock/AsciiLockSurface.qml -- REPLACES the
// old 3-ShaderEffect pipeline (ascii-wave.vert/.frag -> ascii-cells.frag ->
// ascii-color.frag). That pipeline used a custom GridMesh vertex shader to
// wobble the rendered clock-text plane in pseudo-3D, then re-captured the
// result through TWO intermediate ShaderEffectSources before a final colour
// pass. On this project's test target that produced a doubled/ghosted
// clock ("11 7 7 :: 2 2 1 1") that got worse under mouse tilt, and the
// doubling persisted even with an exact-identity vertex transform (uK=0)
// and an effectively-infinite perspective divide -- i.e. it was a
// GridMesh/vertex-shader/ShaderEffectSource plumbing bug, not a wave-math
// bug. See git history on lock/AsciiLockSurface.qml for the full account.
//
// This version never moves geometry and never re-captures its own output:
// ONE ShaderEffect, Qt's default (unmodified) vertex shader, sampling
// exactly two textures -- `source` (the hidden clock Text's
// ShaderEffectSource) and `atlas` (the hidden glyph-charset Row's
// ShaderEffectSource) -- once per screen pixel. The "3D wave/tilt" from the
// original ASCIIText port is now a pure UV-space distortion of the CLOCK
// TEXTURE LOOKUP, computed per-cell (not per-pixel, so the wobble reads as
// the whole glyph mosaic waving, not a per-pixel shimmer): there is no
// mesh, so there is nothing for a mesh-related bug to double.
//
// No integer bitwise ops, no texelFetch, no textureLod, no const arrays, no
// uniform arrays -- compiled via
// `qsb --glsl "100 es,120,150" --hlsl 50 --msl 12`.

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;

    vec2 uResolution;   // stage pixel size
    float uCellPx;      // on-screen ascii cell size, pixels
    float uGlyphCount;  // charset length, as a float

    float uTime;        // seconds, free-running
    float uK;           // overall wave strength
    vec2 uRot;          // eased (pitch, yaw) tilt, radians, mouse-driven
    float uPerspective; // tilt projective-divide strength

    vec2 uChroma;       // clock-sample RGB-offset magnitude (UV units)
    vec2 uDilate;       // clock-sample dilation tap radius (UV units)
    vec2 uGlyphDilate;  // atlas glyph dilation tap radius (UV units)
    float uLumThreshold;

    vec4 colorA;
    vec4 colorB;
    vec4 colorC;
    float uHue;         // eased mouse-orbit angle, radians
};

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source; // hidden clock-text render
layout(binding = 2) uniform sampler2D atlas;  // hidden glyph-charset strip

// Coverage at one UV, max-filtered over a centre tap + 4 diagonal taps --
// see the old ascii-wave.frag's header for why: fattens the glyph
// silhouette so a per-CELL centre sample reliably lands on ink often
// enough to hit the required lit-pixel density.
float dilatedAlpha(sampler2D tex, vec2 uv, vec2 r) {
    float a = texture(tex, uv).a;
    a = max(a, texture(tex, uv + vec2(r.x, r.y)).a);
    a = max(a, texture(tex, uv + vec2(-r.x, r.y)).a);
    a = max(a, texture(tex, uv + vec2(r.x, -r.y)).a);
    a = max(a, texture(tex, uv + vec2(-r.x, -r.y)).a);
    return a;
}

vec3 hueRotate(vec3 col, float angle) {
    // Computed local mat3 (runtime cos/sin), not a compile-time const
    // array -- fine under the "no const arrays" constraint. GLSL mat3(...)
    // is COLUMN-major, so each argument triple below is one COLUMN of the
    // textbook row-major hue-rotation matrix.
    float c = cos(angle);
    float s = sin(angle);
    mat3 m = mat3(
        0.299 + 0.701 * c + 0.168 * s,
        0.299 - 0.299 * c - 0.328 * s,
        0.299 - 0.300 * c + 1.250 * s,

        0.587 - 0.587 * c - 0.328 * s,
        0.587 + 0.413 * c + 0.035 * s,
        0.587 - 0.588 * c - 1.050 * s,

        0.114 - 0.114 * c + 0.497 * s,
        0.114 - 0.114 * c - 0.705 * s,
        0.114 + 0.886 * c - 0.203 * s
    );
    return m * col;
}

void main() {
    float aspect = uResolution.x / max(uResolution.y, 1.0);

    // ---- 1. cell geometry (per-CELL, not per-pixel) ------------------
    vec2 pixelPos = qt_TexCoord0 * uResolution;
    vec2 cellIndex = floor(pixelPos / uCellPx);
    vec2 cellUv = fract(pixelPos / uCellPx);
    vec2 cellCentrePx = (cellIndex + 0.5) * uCellPx;
    vec2 baseUv = cellCentrePx / uResolution;

    // ---- 2. wave: UV-space distortion of the clock-texture lookup ----
    // Ported from ReactBits' ASCIIText vertex displacement, but applied
    // directly to the sample coordinate instead of to mesh geometry.
    vec2 p = baseUv - 0.5;
    // Half-cycle across the plane (not a full 2*pi): a UV-space distortion
    // of a TEXTURE LOOKUP is a "backward" warp -- unlike displacing mesh
    // VERTICES (a "forward" warp, which reads as smooth continuous bending
    // of the same ink), sampling a full sine period of offset across one
    // glyph's own height reshapes it almost beyond recognition. A gentler
    // spatial frequency plus a small amplitude keeps this reading as a
    // waving plane rather than a scramble.
    float freq = 3.14159265;
    float t = uTime;
    float dx = sin(t * 5.0 + p.y * freq) * 0.014 * uK;
    float dy = cos(t * 5.0 + p.x * freq) * 0.006 * uK;
    float scalePulse = 1.0 + sin(t * 5.0) * uK * 0.02;
    vec2 waved = p * scalePulse + vec2(dx, -dy);

    // ---- 3. tilt: 2D projective warp approximating rotation ----------
    vec2 tp = waved * vec2(aspect, 1.0);
    float denom = 1.0 + uRot.y * tp.x * uPerspective + uRot.x * tp.y * uPerspective;
    denom = max(denom, 0.35); // keep the divide bounded, never inverts/folds
    vec2 warped = tp / denom;
    // Small shear on top of the projective divide -- reads as the plane
    // twisting slightly, not just receding.
    warped.x += uRot.y * tp.y * 0.12;
    warped.y += uRot.x * tp.x * 0.12;
    warped.x /= aspect;

    vec2 sampleUv = warped + 0.5;

    // ---- 4. clock luminance at the (distorted) cell centre ------------
    // The original's per-channel RGB offset ("chromatic aberration") is
    // folded into a single scalar luminance perturbation here -- three
    // independently-dilated samples averaged together -- instead of being
    // written out as separate colour channels, so it can never show up as
    // a visible colour fringe: only as a slight per-cell luminance/glyph
    // wobble, exactly like the old (correct) two-pass version intended.
    float r = dilatedAlpha(source, sampleUv + uChroma, uDilate);
    float g = dilatedAlpha(source, sampleUv, uDilate);
    float b = dilatedAlpha(source, sampleUv - uChroma, uDilate);
    float lum = clamp((r + g + b) / 3.0, 0.0, 1.0);

    // ---- 5. luminance -> glyph index -----------------------------------
    // DIRECT, not inverted: charset[0] is ' ' (emptiest), charset[last] is
    // the densest glyph -- a brighter cell centre walks further into the
    // dense tail of the string.
    float idxF = clamp(floor(lum * (uGlyphCount - 1.0) + 0.5), 0.0, uGlyphCount - 1.0);

    // Inset the in-cell sample point away from the cell's own edges --
    // `atlas` is sampled bilinearly and adjacent charset glyphs sit
    // immediately next to each other in the same strip.
    vec2 insetUv = mix(vec2(0.01), vec2(0.99), cellUv);
    float atlasU = (idxF + insetUv.x) / uGlyphCount;
    float atlasV = insetUv.y;
    vec2 atlasUv = vec2(atlasU, atlasV);

    float glyphAlpha = dilatedAlpha(atlas, atlasUv, uGlyphDilate);

    // Empty cell (below luminance threshold): nothing drawn.
    float gate = step(uLumThreshold, lum);
    glyphAlpha *= gate;

    // ---- 6. colour: 3-stop radial gradient, hue-rotated ---------------
    // Per-PIXEL (qt_TexCoord0), not per-cell, so the gradient reads as a
    // smooth field behind the glyph mosaic rather than stepping per cell.
    vec2 centred = (qt_TexCoord0 - 0.5) * vec2(aspect, 1.0);
    float gradT = clamp(length(centred) * 1.4, 0.0, 1.0);
    vec3 baseColor = gradT < 0.5
        ? mix(colorA.rgb, colorB.rgb, gradT * 2.0)
        : mix(colorB.rgb, colorC.rgb, (gradT - 0.5) * 2.0);
    vec3 finalColor = hueRotate(baseColor, uHue);

    fragColor = vec4(finalColor * glyphAlpha, glyphAlpha) * qt_Opacity;
}
