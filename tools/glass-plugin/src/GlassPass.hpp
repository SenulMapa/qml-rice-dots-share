#pragma once

#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprutils/math/Box.hpp>

// Tunables snapshotted when the element is queued, so draw() never reads config.
struct SGlassParams {
    float radius     = 22.F;  // logical px
    float rimWidth   = 22.F;  // bezel, logical px
    float refraction = 1.F;   // rim lens shift, 0..1 (see GlassMath.hpp)
    float dispersion = 0.35F; // RGB split, outer 40% of the bezel
    float specular   = 0.4F;
    float lightAngle = 100.F; // degrees, counter-clockwise from +x
    float blur       = 28.F;  // logical px
    bool  alphaMode  = true;  // true: shape = surface alpha; false: rounded rect
    float alphaThreshold = 0.02F; // alpha mode: surface alpha below this gets no glass
    // Feather mode (featherNamespaces): no lens, no rim. The surface alpha is the blur weight:
    // weight = clamp(alpha * featherGain, 0, 1), output = blurred backdrop at that weight.
    bool  featherMode = false;
    float featherGain = 4.5F;
};

// Draws the glass for one layer surface into the current framebuffer, behind
// the surface (it is queued immediately before the surface's own elements).
class CGlassPassElement : public IPassElement {
  public:
    struct SData {
        CBox         fbBox;      // surface box, framebuffer pixels (rounded)
        CBox         logicalBox; // padded box, monitor-local logical (IPassElement contract)
        float        scale = 1.F;
        float        alpha = 1.F;
        SGlassParams params;
        // alpha mode: the layer surface's own texture (premultiplied, box-sized). Null in rect mode.
        SP<Render::ITexture> surface;
    };

    explicit CGlassPassElement(const SData& data) : m_data(data) {}

    std::vector<UP<IPassElement>> draw() override;
    bool                          needsLiveBlur() override;
    bool                          needsPrecomputeBlur() override { return false; }
    std::optional<CBox>           boundingBox() override;
    bool                          disableSimplification() override { return false; }
    const char*                   passName() override { return "CGlassPassElement"; }
    ePassElementType              type() override { return EK_CUSTOM; }

  private:
    SData m_data;
};

namespace Glass {
    // True while the foreign-render guards allow glass (own monitor pass only).
    bool renderAllowed();
    // Padding (framebuffer px) the sample copies need around the surface box.
    int  samplePadding(const SGlassParams& p, float scale);
    // Releases GL objects. Safe to call without a current context only when nothing was created.
    void shutdown();
    // True once a shader compile failed; glass then stays off for the session.
    bool failed();
}
