#pragma once

// Pure math shared by the plugin (src/GlassPass.cpp) and the offline render test
// (test/glass_render_test.cpp). No Hyprland or GL dependencies. Mirrors shaders/glass.frag.

#include <algorithm>
#include <cmath>

namespace GlassMath {
    // Rim shift amplitude, px, at the very edge. The shift at normalized depth t is
    //   shift(t) = amplitude * (1 - t)^2,   t = depth / bezel in [0,1]
    // The sample position x(d) = d + shift(d) has dx/dd = 1 - 2a(1-t) with a = amplitude/bezel.
    // It is non-decreasing (no fold-over, so text is never mirrored inside the bezel) for
    // a <= 0.5, which is refraction <= 1. Zero value and zero slope where the rim meets the body.
    inline double edgeShift(double bezelPx, double refraction) {
        return 0.5 * bezelPx * std::clamp(refraction, 0.0, 1.0);
    }

    // Blur sigma (device px) of the surface-alpha field used for the edge distance in alpha mode.
    // Small enough that neighbouring modules and gaps do not swamp each other's rim, large enough
    // that the depth reaches the bezel (depth saturates near 3.6 sigma). Clamped to the kernel reach.
    inline double alphaSigmaPx(double bezelPx) {
        return std::clamp(0.4 * bezelPx, 3.0, 16.0);
    }

    // Sample padding (device px) the backdrop copies need around the surface box. Two reasons:
    //  - the rim shift, scaled by the red-channel dispersion factor;
    //  - the body blur reach. The two separable blur passes compound, so the reach is about
    //    2 x blur. Samples past the padded texture clamp to its edge, which smears the rim rows
    //    through the body (vertical streaks), so the pad covers 2 x blur.
    inline int samplePadding(double bezelPx, double refraction, double dispersion, double blurPx) {
        const double red   = edgeShift(bezelPx, refraction) * (1.0 + 0.22 * std::clamp(dispersion, 0.0, 2.0));
        const double shift = std::max(std::ceil(red), std::ceil(2.0 * blurPx) + 2.0);
        return static_cast<int>(shift) + 4;
    }
}
