#version 440

// DitherVeil port. See wallpaper/DitherWallpaper.qml for the CPU-side wiring
// (bake management, palette derivation, click-burst uniforms, intro
// animation) and tools/dither-bake.py for the floyd/atkinson error-diffusion
// bake this shader samples for the `diffused` pattern mode.
//
// Hard constraint (see repo notes): this must compile to GLSL 100es/120 (the
// NVIDIA GL context Qt picks these variants for) as well as 150/HLSL50/MSL12
// via `qsb --glsl "100 es,120,150" --hlsl 50 --msl 12`. That rules out
// integer bitwise ops, texelFetch/textureLod, and const arrays -- the Bayer
// matrix and blue-noise stipple are texture lookups (wallpaper/textures/
// bayer8.png, noise64.png), not computed bit-tricks or arrays.

layout(std140, binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float cellSize;
    vec2 resolution;
    float waveAmp;
    float waveSpeed;
    bool waveOn;
    float blackPoint;
    vec3 inkColor;
    vec3 paperColor;
    float patternMode;   // 0 bayer, 1 noise, 2 lines, 3 diffused (floyd/atkinson)
    float paletteMode;   // 0 duotone, 1 rgb
    float levels;
    float contrast;
    float brightness;
    bool cellsValid;     // false: diffused pattern falls back to bayer
    float reverseMask;   // 0/1
    float rim;
    vec3 rimColor;
    float introT;        // 0 = fully hidden (ink), >=1 = intro finished
    vec4 burst0;         // x, y (px), startTime (shaderTime, <0 = inactive), reach (px)
    vec4 burst1;
    vec4 burst2;
    vec4 burst3;
};

layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;

// Unwarped source image -- the dither CELL GRID always samples this,
// regardless of whether the warp effect is enabled, so cells never ride the
// warp (see warp option (a) note below `cellUv`). `warpedSource` is the same
// image after warp.frag's domain displacement when warp is enabled
// (identical to `source` when it's off) -- only the revealed full-colour
// photo samples that one.
layout(binding=1) uniform sampler2D source;
// Low-res (~1/2 screen) reveal-intensity trail buffer -- see shaders/trail.frag.
layout(binding=2) uniform sampler2D trailMask;
// Baked error-diffused cell levels (tools/dither-bake.py). One texel per
// dither cell, sampled with NEAREST (see the Image wiring in
// DitherWallpaper.qml) so cells snap to crisp two-colour blocks, never grey
// anti-aliased dots.
layout(binding=3) uniform sampler2D cellsTex;
// Static 8x8 ordered-dither threshold matrix, NEAREST-sampled.
layout(binding=4) uniform sampler2D bayer8Tex;
// Static 64x64 blue-noise (void-and-cluster) threshold matrix, NEAREST-sampled.
layout(binding=5) uniform sampler2D noise64Tex;
// Warped image (see `source` comment above) -- only the reveal's full-colour
// photo sample uses this.
layout(binding=6) uniform sampler2D warpedSource;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// bayer8Tex/noise64Tex texels are already NEAREST-filtered by the QML side
// (Image.smooth: false), so a plain fract()-wrapped lookup addressing the
// cell's own bucket is enough -- no textureLod/texelFetch needed.
float bayerAt(vec2 cell) {
    return texture(bayer8Tex, (mod(cell, 8.0) + 0.5) / 8.0).r;
}
float noiseAt(vec2 cell) {
    return texture(noise64Tex, (mod(cell, 64.0) + 0.5) / 64.0).r;
}

// quantize(v, t): DitherVeil's ordered-dither step quantization.
float quantizeChannel(float v, float t) {
    float steps = max(levels - 1.0, 1.0);
    float s = v * steps;
    float base = floor(s);
    return min(base + step(t, s - base), steps) / steps;
}

void main() {
    vec2 uv = qt_TexCoord0;

    // Idle wave: UV displacement of both the source sample and the dither
    // cell grid (kept from the prior ordered-dither-only shader -- still a
    // valid look with DitherVeil's patterns layered on top).
    vec2 warp = vec2(0.0);
    if (waveOn) {
        float t = time * waveSpeed;
        warp = vec2(sin(uv.y * 10.0 + t), cos(uv.x * 8.0 + t * 0.8)) * waveAmp * 0.01;
    }
    vec2 warpedUV = clamp(uv + warp, vec2(0.0), vec2(1.0));

    // Cell grid is derived from the UNWARPED uv -- warp option (a) (see the
    // warp-integration note in DitherWallpaper.qml): only the colour-photo
    // sample used for the reveal rides the warp; the pattern cell grid
    // (bayer/noise/lines threshold lookups AND the baked floyd/atkinson
    // cellsTex lookup) stays static, so error-diffused dots never crawl and
    // the ordered patterns' own cell alignment stays crisp. `px` doubles as
    // the pixel-space coordinate the click-burst shockwave measures against.
    vec2 px = uv * resolution;
    vec2 cell = floor(px / cellSize);
    vec2 cellCenter = (cell + 0.5) * cellSize;
    vec2 cellUv = clamp(cellCenter / resolution, vec2(0.0), vec2(1.0));

    vec4 texColor = texture(source, cellUv);
    float rawLum = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));

    // Legacy black-point crush (owner-tuned per-wallpaper control, kept as
    // its own settings slider) feeds into DitherVeil's own grade curve.
    float afterBlack = clamp((rawLum - blackPoint) / max(1.0 - blackPoint, 0.0001), 0.0, 1.0);
    float graded = pow(clamp((afterBlack - 0.5) * contrast + 0.5 + brightness, 0.0, 1.0), 1.6);

    // The revealed full-colour photo DOES ride the warp (option (a)'s "warp
    // the colour-photo sample only") -- sampled at full per-pixel warpedUV
    // from the already-warped `warpedSource` texture, not snapped to the
    // cell grid, so the reveal itself looks like a live rippling window onto
    // the source image while the dither cells above stay perfectly static.
    vec4 photoColor = texture(warpedSource, warpedUV);
    float photoRawLum = dot(photoColor.rgb, vec3(0.299, 0.587, 0.114));
    float photoAfterBlack = clamp((photoRawLum - blackPoint) / max(1.0 - blackPoint, 0.0001), 0.0, 1.0);
    float photoGraded = pow(clamp((photoAfterBlack - 0.5) * contrast + 0.5 + brightness, 0.0, 1.0), 1.6);

    bool useDiffused = (patternMode > 2.5) && cellsValid;
    bool useLines = (patternMode > 1.5) && (patternMode < 2.5);
    bool useNoise = (patternMode > 0.5) && (patternMode < 1.5);
    // patternMode == 0, or a diffused request with no bake ready yet, both
    // fall through to bayer.

    vec3 ditheredColor;
    if (useDiffused) {
        float level = texture(cellsTex, cellUv).r;
        ditheredColor = mix(inkColor, paperColor, level);
        if (paletteMode > 0.5) {
            // rgb palette: the CPU bake is luma-only (see the ditherPaletteMode
            // comment in core/Config.qml) -- duotone is the faithful result
            // for diffused patterns.
        }
    } else if (useLines) {
        float f = (mod(cell.x + cell.y, 6.0) + 0.5) / 6.0;
        float order = bayerAt(cell);
        float t = clamp(abs(f * 2.0 - 1.0) + (order - 0.5) * (2.0 / 6.0), 0.0, 1.0);
        float level = step(t, graded);
        ditheredColor = mix(inkColor, paperColor, level);
    } else {
        float t = useNoise ? noiseAt(cell) : bayerAt(cell);
        if (paletteMode > 0.5) {
            ditheredColor = vec3(
                quantizeChannel(texColor.r, t),
                quantizeChannel(texColor.g, t),
                quantizeChannel(texColor.b, t));
        } else {
            float level = quantizeChannel(graded, t);
            ditheredColor = mix(inkColor, paperColor, level);
        }
    }

    // ---- reveal mask: recursive low-res trail buffer + click-burst rings --
    vec2 maskWarp = (vec2(hash(uv * 40.0 + time * 0.15),
                           hash(uv * 40.0 + 91.0 + time * 0.15)) - 0.5) * 0.012;
    float trailRaw = texture(trailMask, clamp(uv + maskWarp, vec2(0.0), vec2(1.0))).r;

    // Unrolled (not a loop over an array -- GLSL 100es rejects array
    // constructors/dynamic array indexing on this NVIDIA GL context, see the
    // repo's shader constraints notes) shockwave contribution per click.
    float shockwave = 0.0;
    {
        vec4 b = burst0;
        if (b.z >= 0.0) {
            float k = clamp((time - b.z) / 1.2, 0.0, 1.0);
            float radius = b.w * sin(k * 3.14159265 * 0.5);
            float strength = 1.0 - k * k * k;
            float width = max(60.0, radius * 0.9);
            float d = abs(length(px - b.xy) - radius);
            float contrib = (k < 1.0) ? strength * (1.0 - smoothstep(0.0, width, d)) : 0.0;
            shockwave = max(shockwave, contrib);
        }
    }
    {
        vec4 b = burst1;
        if (b.z >= 0.0) {
            float k = clamp((time - b.z) / 1.2, 0.0, 1.0);
            float radius = b.w * sin(k * 3.14159265 * 0.5);
            float strength = 1.0 - k * k * k;
            float width = max(60.0, radius * 0.9);
            float d = abs(length(px - b.xy) - radius);
            float contrib = (k < 1.0) ? strength * (1.0 - smoothstep(0.0, width, d)) : 0.0;
            shockwave = max(shockwave, contrib);
        }
    }
    {
        vec4 b = burst2;
        if (b.z >= 0.0) {
            float k = clamp((time - b.z) / 1.2, 0.0, 1.0);
            float radius = b.w * sin(k * 3.14159265 * 0.5);
            float strength = 1.0 - k * k * k;
            float width = max(60.0, radius * 0.9);
            float d = abs(length(px - b.xy) - radius);
            float contrib = (k < 1.0) ? strength * (1.0 - smoothstep(0.0, width, d)) : 0.0;
            shockwave = max(shockwave, contrib);
        }
    }
    {
        vec4 b = burst3;
        if (b.z >= 0.0) {
            float k = clamp((time - b.z) / 1.2, 0.0, 1.0);
            float radius = b.w * sin(k * 3.14159265 * 0.5);
            float strength = 1.0 - k * k * k;
            float width = max(60.0, radius * 0.9);
            float d = abs(length(px - b.xy) - radius);
            float contrib = (k < 1.0) ? strength * (1.0 - smoothstep(0.0, width, d)) : 0.0;
            shockwave = max(shockwave, contrib);
        }
    }

    float mask = max(clamp(trailRaw, 0.0, 1.0), shockwave);
    float shown = mix(mask, 1.0 - mask, reverseMask);

    vec3 leveledColor = photoRawLum > 0.0001
        ? photoColor.rgb * (photoGraded / photoRawLum) : vec3(0.0);
    leveledColor = clamp(leveledColor, 0.0, 1.0);

    // Dissolving rim: order from bayer(cell.yx) per the reference.
    float order = bayerAt(cell.yx);
    float low = order * (1.0 - rim);
    vec3 color = ditheredColor;
    color = mix(color, rimColor, step(low, shown) * step(0.001, rim));
    color = mix(color, leveledColor, step(low + rim, shown));

    // ---- intro dissolve: radial + bayer threshold cross-dissolve from ink -
    vec2 aspect = vec2(resolution.x / max(resolution.y, 1.0), 1.0);
    float spread = length((cellUv - 0.5) * aspect) / max(length(aspect * 0.5), 0.0001);
    float introOrder = bayerAt(cell + vec2(3.0, 5.0));
    float appear = step(spread * 0.72 + introOrder * 0.28, introT * 1.001);
    vec3 finalColor = mix(inkColor, color, appear);

    fragColor = vec4(finalColor, texColor.a) * qt_Opacity;
}
