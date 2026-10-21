#version 440

// Low-res reveal-intensity trail buffer -- DitherVeil-style capsule stroke
// reveal. Rendered recursively (this ShaderEffect's own ShaderEffectSource
// output is fed back in as `prevFrame`, see wallpaper/DitherWallpaper.qml's
// trailFeedback): each frame linearly fades the previous mask by dt/linger
// and deposits a soft capsule (segment from the previous brush position to
// the current one) so a fast-moving cursor draws a continuous stroke
// instead of a string of discrete dots.
//
// The brush position itself is still the owner's existing spring-damped
// springX/springY (core/MotionValue.qml, tuned response ~0.55s / zeta 0.7
// per DitherWallpaper.qml's comments) -- this shader only adds the DitherVeil
// capsule-distance mask shape and hold/linger timing on top of that
// existing, owner-tuned motion, per the port brief's instruction to keep the
// owner's tuned spring feel rather than replace it with a new tau.

layout(std140, binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 cursorUV;      // current spring-lagged brush position
    vec2 prevCursorUV;  // previous frame's spring-lagged brush position
    float radius;        // already presence-scaled: revealRadius*(0.45+0.55*presence)
    float softness;
    float linger;
    float presence;      // 0..1 eased cursor-hover presence
    float dt;
    float time;
    vec2 resolution;
};

layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;

layout(binding=1) uniform sampler2D prevFrame;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Distance from `p` to the segment [a,b].
float segmentDistance(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    float len2 = max(dot(ab, ab), 1e-6);
    float t = clamp(dot(p - a, ab) / len2, 0.0, 1.0);
    vec2 proj = a + ab * t;
    return length(p - proj);
}

void main() {
    vec2 uv = qt_TexCoord0;

    // Slight noise advection on the feedback read -- a tiny per-frame jitter
    // that, compounded recursively, makes the decaying trail warp/wobble
    // instead of shrinking as a perfect static blob (the "fluid" edge the
    // owner asked for).
    vec2 flow = vec2(hash(uv * 3.0 + time * 0.10),
                      hash(uv * 3.0 + 17.0 + time * 0.10)) - 0.5;
    vec2 prevUV = uv + flow * (1.5 / resolution.x);
    float prev = texture(prevFrame, clamp(prevUV, vec2(0.0), vec2(1.0))).r;

    // Linear linger fade: trail = max(prev - fade, 0), fade = dt/linger.
    float fade = dt / max(linger, 0.001);
    float trail = max(prev - fade, 0.0);

    // Aspect-correct capsule distance from the previous brush position to
    // the current one (a stroke segment, not a point), same HOLD band
    // widening DitherVeil uses so a fast stroke still reads as one
    // continuous soft ribbon rather than beads.
    vec2 aspect = vec2(resolution.x / max(resolution.y, 1.0), 1.0);
    vec2 p = (uv - 0.5) * aspect;
    vec2 a = (prevCursorUV - 0.5) * aspect;
    vec2 b = (cursorUV - 0.5) * aspect;
    float d = segmentDistance(p, a, b);

    const float HOLD = 1.6;
    float band = max(radius * softness, 1.0 / resolution.x) * HOLD;
    float deposit = clamp((radius - d) / band, 0.0, 1.0) * clamp(presence, 0.0, 1.0);

    float result = clamp(max(trail, deposit), 0.0, 1.0);
    fragColor = vec4(result, result, result, 1.0) * qt_Opacity;
}
