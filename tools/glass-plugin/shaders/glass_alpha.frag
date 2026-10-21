#version 300 es
precision highp float;

// qmlrice-glass: copies an alpha field from a source into a target through an explicit box mapping.
//   srcIsSurface == 1: the source is the layer surface texture, alpha in .a
//   srcIsSurface == 0: the source is our box-sized alpha FB, alpha in .r (its .a may be dropped by
//                      an XRGB framebuffer, so it is never read)
// The target covers the box plus `pad` px on every side (padSize = box + 2 pad). Outside the box the
// value is 0. Used twice in alpha mode: surface -> box-sized FB (pad 0), then box FB -> padded half-res.
// glass_alpha_ext.frag is the same thing for DMA-buf (GL_TEXTURE_EXTERNAL_OES) surface textures.

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform sampler2D srcTex;
uniform int   srcIsSurface;
uniform vec2  boxSize;      // surface size, framebuffer px
uniform vec2  padSize;      // target size, framebuffer px (box + 2 pad)
uniform float pad;          // padding around the box, px

void main() {
    vec2 p = v_texcoord * padSize - vec2(pad);  // box px
    vec2 uv = p / boxSize;
    float a = 0.0;
    if (uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0) {
        vec4 s = texture(srcTex, uv);
        a = (srcIsSurface == 1) ? s.a : s.r;
    }
    fragColor = vec4(a);
}
