// Offline render check: runs the plugin's two shaders through the same
// sample -> downscale -> blur -> glass pipeline as src/GlassPass.cpp, in a
// headless EGL/GLES3 context, over a raw RGBA backdrop. No Hyprland involved.
//
// usage: glass_render_test <glass.frag> <glass_blur.frag> <backdrop.rgba> <w> <h>
//        <out.rgba> <x> <y> <bw> <bh> <radius> <bezel> <refraction 0..1> <dispersion> <specular> <lightAngleDeg>
//        [<surface.rgba> <glass_alpha.frag>]
//        (env GLASS_BLUR = body blur px, default 28; GLASS_THRESHOLD = alpha gate, default 0.02)
//        (env GLASS_FEATHER=1 runs the feather treatment (alpha mode only): blur weight = clamp(alpha *
//         GLASS_FEATHER_GAIN, 0, 1), default gain 4.5; featherNamespaces in the plugin)
// Without the surface arguments the shape is the rounded rect (shape = "rect" in the plugin).
// With them the shape is the surface's own alpha (shape = "alpha", the plugin default): the
// surface is a bw x bh premultiplied RGBA raw image, the same box as the glass.
// Chain several panels by feeding each run's out.rgba back in as the next backdrop.
// Backdrop, surface and output are raw RGBA in file row order (row 0 = top of the image).
#include "../src/GlassMath.hpp"
#include <EGL/egl.h>
#include <GLES3/gl3.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

static std::string slurp(const char* p) {
    std::ifstream f(p);
    std::stringstream s;
    s << f.rdbuf();
    return s.str();
}

static GLuint compile(GLenum t, const std::string& src) {
    GLuint s = glCreateShader(t);
    const char* c = src.c_str();
    glShaderSource(s, 1, &c, nullptr);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[2048];
        glGetShaderInfoLog(s, sizeof log, nullptr, log);
        std::fprintf(stderr, "shader compile failed:\n%s\n", log);
        std::exit(2);
    }
    return s;
}

static const char* VERT = R"(#version 300 es
uniform mat3 proj;
in vec2 pos;
in vec2 texcoord;
out vec2 v_texcoord;
void main() {
    gl_Position = vec4(proj * vec3(pos, 1.0), 1.0);
    v_texcoord = texcoord;
})";

static GLuint program(const std::string& frag) {
    GLuint p = glCreateProgram();
    glAttachShader(p, compile(GL_VERTEX_SHADER, VERT));
    glAttachShader(p, compile(GL_FRAGMENT_SHADER, frag));
    glBindAttribLocation(p, 0, "pos");
    glBindAttribLocation(p, 1, "texcoord");
    glLinkProgram(p);
    GLint ok = 0;
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        std::fprintf(stderr, "link failed\n");
        std::exit(2);
    }
    return p;
}

struct Target {
    GLuint tex = 0, fbo = 0;
    int    w = 0, h = 0;
};

static Target makeTarget(int w, int h) {
    Target t;
    t.w = w;
    t.h = h;
    glGenTextures(1, &t.tex);
    glBindTexture(GL_TEXTURE_2D, t.tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glGenFramebuffers(1, &t.fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, t.fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, t.tex, 0);
    return t;
}

int main(int argc, char** argv) {
    if (argc != 17 && argc != 19) {
        std::fprintf(stderr, "bad args\n");
        return 1;
    }
    const bool alphaMode = argc == 19;
    const std::string glassSrc = slurp(argv[1]), blurSrc = slurp(argv[2]);
    const std::string alphaSrc = alphaMode ? slurp(argv[18]) : std::string();
    const int W = std::atoi(argv[4]), H = std::atoi(argv[5]);
    const float bx = std::atof(argv[7]), by = std::atof(argv[8]), bw = std::atof(argv[9]), bh = std::atof(argv[10]);
    const float radius = std::atof(argv[11]), bezel = std::atof(argv[12]);
    const float refr = std::atof(argv[13]), disp = std::atof(argv[14]), spec = std::atof(argv[15]);
    const float blurPx = std::getenv("GLASS_BLUR") ? std::atof(std::getenv("GLASS_BLUR")) : 28.f;
    const float alphaThr = std::getenv("GLASS_THRESHOLD") ? std::atof(std::getenv("GLASS_THRESHOLD")) : 0.02f;
    const bool  feather  = std::getenv("GLASS_FEATHER") && std::atoi(std::getenv("GLASS_FEATHER")) == 1;
    const float featherGain = std::getenv("GLASS_FEATHER_GAIN") ? std::atof(std::getenv("GLASS_FEATHER_GAIN")) : 4.5f;
    if (feather && !alphaMode) {
        std::fprintf(stderr, "feather needs the surface arguments (alpha mode)\n");
        return 1;
    }

    EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    eglInitialize(dpy, nullptr, nullptr);
    eglBindAPI(EGL_OPENGL_ES_API);
    const EGLint cfgAttr[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE};
    EGLConfig    cfg;
    EGLint       n = 0;
    eglChooseConfig(dpy, cfgAttr, &cfg, 1, &n);
    const EGLint pbAttr[] = {EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE};
    EGLSurface   surf = eglCreatePbufferSurface(dpy, cfg, pbAttr);
    const EGLint ctxAttr[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    EGLContext   ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctxAttr);
    if (!n || surf == EGL_NO_SURFACE || ctx == EGL_NO_CONTEXT || !eglMakeCurrent(dpy, surf, surf, ctx)) {
        std::fprintf(stderr, "EGL setup failed\n");
        return 3;
    }
    std::fprintf(stderr, "GL: %s\n", (const char*)glGetString(GL_RENDERER));

    // "Monitor framebuffer": the backdrop, row 0 = top.
    std::vector<unsigned char> img(W * H * 4);
    {
        std::ifstream f(argv[3], std::ios::binary);
        f.read((char*)img.data(), img.size());
    }
    Target screen = makeTarget(W, H);
    glBindTexture(GL_TEXTURE_2D, screen.tex);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, img.data());

    GLuint gp = program(glassSrc), bp = program(blurSrc), fp = alphaMode ? program(alphaSrc) : 0;

    // Quad: pos in [0,1], texcoord (0,0) at the top-left, same convention as Hyprland's VAO.
    const float quad[] = {0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 1, 1, 1, 1};
    GLuint      vao, vbo;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glGenBuffers(1, &vbo);
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 16, (void*)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 16, (void*)8);

    const int  pad   = GlassMath::samplePadding(bezel, refr, disp, blurPx);
    const int  fullW = (int)bw + 2 * pad, fullH = (int)bh + 2 * pad;
    const int  blurW = std::max(1, fullW / 2), blurH = std::max(1, fullH / 2);
    Target     sharp = makeTarget(fullW, fullH), blurT = makeTarget(blurW, blurH), tmp = makeTarget(blurW, blurH);
    const float bezelPx = std::max(1.f, bezel);
    const float alphaSigma = (float)GlassMath::alphaSigmaPx(bezelPx);

    // Surface texture (alpha mode): the layer surface's own pixels, box-sized, on unit 2.
    GLuint surfTex = 0;
    Target alphaT, sharpAlphaT;
    if (alphaMode) {
        std::vector<unsigned char> surf(bw * bh * 4);
        {
            std::ifstream f(argv[17], std::ios::binary);
            f.read((char*)surf.data(), surf.size());
        }
        glGenTextures(1, &surfTex);
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, surfTex);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, (GLsizei)bw, (GLsizei)bh, 0, GL_RGBA, GL_UNSIGNED_BYTE, surf.data());
        glActiveTexture(GL_TEXTURE0);

        // 1b. surface alpha -> box-sized FB (plugin step a), then -> padded half-res (step b)
        const float full2[9] = {2, 0, 0, 0, 2, 0, -1, -1, 1};
        glDisable(GL_BLEND);
        sharpAlphaT = makeTarget(bw, bh);
        glBindFramebuffer(GL_FRAMEBUFFER, sharpAlphaT.fbo);
        glViewport(0, 0, bw, bh);
        glUseProgram(fp);
        glUniformMatrix3fv(glGetUniformLocation(fp, "proj"), 1, GL_FALSE, full2);
        glUniform1i(glGetUniformLocation(fp, "srcTex"), 2);
        glUniform1i(glGetUniformLocation(fp, "srcIsSurface"), 1);
        glUniform2f(glGetUniformLocation(fp, "boxSize"), bw, bh);
        glUniform2f(glGetUniformLocation(fp, "padSize"), bw, bh);
        glUniform1f(glGetUniformLocation(fp, "pad"), 0.f);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

        alphaT = makeTarget(blurW, blurH);
        glBindFramebuffer(GL_FRAMEBUFFER, alphaT.fbo);
        glViewport(0, 0, blurW, blurH);
        glActiveTexture(GL_TEXTURE2);
        glBindTexture(GL_TEXTURE_2D, sharpAlphaT.tex);
        glUniform1i(glGetUniformLocation(fp, "srcIsSurface"), 0);
        glUniform2f(glGetUniformLocation(fp, "boxSize"), bw, bh);
        glUniform2f(glGetUniformLocation(fp, "padSize"), (float)fullW, (float)fullH);
        glUniform1f(glGetUniformLocation(fp, "pad"), (float)pad);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

        // 1c. blur the alpha field: blurRadius in half-res texels = alphaSigma (see plugin)
        const float full[9] = {2, 0, 0, 0, 2, 0, -1, -1, 1};
        glUseProgram(bp);
        glUniformMatrix3fv(glGetUniformLocation(bp, "proj"), 1, GL_FALSE, full);
        glUniform1i(glGetUniformLocation(bp, "tex"), 0);
        glUniform1f(glGetUniformLocation(bp, "blurRadius"), alphaSigma);
        glActiveTexture(GL_TEXTURE0);
        glBindFramebuffer(GL_FRAMEBUFFER, tmp.fbo);
        glBindTexture(GL_TEXTURE_2D, alphaT.tex);
        glUniform2f(glGetUniformLocation(bp, "direction"), 1.f / blurW, 0.f);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glBindFramebuffer(GL_FRAMEBUFFER, alphaT.fbo);
        glBindTexture(GL_TEXTURE_2D, tmp.tex);
        glUniform2f(glGetUniformLocation(bp, "direction"), 0.f, 1.f / blurH);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }

    // 1. copy backdrop region (clamped), as the plugin does with glBlitFramebuffer
    int sx0 = (int)bx - pad, sy0 = (int)by - pad, sx1 = sx0 + fullW, sy1 = sy0 + fullH;
    int dx0 = 0, dy0 = 0, dx1 = fullW, dy1 = fullH;
    bool clamped = false;
    if (sx0 < 0) { dx0 -= sx0; sx0 = 0; clamped = true; }
    if (sy0 < 0) { dy0 -= sy0; sy0 = 0; clamped = true; }
    if (sx1 > W) { dx1 -= sx1 - W; sx1 = W; clamped = true; }
    if (sy1 > H) { dy1 -= sy1 - H; sy1 = H; clamped = true; }
    if (clamped) {
        glBindFramebuffer(GL_FRAMEBUFFER, sharp.fbo);
        glClearColor(0, 0, 0, 0);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    glBindFramebuffer(GL_READ_FRAMEBUFFER, screen.fbo);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, sharp.fbo);
    glBlitFramebuffer(sx0, sy0, sx1, sy1, dx0, dy0, dx1, dy1, GL_COLOR_BUFFER_BIT, GL_LINEAR);

    // 2. downscale + separable blur
    glBindFramebuffer(GL_READ_FRAMEBUFFER, sharp.fbo);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, blurT.fbo);
    glBlitFramebuffer(0, 0, fullW, fullH, 0, 0, blurW, blurH, GL_COLOR_BUFFER_BIT, GL_LINEAR);

    const float texels = blurPx / 2.f;
    if (texels >= 0.5f) {
        const float full[9] = {2, 0, 0, 0, 2, 0, -1, -1, 1};
        glDisable(GL_BLEND);
        glUseProgram(bp);
        glUniformMatrix3fv(glGetUniformLocation(bp, "proj"), 1, GL_FALSE, full);
        glUniform1i(glGetUniformLocation(bp, "tex"), 0);
        glUniform1f(glGetUniformLocation(bp, "blurRadius"), texels);
        glViewport(0, 0, blurW, blurH);
        glActiveTexture(GL_TEXTURE0);
        glBindFramebuffer(GL_FRAMEBUFFER, tmp.fbo);
        glBindTexture(GL_TEXTURE_2D, blurT.tex);
        glUniform2f(glGetUniformLocation(bp, "direction"), 1.f / blurW, 0.f);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        glBindFramebuffer(GL_FRAMEBUFFER, blurT.fbo);
        glBindTexture(GL_TEXTURE_2D, tmp.tex);
        glUniform2f(glGetUniformLocation(bp, "direction"), 0.f, 1.f / blurH);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }

    // 3. glass quad over the box, premultiplied blend. Row 0 = top, so clip y is flipped
    // only to land row index == y (the readback below keeps that order).
    glBindFramebuffer(GL_FRAMEBUFFER, screen.fbo);
    glViewport(0, 0, W, H);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    glUseProgram(gp);
    // column-major mat3 mapping unit quad -> pixel box -> clip space (y not flipped: row index == GL y)
    const float sxn = 2.f * bw / W, syn = 2.f * bh / H;
    const float m[9] = {sxn, 0, 0, 0, syn, 0, 2.f * bx / W - 1.f, 2.f * by / H - 1.f, 1};
    glUniformMatrix3fv(glGetUniformLocation(gp, "proj"), 1, GL_FALSE, m);
    glUniform1i(glGetUniformLocation(gp, "sharpTex"), 0);
    glUniform1i(glGetUniformLocation(gp, "blurTex"), 1);
    glUniform2f(glGetUniformLocation(gp, "boxSize"), bw, bh);
    glUniform1f(glGetUniformLocation(gp, "pad"), (float)pad);
    glUniform1f(glGetUniformLocation(gp, "radius"), radius);
    glUniform1f(glGetUniformLocation(gp, "bezel"), bezel);
    glUniform1f(glGetUniformLocation(gp, "refraction"), refr);
    glUniform1f(glGetUniformLocation(gp, "dispersion"), disp);
    glUniform1f(glGetUniformLocation(gp, "specular"), spec);
    glUniform1f(glGetUniformLocation(gp, "lightAngle"), std::atof(argv[16]) * M_PI / 180.0);
    glUniform1f(glGetUniformLocation(gp, "alpha"), 1.f);
    glUniform1i(glGetUniformLocation(gp, "alphaMode"), alphaMode ? 1 : 0);
    glUniform1f(glGetUniformLocation(gp, "alphaThreshold"), alphaThr);
    glUniform1f(glGetUniformLocation(gp, "alphaSigma"), alphaSigma);
    glUniform2f(glGetUniformLocation(gp, "alphaTexel"), 1.f / blurW, 1.f / blurH);
    glUniform1i(glGetUniformLocation(gp, "featherMode"), feather ? 1 : 0);
    glUniform1f(glGetUniformLocation(gp, "featherGain"), featherGain);
    glUniform1i(glGetUniformLocation(gp, "sharpAlphaTex"), 2);
    glUniform1i(glGetUniformLocation(gp, "alphaTex"), 3);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, sharp.tex);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, blurT.tex);
    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D, alphaMode ? sharpAlphaT.tex : 0);
    glActiveTexture(GL_TEXTURE3);
    glBindTexture(GL_TEXTURE_2D, alphaMode ? alphaT.tex : 0);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    std::vector<unsigned char> out(W * H * 4);
    glBindFramebuffer(GL_FRAMEBUFFER, screen.fbo);
    glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, out.data());
    std::ofstream o(argv[6], std::ios::binary);
    o.write((const char*)out.data(), out.size());
    std::fprintf(stderr, "glGetError=0x%x\n", glGetError());
    return 0;
}
