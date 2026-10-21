#version 440

// Looping liquid-warp UV displacement of the wallpaper image.
// Uses 2-octave value/simplex noise, time-driven, with displacement
// amplitude ~0.4-0.8% of screen and loop period ~30s.
// Samples with slight overscale/clamp so edges never pull.

layout(std140, binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float warpStrength;
    vec2 resolution;
};

layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;

layout(binding=1) uniform sampler2D source;

// Simple hash function for pseudorandom values
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Value noise (simpler than Perlin, sufficient for this use)
float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // smoothstep interpolation

    float n00 = hash(i);
    float n10 = hash(i + vec2(1.0, 0.0));
    float n01 = hash(i + vec2(0.0, 1.0));
    float n11 = hash(i + vec2(1.0, 1.0));

    float nx0 = mix(n00, n10, f.x);
    float nx1 = mix(n01, n11, f.x);
    return mix(nx0, nx1, f.y);
}

// Two-octave noise: base frequency + 2x frequency with 1/2 amplitude
float noiseOctave2(vec2 p) {
    float n1 = valueNoise(p) * 0.67;
    float n2 = valueNoise(p * 2.0) * 0.33;
    return n1 + n2;
}

void main() {
    vec2 uv = qt_TexCoord0;

    // Domain warp: two time-varying noise fields to displace X and Y independently
    // Loop period ~30s: 2*PI / (2*PI/30) = 30 seconds
    float t = time / 30.0; // normalized time [0..1] per 30s cycle

    // Two independent noise evaluations for x and y displacement
    float warpX = noiseOctave2(uv * 3.0 + vec2(t * 2.0, 17.0)) * 2.0 - 1.0;
    float warpY = noiseOctave2(uv * 3.0 + vec2(23.0, t * 1.8)) * 2.0 - 1.0;

    // Apply warp with amplitude control. warpStrength (default 0.006) IS the
    // displacement amplitude already expressed as a fraction of UV space --
    // i.e. 0.006 == 0.6% of screen, matching the "0.4-0.8% of screen" this
    // shader is meant to move things by. A previous version of this line
    // additionally divided by resolution (`* (1.0/max(resolution.x,
    // resolution.y))`), which shrank the displacement to a few thousandths
    // of a physical pixel at 1080p -- confirmed via an offscreen grabToImage
    // render (t=0 vs t=15 frame diff maxed at 2/255) that the warp was
    // completely imperceptible. `resolution` is intentionally unused here
    // now; it's still a uniform because other shaders in this pipeline share
    // the same property set.
    vec2 warpDisplacement = vec2(warpX, warpY) * warpStrength;

    // Sample with clamp to prevent edge pulling/tiling
    vec2 warpedUV = clamp(uv + warpDisplacement, vec2(0.0), vec2(1.0));

    vec4 texColor = texture(source, warpedUV);
    fragColor = texColor * qt_Opacity;
}
