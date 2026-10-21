#version 300 es
precision highp float;

// qmlrice-glass: one separable Gaussian pass over the downscaled backdrop copy.
// Kernel reaches 16 texels (2 sigma at a 28 px body blur, half-res), so the body is not clipped.

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform sampler2D tex;
uniform vec2  direction;   // (1/width, 0) or (0, 1/height)
uniform float blurRadius;  // kernel radius in texels

void main() {
    float sigma = max(blurRadius * 0.5, 0.001);
    float k = -0.5 / (sigma * sigma);
    int taps = int(min(ceil(blurRadius), 16.0));

    vec4 sum = texture(tex, v_texcoord);
    float wsum = 1.0;
    for (int i = 1; i <= 16; i++) {
        if (i > taps) break;
        float w = exp(float(i * i) * k);
        vec2 o = direction * float(i);
        sum += w * (texture(tex, v_texcoord + o) + texture(tex, v_texcoord - o));
        wsum += 2.0 * w;
    }
    fragColor = sum / wsum;
}
