#define WLR_USE_UNSTABLE

#include <dlfcn.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <memory>
#include <regex>
#include <string>
#include <unordered_map>
#include <vector>

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/protocols/LayerShell.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <hyprutils/signal/Listener.hpp>

#include "GlassPass.hpp"
#include "Globals.hpp"

// The one Hyprland build this plugin is written against. No override exists:
// anything else loads as a no-op (PLUGIN_INIT throws before touching anything).
static constexpr const char* PINNED_COMMIT = "efb50993780079460b0cbed1363e2166a2de1d9f";

static constexpr const char* DEFAULT_NAMESPACES = "^(qml-rice:dock|qml-rice:menu|qml-rice:osd|qml-rice:notif.*|qml-rice:launcher|qml-rice:mac-.*)$";
static constexpr const char* DEFAULT_FEATHER_NAMESPACES = "^qml-rice:mac-nc-backdrop$";

// Do NOT change this function.
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

namespace {
    // Itanium-mangled Render::IHyprRenderer::renderLayer(PHLLS, PHLMONITOR, const steady_tp&, bool, bool)
    // as exported by Hyprland v0.56.2 (efb50993). The full signature is in the name, so a hit is exactly
    // the overload the hook below is written for.
    constexpr const char* SYM_RENDER_LAYER =
        "_ZN6Render13IHyprRenderer11renderLayerEN9Hyprutils6Memory14CSharedPointerIN7Desktop4View13CLayerSurfaceEEENS3_IN7Monitor8CMonitorEEERKNSt6chrono10time_"
        "pointINSB_3_V212steady_clockENSB_8durationIlSt5ratioILl1ELl1000000000EEEEEEbb";

    using renderLayerFn = void (*)(Render::IHyprRenderer*, PHLLS, PHLMONITOR, const Time::steady_tp&, bool, bool);

    struct SLayerMatch {
        std::string ns;
        uint64_t    gen     = 0;
        bool        match   = false; // glass (namespaces)
        bool        feather = false; // feather (featherNamespaces); wins over match
    };

    struct SState {
        CFunctionHook* hook = nullptr;

        struct {
            SP<Config::Values::CBoolValue>   enabled;
            SP<Config::Values::CStringValue> namespaces;
            SP<Config::Values::CFloatValue>  rimWidth, radius, refraction, dispersion, specular, lightAngle, blur, alphaThreshold;
            SP<Config::Values::CStringValue> shape;
            SP<Config::Values::CStringValue> featherNamespaces;
            SP<Config::Values::CFloatValue>  featherGain;
        } cfg;

        std::regex                                       re;
        bool                                             reOk = false;
        std::regex                                       featherRe;
        bool                                             featherReOk = false;
        uint64_t                                         gen  = 1;
        std::unordered_map<void*, SLayerMatch>           layers;
        std::vector<Hyprutils::Signal::CHyprSignalListener> listeners;
    };

    UP<SState> g_state;

    void rebuildRegex() {
        if (!g_state)
            return;
        g_state->gen++;
        g_state->layers.clear();
        g_state->reOk        = false;
        g_state->featherReOk = false;
        try {
            g_state->re   = std::regex(g_state->cfg.namespaces->value(), std::regex::ECMAScript | std::regex::optimize);
            g_state->reOk = true;
        } catch (const std::exception& e) {
            // Fail closed: a bad pattern matches nothing.
            HyprlandAPI::addNotification(PHANDLE, std::string("[qmlrice-glass] invalid namespaces regex, glass off: ") + e.what(), CHyprColor{1.0, 0.8, 0.2, 1.0}, 6000);
        }
        try {
            g_state->featherRe   = std::regex(g_state->cfg.featherNamespaces->value(), std::regex::ECMAScript | std::regex::optimize);
            g_state->featherReOk = true;
        } catch (const std::exception& e) {
            // Fail closed: a bad pattern matches nothing.
            HyprlandAPI::addNotification(PHANDLE, std::string("[qmlrice-glass] invalid featherNamespaces regex, feather off: ") + e.what(), CHyprColor{1.0, 0.8, 0.2, 1.0}, 6000);
        }
    }

    const SLayerMatch& layerMatch(const PHLLS& ls) {
        auto& entry = g_state->layers[ls.get()];
        if (entry.gen != g_state->gen || entry.ns != ls->m_namespace) {
            entry.ns      = ls->m_namespace;
            entry.gen     = g_state->gen;
            entry.match   = g_state->reOk && std::regex_match(entry.ns, g_state->re);
            entry.feather = g_state->featherReOk && std::regex_match(entry.ns, g_state->featherRe);
        }
        return entry;
    }

    // Queues the glass element for this layer, in front of everything already
    // drawn and behind the surface elements renderLayer is about to add.
    // feather: the feather treatment (alpha is the blur weight, no lens); otherwise normal glass.
    void queueGlass(const PHLLS& ls, const PHLMONITOR& mon, bool feather) {
        if (!ls->m_mapped || mon->m_transform != WL_OUTPUT_TRANSFORM_NORMAL)
            return;

        const float alpha = ls->alpha().getTotal();
        if (!(alpha > 0.004F)) // hidden / fully faded: skip, and rejects NaN
            return;

        const float scale = mon->m_scale > 0.F ? mon->m_scale : 1.F;

        CBox logical{ls->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT), ls->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT)};
        logical.translate(-mon->m_position);
        if (!std::isfinite(logical.x) || !std::isfinite(logical.y) || !std::isfinite(logical.w) || !std::isfinite(logical.h) || logical.w < 1 || logical.h < 1)
            return;

        CBox fb = logical;
        fb.scale(scale).round().noNegativeSize();
        if (fb.w < 2 || fb.h < 2)
            return;

        const auto&  c = g_state->cfg;
        SGlassParams p;
        p.radius     = std::max(0.F, c.radius->value());
        p.rimWidth   = std::max(1.F, c.rimWidth->value());
        p.refraction = std::clamp(static_cast<float>(c.refraction->value()), 0.F, 1.F);
        p.dispersion = std::clamp(static_cast<float>(c.dispersion->value()), 0.F, 2.F);
        p.specular   = std::clamp(static_cast<float>(c.specular->value()), 0.F, 1.F);
        p.lightAngle = c.lightAngle->value();
        p.blur       = std::clamp(static_cast<float>(c.blur->value()), 0.F, 64.F);
        p.alphaThreshold = std::clamp(static_cast<float>(c.alphaThreshold->value()), 0.F, 1.F);
        // Anything but "rect" is the alpha mode (the default). An unknown value is not an error:
        // the alpha mode is the one that never glasses what the surface does not paint.
        p.alphaMode = c.shape->value() != "rect";
        if (feather) {
            // Feather needs the surface's exact per-pixel alpha, so it always runs the alpha path.
            p.alphaMode      = true;
            p.featherMode    = true;
            p.featherGain    = std::clamp(static_cast<float>(c.featherGain->value()), 0.F, 100.F);
        }

        // Alpha mode draws from the surface's own texture, SHM or dma-buf (the draw reads it through
        // ITexture bind/unbind, so the GL target is Hyprland's). Without a texture (not committed yet)
        // the surface paints nothing we can measure: no glass this frame instead of a rectangle.
        SP<Render::ITexture> surface;
        if (p.alphaMode) {
            const auto res  = ls->m_layerSurface.lock();
            const auto wlsf = res ? res->m_surface.lock() : nullptr;
            surface         = wlsf ? wlsf->m_current.texture : nullptr;
            if (!surface || !surface->ok())
                return;
        }

        // Bounding box handed to the render pass: logical, padded for the sample margin.
        CBox padded = fb;
        padded.expand(Glass::samplePadding(p, scale));
        padded.scale(1.0 / scale).round();

        CGlassPassElement::SData d;
        d.fbBox      = fb;
        d.logicalBox = padded;
        d.scale      = scale;
        d.alpha      = alpha;
        d.params     = p;
        d.surface    = surface;
        g_pHyprRenderer->m_renderPass.add(makeUnique<CGlassPassElement>(d));
    }

    void hkRenderLayer(Render::IHyprRenderer* self, PHLLS ls, PHLMONITOR mon, const Time::steady_tp& now, bool popups, bool lockscreen) {
        // Without state or a trampoline there is nothing safe to do but not be here at all.
        auto original = (g_state && g_state->hook) ? reinterpret_cast<renderLayerFn>(g_state->hook->m_original) : nullptr;
        if (!original)
            return;

        try {
            if (!popups && !lockscreen && ls && mon && g_state->cfg.enabled->value() && Glass::renderAllowed() && !Glass::failed()) {
                const auto& m = layerMatch(ls);
                if (m.feather)
                    queueGlass(ls, mon, true); // feather wins over normal glass
                else if (m.match)
                    queueGlass(ls, mon, false);
            }
        } catch (...) {
            // Fail closed: render the layer exactly as Hyprland would.
        }

        original(self, ls, mon, now, popups, lockscreen);
    }

    void onLayerClosed(PHLLS ls) {
        if (g_state && ls)
            g_state->layers.erase(ls.get());
    }

    template <typename T, typename... A>
    SP<T> addValue(const char* name, const char* desc, A&&... a) {
        auto v = makeShared<T>(name, desc, std::forward<A>(a)...);
        HyprlandAPI::addConfigValueV2(PHANDLE, v);
        return v;
    }
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    // Version guard. Nothing that depends on Hyprland's internal layout runs before this.
    // The running compiler's commit, the commit these headers came from, and the pin must all agree.
    const std::string running = __hyprland_api_get_hash();
    const std::string client  = __hyprland_api_get_client_hash();
    const auto        ver     = HyprlandAPI::getHyprlandVersion(handle);
    if (running != client || ver.hash != PINNED_COMMIT || std::strncmp(running.c_str(), PINNED_COMMIT, std::strlen(PINNED_COMMIT)) != 0) {
        HyprlandAPI::addNotification(handle, "[qmlrice-glass] Hyprland build mismatch (built for " + std::string(PINNED_COMMIT).substr(0, 8) + ", running " + ver.hash.substr(0, 8) + "), plugin not loaded",
                                     CHyprColor{1.0, 0.2, 0.2, 1.0}, 8000);
        throw std::runtime_error("[qmlrice-glass] Hyprland build mismatch, not loading");
    }

    g_state = makeUnique<SState>();

    g_state->cfg.enabled    = addValue<Config::Values::CBoolValue>("plugin:qmlrice_glass:enabled", "Master switch (default off)", false);
    g_state->cfg.namespaces = addValue<Config::Values::CStringValue>("plugin:qmlrice_glass:namespaces", "Regex (full match) of layer namespaces that get glass", DEFAULT_NAMESPACES);
    g_state->cfg.rimWidth   = addValue<Config::Values::CFloatValue>("plugin:qmlrice_glass:rimWidth", "Refracting bezel width, logical px", 22.F);
    g_state->cfg.radius     = addValue<Config::Values::CFloatValue>("plugin:qmlrice_glass:radius", "Corner radius of the glass shape, logical px", 22.F);
    g_state->cfg.refraction = addValue<Config::Values::CFloatValue>("plugin:qmlrice_glass:refraction", "Rim lens shift, fraction of bezel/2, 0..1 (above 1 folds text)", 1.0F);
    g_state->cfg.dispersion = addValue<Config::Values::CFloatValue>("plugin:qmlrice_glass:dispersion", "Rim RGB dispersion, 0..2, outer 40% of the bezel only", 0.35F);
    g_state->cfg.specular   = addValue<Config::Values::CFloatValue>("plugin:qmlrice_glass:specular", "Specular rim highlight strength 0..1", 0.4F);
    g_state->cfg.lightAngle = addValue<Config::Values::CFloatValue>("plugin:qmlrice_glass:lightAngle", "Light direction, degrees counter-clockwise from +x (90 = from the top)", 100.F);
    g_state->cfg.blur       = addValue<Config::Values::CFloatValue>("plugin:qmlrice_glass:blur", "Frosted body blur radius, logical px", 28.F);
    g_state->cfg.shape          = addValue<Config::Values::CStringValue>("plugin:qmlrice_glass:shape", "Glass shape: alpha (the surface's own alpha, default) or rect (the box, radius)", "alpha");
    g_state->cfg.alphaThreshold = addValue<Config::Values::CFloatValue>("plugin:qmlrice_glass:alphaThreshold", "Alpha mode: surface alpha below this gets no glass, 0..1", 0.02F);
    g_state->cfg.featherNamespaces = addValue<Config::Values::CStringValue>("plugin:qmlrice_glass:featherNamespaces", "Regex (full match) of layer namespaces that get a feathered blur from their alpha", DEFAULT_FEATHER_NAMESPACES);
    g_state->cfg.featherGain       = addValue<Config::Values::CFloatValue>("plugin:qmlrice_glass:featherGain", "Feather: blur weight = clamp(surface alpha x gain, 0, 1)", 4.5F);

    g_state->listeners.push_back(Event::bus()->m_events.layer.closed.listen([](PHLLS ls) { onLayerClosed(ls); }));
    g_state->listeners.push_back(Event::bus()->m_events.config.reloaded.listen([] { rebuildRegex(); }));

    // Hook: private symbol, resolved by exact mangled name, accepted only if it lives in the
    // Hyprland executable itself. Any failure leaves the plugin inert.
    Dl_info hl{}, sym{};
    void*   addr = dlsym(RTLD_DEFAULT, SYM_RENDER_LAYER);
    if (addr && dladdr(reinterpret_cast<void*>(&HyprlandAPI::findFunctionsByName), &hl) && dladdr(addr, &sym) && sym.dli_fbase == hl.dli_fbase) {
        g_state->hook = HyprlandAPI::createFunctionHook(PHANDLE, addr, reinterpret_cast<void*>(&hkRenderLayer));
        if (g_state->hook && !g_state->hook->hook()) {
            HyprlandAPI::removeFunctionHook(PHANDLE, g_state->hook);
            g_state->hook = nullptr;
        }
    }
    if (!g_state->hook)
        HyprlandAPI::addNotification(PHANDLE, "[qmlrice-glass] could not hook renderLayer, glass is inert", CHyprColor{1.0, 0.8, 0.2, 1.0}, 8000);

    rebuildRegex();

    return {"qmlrice-glass", "Liquid-glass render effect for selected layer-shell surfaces", "qml-rice", "0.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    if (!g_state)
        return;

    // Unhook first so no render call can reach our code once we start tearing down.
    if (g_state->hook) {
        HyprlandAPI::removeFunctionHook(PHANDLE, g_state->hook);
        g_state->hook = nullptr;
    }
    g_state->listeners.clear();
    g_pHyprRenderer->m_renderPass.removeAllOfType("CGlassPassElement");
    Glass::shutdown();
    g_state.reset();
}
