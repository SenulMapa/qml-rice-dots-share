#include "GlassPass.hpp"
#include "GlassMath.hpp"
#include "Globals.hpp"
#include "shaders_embedded.hpp"

#include <GLES3/gl32.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Shader.hpp>
#include <hyprland/src/render/gl/GLFramebuffer.hpp>

using Render::GL::g_pHyprOpenGL;

namespace {
    constexpr int DOWNSCALE = 2; // the frosted body and the alpha field are blurred at half resolution

    // Matches the full-screen triangle-strip matrix the blur pass uses (see GlassPass draw()).
    constexpr std::array<float, 9> FULLSCREEN = {2.F, 0.F, 0.F, 0.F, 2.F, 0.F, -1.F, -1.F, 1.F};

    struct SGlassGL {
        SP<CShader>              glass = makeShared<CShader>();
        SP<CShader>              blur  = makeShared<CShader>();
        SP<CShader>              fill    = makeShared<CShader>(); // 2D source (surface SHM, or our box FB)
        SP<CShader>              fillExt = makeShared<CShader>(); // GL_TEXTURE_EXTERNAL_OES source (dma-buf surface)
        SP<Render::IFramebuffer> sharpAlphaFB, alphaFB, sharpFB, blurFB, tmpFB;
        GLuint                   sampler = 0; // linear/clamp sampler for units 2 and 3
        bool                     ready  = false;
        bool                     failed = false;
        bool                     extReady = false; // fillExt compiled; without it dma-buf layers get no glass

        GLint uBoxSize = -1, uPad = -1, uRadius = -1, uBezel = -1, uRefr = -1, uDisp = -1, uSpec = -1, uAngle = -1, uAlpha = -1, uSharp = -1, uBlurTex = -1;
        GLint uSharpAlpha = -1, uAlphaTex = -1, uAlphaMode = -1, uAlphaThr = -1, uAlphaSigma = -1, uAlphaTexel = -1;
        GLint uDir = -1, uBlurRadius = -1;
        GLint uFeatherMode = -1, uFeatherGain = -1;

        struct SFillLoc {
            GLint src = -1, isSurf = -1, box = -1, padSize = -1, pad = -1;
        };
        SFillLoc fillLoc, fillExtLoc;
    };

    SGlassGL g_gl;

    GLuint fbId(const SP<Render::IFramebuffer>& fb) {
        auto* gl = dynamic_cast<Render::GL::CGLFramebuffer*>(fb.get());
        return gl ? gl->getFBID() : 0;
    }

    void failOnce(const char* what) {
        if (g_gl.failed)
            return;
        g_gl.failed = true;
        HyprlandAPI::addNotification(PHANDLE, std::string("[qmlrice-glass] ") + what + " - glass disabled for this session", CHyprColor{1.0, 0.2, 0.2, 1.0}, 8000);
    }

    bool ensureShaders() {
        if (g_gl.ready)
            return true;
        if (g_gl.failed)
            return false;

        const auto& vert = g_pHyprOpenGL->m_shaders->TEXVERTSRC;
        if (!g_gl.glass->createProgram(vert, GLASS_FRAG, true) || !g_gl.blur->createProgram(vert, BLUR_FRAG, true) || !g_gl.fill->createProgram(vert, ALPHA_FRAG, true)) {
            failOnce("shader compile failed");
            return false;
        }
        // The external-target variant is only needed for dma-buf surfaces. If the driver rejects it,
        // those layers get no glass (one notice); SHM layers are unaffected.
        g_gl.extReady = g_gl.fillExt->createProgram(vert, ALPHA_EXT_FRAG, true);
        if (!g_gl.extReady)
            HyprlandAPI::addNotification(PHANDLE, "[qmlrice-glass] dma-buf alpha shader failed to compile, dma-buf layers get no glass", CHyprColor{1.0, 0.8, 0.2, 1.0}, 8000);

        const auto gp = g_gl.glass->program();
        g_gl.uBoxSize    = glGetUniformLocation(gp, "boxSize");
        g_gl.uPad        = glGetUniformLocation(gp, "pad");
        g_gl.uRadius     = glGetUniformLocation(gp, "radius");
        g_gl.uBezel      = glGetUniformLocation(gp, "bezel");
        g_gl.uRefr       = glGetUniformLocation(gp, "refraction");
        g_gl.uDisp       = glGetUniformLocation(gp, "dispersion");
        g_gl.uSpec       = glGetUniformLocation(gp, "specular");
        g_gl.uAngle      = glGetUniformLocation(gp, "lightAngle");
        g_gl.uAlpha      = glGetUniformLocation(gp, "alpha");
        g_gl.uSharp      = glGetUniformLocation(gp, "sharpTex");
        g_gl.uBlurTex    = glGetUniformLocation(gp, "blurTex");
        g_gl.uSharpAlpha = glGetUniformLocation(gp, "sharpAlphaTex");
        g_gl.uAlphaTex   = glGetUniformLocation(gp, "alphaTex");
        g_gl.uAlphaMode  = glGetUniformLocation(gp, "alphaMode");
        g_gl.uAlphaThr   = glGetUniformLocation(gp, "alphaThreshold");
        g_gl.uAlphaSigma = glGetUniformLocation(gp, "alphaSigma");
        g_gl.uAlphaTexel = glGetUniformLocation(gp, "alphaTexel");
        g_gl.uFeatherMode = glGetUniformLocation(gp, "featherMode");
        g_gl.uFeatherGain = glGetUniformLocation(gp, "featherGain");

        const auto bp    = g_gl.blur->program();
        g_gl.uDir        = glGetUniformLocation(bp, "direction");
        g_gl.uBlurRadius = glGetUniformLocation(bp, "blurRadius");

        const auto locs = [](GLuint prog, const char* srcName) {
            SGlassGL::SFillLoc l;
            l.src     = glGetUniformLocation(prog, srcName);
            l.isSurf  = glGetUniformLocation(prog, "srcIsSurface");
            l.box     = glGetUniformLocation(prog, "boxSize");
            l.padSize = glGetUniformLocation(prog, "padSize");
            l.pad     = glGetUniformLocation(prog, "pad");
            return l;
        };
        g_gl.fillLoc = locs(g_gl.fill->program(), "srcTex");
        if (g_gl.extReady)
            g_gl.fillExtLoc = locs(g_gl.fillExt->program(), "srcTex");

        if (!g_gl.sampler) {
            glGenSamplers(1, &g_gl.sampler);
            glSamplerParameteri(g_gl.sampler, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glSamplerParameteri(g_gl.sampler, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glSamplerParameteri(g_gl.sampler, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glSamplerParameteri(g_gl.sampler, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        }

        g_gl.ready = true;
        return true;
    }

    void ensureFB(SP<Render::IFramebuffer>& fb, const char* name, int w, int h, DRMFormat fmt) {
        if (!fb)
            fb = g_pHyprRenderer->createFB(name);
        if (fb->m_size.x != w || fb->m_size.y != h || fb->m_drmFormat != fmt)
            fb->alloc(w, h, fmt);
    }

    void setupSampler(const SP<Render::IFramebuffer>& fb) {
        fb->getTexture()->bind();
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }

    // Separable Gaussian over `src` into `dst`, through `tmp`. The shader's kernel sigma is
    // blurRadius / 2 texels, so the caller passes blurRadius in texels of the target size.
    void blurInto(const SP<Render::IFramebuffer>& src, const SP<Render::IFramebuffer>& dst, const SP<Render::IFramebuffer>& tmp, int w, int h, float blurRadiusTexels) {
        g_pHyprRenderer->blend(false);
        auto bs = g_pHyprOpenGL->useShader(g_gl.blur);
        bs->setUniformMatrix3fv(SHADER_PROJ, 1, GL_FALSE, FULLSCREEN);
        bs->setUniformInt(SHADER_TEX, 0);
        glUniform1f(g_gl.uBlurRadius, blurRadiusTexels);
        glBindVertexArray(bs->getUniformLocation(SHADER_SHADER_VAO));
        g_pHyprOpenGL->setViewport(0, 0, w, h);
        glActiveTexture(GL_TEXTURE0);

        glBindFramebuffer(GL_FRAMEBUFFER, fbId(tmp));
        setupSampler(src);
        glUniform2f(g_gl.uDir, 1.F / w, 0.F);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

        glBindFramebuffer(GL_FRAMEBUFFER, fbId(dst));
        setupSampler(tmp);
        glUniform2f(g_gl.uDir, 0.F, 1.F / h);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }
}

namespace Glass {
    bool renderAllowed() {
        const auto& rd = g_pHyprRenderer->m_renderData;
        if (g_pHyprRenderer->m_bRenderingSnapshot)
            return false;
        if (rd.projectionType != Render::RPT_MONITOR)
            return false;
        // Only the monitor's own pass: a different current FB means a replay/export.
        if (rd.mainFB && rd.currentFB != rd.mainFB)
            return false;
        if (rd.renderModif.enabled && !rd.renderModif.modifs.empty())
            return false;
        return true;
    }

    int samplePadding(const SGlassParams& p, float scale) {
        return GlassMath::samplePadding(p.rimWidth * scale, p.refraction, p.dispersion, p.blur * scale);
    }

    bool failed() {
        return g_gl.failed;
    }

    void shutdown() {
        if (g_gl.ready || g_gl.sharpFB || g_gl.blurFB || g_gl.tmpFB || g_gl.alphaFB || g_gl.sharpAlphaFB || g_gl.sampler) {
            g_pHyprOpenGL->makeEGLCurrent();
            g_gl.glass->destroy();
            g_gl.blur->destroy();
            g_gl.fill->destroy();
            g_gl.fillExt->destroy();
            g_gl.sharpFB.reset();
            g_gl.blurFB.reset();
            g_gl.tmpFB.reset();
            g_gl.alphaFB.reset();
            g_gl.sharpAlphaFB.reset();
            if (g_gl.sampler)
                glDeleteSamplers(1, &g_gl.sampler);
            g_gl.sampler = 0;
        }
        g_gl.ready = false;
        g_gl.extReady = false;
    }
}

std::optional<CBox> CGlassPassElement::boundingBox() {
    if (m_data.logicalBox.w <= 0 || m_data.logicalBox.h <= 0)
        return std::nullopt;
    return m_data.logicalBox;
}

bool CGlassPassElement::needsLiveBlur() {
    // Our draw() reads what is already in the framebuffer behind the surface. Live
    // blur makes the render pass redraw that background across the whole element
    // box on partial damage, so we never sample our own previous glass. The pass
    // asserts a bounding box for any live-blur element, so both must agree.
    return !Glass::failed() && boundingBox().has_value();
}

std::vector<UP<IPassElement>> CGlassPassElement::draw() {
    if (Glass::failed())
        return {};

    try {
        const auto monitor = g_pHyprRenderer->m_renderData.pMonitor.lock();
        const auto src     = g_pHyprRenderer->m_renderData.currentFB;
        if (!monitor || !src || monitor->m_transform != WL_OUTPUT_TRANSFORM_NORMAL)
            return {};

        const CBox& box = m_data.fbBox;
        if (box.w < 2 || box.h < 2)
            return {};

        // Nothing of our box is damaged this frame: nothing to draw.
        CBox damageExtents = g_pHyprRenderer->m_renderData.damage.copy().intersect(box).getExtents();
        if (damageExtents.w <= 0 || damageExtents.h <= 0)
            return {};

        const bool alphaMode = m_data.params.alphaMode;

        if (!ensureShaders())
            return {};

        // Alpha mode reads the surface through Hyprland's texture object (bind/unbind, so the target
        // is right for SHM and dma-buf alike). A missing or broken texture, or a dma-buf layer without
        // the external shader, paints nothing we can measure: no glass this frame.
        if (alphaMode) {
            if (!m_data.surface || !m_data.surface->ok())
                return {};
            if (m_data.surface->m_type == Render::TEXTURE_EXTERNAL && !g_gl.extReady)
                return {};
        }

        const int pad  = Glass::samplePadding(m_data.params, m_data.scale);
        const int fullW = static_cast<int>(box.w) + 2 * pad;
        const int fullH = static_cast<int>(box.h) + 2 * pad;
        const int blurW = std::max(1, fullW / DOWNSCALE);
        const int blurH = std::max(1, fullH / DOWNSCALE);
        const float bezelPx = std::max(1.F, m_data.params.rimWidth * m_data.scale);
        const int boxW = static_cast<int>(box.w), boxH = static_cast<int>(box.h);

        ensureFB(g_gl.sharpFB, "qmlrice-glass-sharp", fullW, fullH, src->m_drmFormat);
        ensureFB(g_gl.blurFB, "qmlrice-glass-blur", blurW, blurH, src->m_drmFormat);
        ensureFB(g_gl.tmpFB, "qmlrice-glass-tmp", blurW, blurH, src->m_drmFormat);
        if (alphaMode) {
            ensureFB(g_gl.sharpAlphaFB, "qmlrice-glass-salpha", boxW, boxH, src->m_drmFormat);
            ensureFB(g_gl.alphaFB, "qmlrice-glass-alpha", blurW, blurH, src->m_drmFormat);
        }
        if (!fbId(g_gl.sharpFB) || !fbId(g_gl.blurFB) || !fbId(g_gl.tmpFB) || !fbId(src) || (alphaMode && (!fbId(g_gl.alphaFB) || !fbId(g_gl.sharpAlphaFB)))) {
            failOnce("framebuffer backend is not GL");
            return {};
        }

        // 1. Copy the backdrop (box plus padding) out of the current framebuffer.
        int sx0 = static_cast<int>(box.x) - pad, sy0 = static_cast<int>(box.y) - pad;
        int sx1 = sx0 + fullW, sy1 = sy0 + fullH;
        int dx0 = 0, dy0 = 0, dx1 = fullW, dy1 = fullH;
        const int fbW = static_cast<int>(src->m_size.x), fbH = static_cast<int>(src->m_size.y);
        bool clamped = false;
        if (sx0 < 0) { dx0 -= sx0; sx0 = 0; clamped = true; }
        if (sy0 < 0) { dy0 -= sy0; sy0 = 0; clamped = true; }
        if (sx1 > fbW) { dx1 -= sx1 - fbW; sx1 = fbW; clamped = true; }
        if (sy1 > fbH) { dy1 -= sy1 - fbH; sy1 = fbH; clamped = true; }
        if (sx1 <= sx0 || sy1 <= sy0)
            return {};

        // The render pass scissors each element to its damage; that must not clip our blits.
        g_pHyprOpenGL->setCapStatus(GL_SCISSOR_TEST, false);
        if (glIsEnabled(GL_SCISSOR_TEST))
            glDisable(GL_SCISSOR_TEST);

        if (clamped) {
            glBindFramebuffer(GL_FRAMEBUFFER, fbId(g_gl.sharpFB));
            glClearColor(0.F, 0.F, 0.F, 0.F);
            glClear(GL_COLOR_BUFFER_BIT);
        }
        glBindFramebuffer(GL_READ_FRAMEBUFFER, fbId(src));
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbId(g_gl.sharpFB));
        glBlitFramebuffer(sx0, sy0, sx1, sy1, dx0, dy0, dx1, dy1, GL_COLOR_BUFFER_BIT, GL_LINEAR);

        // 2. Downscale into the blur target, then two separable Gaussian passes.
        glBindFramebuffer(GL_READ_FRAMEBUFFER, fbId(g_gl.sharpFB));
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, fbId(g_gl.blurFB));
        glBlitFramebuffer(0, 0, fullW, fullH, 0, 0, blurW, blurH, GL_COLOR_BUFFER_BIT, GL_LINEAR);

        const float blurTexels = m_data.params.blur * m_data.scale / DOWNSCALE;
        if (blurTexels >= 0.5F)
            blurInto(g_gl.blurFB, g_gl.blurFB, g_gl.tmpFB, blurW, blurH, blurTexels);

        // 3. Alpha mode. (a) the surface's alpha at box size, the exact silhouette; (b) that field
        //    copied into a padded half-res target; (c) blurred. The glass shader takes the silhouette
        //    from (a) and the edge distance and normal from (c).
        const float alphaSigma = static_cast<float>(GlassMath::alphaSigmaPx(bezelPx));
        if (alphaMode) {
            const bool ext = m_data.surface->m_type == Render::TEXTURE_EXTERNAL;
            const auto& fl = ext ? g_gl.fillExtLoc : g_gl.fillLoc;
            const auto& prog = ext ? g_gl.fillExt : g_gl.fill;

            // (a) surface -> box-sized FB, no padding
            glBindFramebuffer(GL_FRAMEBUFFER, fbId(g_gl.sharpAlphaFB));
            g_pHyprOpenGL->setViewport(0, 0, boxW, boxH);
            g_pHyprRenderer->blend(false);
            auto fs = g_pHyprOpenGL->useShader(prog);
            fs->setUniformMatrix3fv(SHADER_PROJ, 1, GL_FALSE, FULLSCREEN);
            glUniform1i(fl.src, 2);
            glUniform1i(fl.isSurf, 1);
            glUniform2f(fl.box, static_cast<float>(boxW), static_cast<float>(boxH));
            glUniform2f(fl.padSize, static_cast<float>(boxW), static_cast<float>(boxH));
            glUniform1f(fl.pad, 0.F);
            glBindVertexArray(fs->getUniformLocation(SHADER_SHADER_VAO));
            glActiveTexture(GL_TEXTURE2);
            m_data.surface->bind();
            glBindSampler(2, g_gl.sampler);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            glBindSampler(2, 0);
            m_data.surface->unbind();

            // (b) box FB -> padded half-res target
            glBindFramebuffer(GL_FRAMEBUFFER, fbId(g_gl.alphaFB));
            g_pHyprOpenGL->setViewport(0, 0, blurW, blurH);
            fs = g_pHyprOpenGL->useShader(g_gl.fill);
            fs->setUniformMatrix3fv(SHADER_PROJ, 1, GL_FALSE, FULLSCREEN);
            glUniform1i(g_gl.fillLoc.src, 2);
            glUniform1i(g_gl.fillLoc.isSurf, 0);
            glUniform2f(g_gl.fillLoc.box, static_cast<float>(boxW), static_cast<float>(boxH));
            glUniform2f(g_gl.fillLoc.padSize, static_cast<float>(fullW), static_cast<float>(fullH));
            glUniform1f(g_gl.fillLoc.pad, static_cast<float>(pad));
            glBindVertexArray(fs->getUniformLocation(SHADER_SHADER_VAO));
            glActiveTexture(GL_TEXTURE2);
            setupSampler(g_gl.sharpAlphaFB);
            glBindSampler(2, g_gl.sampler);
            glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
            glBindSampler(2, 0);

            // (c) blur. The target is half res: alphaSigma device px is alphaSigma / 2 texels, so
            // blurRadius (= 2 sigma texels) is alphaSigma itself.
            blurInto(g_gl.alphaFB, g_gl.alphaFB, g_gl.tmpFB, blurW, blurH, alphaSigma);
        }

        // 4. Draw the glass quad over the surface box.
        glBindFramebuffer(GL_FRAMEBUFFER, fbId(src));
        g_pHyprOpenGL->setViewport(0, 0, fbW, fbH);
        g_pHyprRenderer->blend(true);

        const auto transform = Math::wlTransformToHyprutils(Math::invertTransform(monitor->m_transform));
        CBox       rawBox    = box;
        Mat3x3     matrix    = g_pHyprRenderer->projectBoxToTarget(rawBox, transform);
        matrix.transpose();

        auto gs = g_pHyprOpenGL->useShader(g_gl.glass);
        gs->setUniformMatrix3fv(SHADER_PROJ, 1, GL_FALSE, matrix.getMatrix());
        glUniform1i(g_gl.uSharp, 0);
        glUniform1i(g_gl.uBlurTex, 1);
        glUniform1i(g_gl.uSharpAlpha, 2);
        glUniform1i(g_gl.uAlphaTex, 3);
        glUniform1i(g_gl.uAlphaMode, alphaMode ? 1 : 0);
        glUniform1f(g_gl.uAlphaThr, std::clamp(m_data.params.alphaThreshold, 0.F, 1.F));
        glUniform1f(g_gl.uAlphaSigma, alphaSigma);
        glUniform2f(g_gl.uAlphaTexel, 1.F / static_cast<float>(blurW), 1.F / static_cast<float>(blurH));
        glUniform2f(g_gl.uBoxSize, static_cast<float>(box.w), static_cast<float>(box.h));
        glUniform1f(g_gl.uPad, static_cast<float>(pad));
        const auto& prm = m_data.params;
        glUniform1f(g_gl.uRadius, prm.radius * m_data.scale);
        glUniform1f(g_gl.uBezel, bezelPx);
        glUniform1f(g_gl.uRefr, std::clamp(prm.refraction, 0.F, 1.F));
        glUniform1f(g_gl.uDisp, std::clamp(prm.dispersion, 0.F, 2.F));
        glUniform1f(g_gl.uSpec, std::clamp(prm.specular, 0.F, 1.F));
        glUniform1f(g_gl.uAngle, prm.lightAngle * static_cast<float>(M_PI) / 180.F);
        glUniform1f(g_gl.uAlpha, std::clamp(m_data.alpha, 0.F, 1.F));
        glUniform1i(g_gl.uFeatherMode, prm.featherMode ? 1 : 0);
        glUniform1f(g_gl.uFeatherGain, prm.featherGain);

        glActiveTexture(GL_TEXTURE0);
        setupSampler(g_gl.sharpFB);
        glActiveTexture(GL_TEXTURE1);
        setupSampler(g_gl.blurFB);
        if (alphaMode) {
            glActiveTexture(GL_TEXTURE2);
            setupSampler(g_gl.sharpAlphaFB);
            glBindSampler(2, g_gl.sampler);
            glActiveTexture(GL_TEXTURE3);
            setupSampler(g_gl.alphaFB);
        }

        glBindVertexArray(gs->getUniformLocation(SHADER_SHADER_VAO));
        g_pHyprOpenGL->scissor(damageExtents);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
        g_pHyprOpenGL->scissor(nullptr);

        // Leave the state Hyprland expects between elements.
        glBindVertexArray(0);
        if (alphaMode) {
            glBindSampler(2, 0);
            glActiveTexture(GL_TEXTURE2);
            glBindTexture(GL_TEXTURE_2D, 0);
            glActiveTexture(GL_TEXTURE3);
            glBindTexture(GL_TEXTURE_2D, 0);
        }
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, 0);
        glActiveTexture(GL_TEXTURE0);
    } catch (...) {
        // Fail closed: stop drawing glass for the session rather than risk the compositor.
        failOnce("exception while drawing");
        if (const auto src = g_pHyprRenderer->m_renderData.currentFB; src && fbId(src))
            glBindFramebuffer(GL_FRAMEBUFFER, fbId(src));
    }
    return {};
}
