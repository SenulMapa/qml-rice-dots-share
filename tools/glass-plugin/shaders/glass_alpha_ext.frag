#version 300 es
#extension GL_OES_EGL_image_external_essl3 : require
precision highp float;

// qmlrice-glass: the DMA-buf variant of glass_alpha.frag. A dma-buf surface texture is an
// EGLImage bound to GL_TEXTURE_EXTERNAL_OES, so it needs samplerExternalOES (the same way Hyprland's
// own ext fragment shader samples it). Only the surface is ever read through this shader.
// Same box mapping and output as glass_alpha.frag (srcIsSurface is always 1 here).

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform samplerExternalOES srcTex;
uniform vec2  boxSize;
uniform vec2  padSize;
uniform float pad;

void main() {
    vec2 p = v_texcoord * padSize - vec2(pad);
    vec2 uv = p / boxSize;
    float a = 0.0;
    if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0)
        a = texture(srcTex, uv).a;
    fragColor = vec4(a);
}
