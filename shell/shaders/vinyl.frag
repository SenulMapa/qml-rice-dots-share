#version 440

layout(std140, binding=0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float spinAngle;
    float grooveDensity;
    vec3 vinylColor;
    vec3 highlightColor;
};

layout(location=0) in vec2 qt_TexCoord0;
layout(location=0) out vec4 fragColor;

// Item is always sized square (diameter x diameter) by its QML owner, so
// no aspect correction is needed here -- UV space is already circular.
void main() {
    vec2 uv = qt_TexCoord0 - vec2(0.5);
    float r = length(uv);

    if (r > 0.5) {
        fragColor = vec4(0.0);
        return;
    }

    float ang = atan(uv.y, uv.x);

    // Concentric groove texture -- a plain radial sine ring pattern, no
    // constant arrays (this build's GLSL 100/120 variants reject them, per
    // shaders/dither.frag's own note).
    float groove = 0.5 + 0.5 * sin(r * grooveDensity);
    float shade = mix(0.86, 1.0, groove);

    // A single rotating specular band -- reads as a light source sweeping
    // the disc's surface as it spins, not a static shine.
    float sweep = cos(ang - spinAngle);
    float specular = pow(max(sweep, 0.0), 10.0) * smoothstep(0.5, 0.12, r);

    vec3 color = vinylColor * shade + highlightColor * specular * 0.55;

    // Soft 1px-ish antialiased outer edge instead of a hard circle cut.
    float edge = smoothstep(0.5, 0.485, r);

    fragColor = vec4(color, 1.0) * edge * qt_Opacity;
}
