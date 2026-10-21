pragma Singleton
import QtQuick
import Quickshell.Io

QtObject {
    id: root

    readonly property var fallbackDark: ({
        primary: "#c7c3ff", onPrimary: "#2e2866",
        primaryContainer: "#46417f", onPrimaryContainer: "#e4e0ff",
        secondary: "#c8c4dc", tertiary: "#edb8c8",
        surface: "#121217", surfaceContainerLow: "#1a1a21",
        surfaceContainer: "#202027", surfaceContainerHigh: "#2a2931",
        onSurface: "#e6e1e9", onSurfaceVariant: "#c9c5cf",
        outline: "#928f99", outlineVariant: "#48464f",
        error: "#ffb4ab", warning: "#f4c46b", success: "#8bd5a5"
    })
    readonly property var fallbackLight: ({
        primary: "#5d5791", onPrimary: "#ffffff",
        primaryContainer: "#e4e0ff", onPrimaryContainer: "#19134b",
        secondary: "#605d70", tertiary: "#7a5360",
        surface: "#fcf8ff", surfaceContainerLow: "#f6f2fa",
        surfaceContainer: "#f0ecf4", surfaceContainerHigh: "#eae6ee",
        onSurface: "#1c1b20", onSurfaceVariant: "#49464f",
        outline: "#7a767f", outlineVariant: "#cbc6d0",
        error: "#ba1a1a", warning: "#805600", success: "#216e45"
    })

    property var generated: ({})
    property bool generatedAvailable: false
    property string generatedMode: "dark"

    readonly property string effectiveMode: Config.appearance.mode === "auto"
        ? (Config.appearance.wallpaperPaletteEnabled ? generatedMode : "dark")
        : Config.appearance.mode
    readonly property bool dark: effectiveMode !== "light"
    readonly property bool accentOverridden:
        Config.appearance.accentOverride.length > 0
    readonly property var colors: generatedAvailable
            && Config.appearance.wallpaperPaletteEnabled
        ? (generated[effectiveMode] || generated.dark || generated.light)
        : (dark ? fallbackDark : fallbackLight)

    // ── REPAINT (ported from impasto theme/Theme.qml, verbatim except: ─────
    //  - impasto owns 9 imperatively-assigned `property color` tokens fed by
    //    ThemeService.apply(); we compute tokens from Config.appearance's
    //    generated Material palette instead, so these stay plain (non-
    //    readonly) properties whose VALUE is still a live binding to
    //    colorValue()/accentOverridden -- QML permits a Behavior on a bound
    //    property, just not on a `readonly` one, so dropping `readonly` on
    //    exactly the handful of tokens that visibly repaint (impasto's
    //    "paletteTransition") is the whole port. Every other Theme token
    //    below is untouched and stays readonly.
    //  - impasto's duration is a fixed 260ms; ours tracks
    //    Config.wallpaper.transitionDuration so the re-tint lands in sync
    //    with whatever wallpaper transition (awww) is actually playing.
    //  - impasto animates 9 tokens; UHD 620 budget caps us at the handful
    //    that DeskTheme/dashboard/island cards actually key off of --
    //    everything downstream (DeskTheme.background, .accent, ...) is a
    //    plain property bound to one of these, so it rides the same
    //    animation for free without its own ColorAnimation. ─────────────
    readonly property int paletteTransition:
        Math.round(Config.wallpaper.transitionDuration * 1000)

    property color primary: accentOverridden
        ? Config.appearance.accentOverride : colorValue("primary")
    // `onPrimary`/`onSurface` collide with QML's handler-style property lookup
    // when the corresponding base token exists. Expose explicit foreground names.
    property color primaryText: accentOverridden
        ? foregroundFor(primary) : colorValue("onPrimary")
    property color primaryContainer: accentOverridden
        ? Qt.tint(colorValue("surfaceContainer"),
            Qt.alpha(primary, dark ? 0.34 : 0.20))
        : colorValue("primaryContainer")
    readonly property color primaryContainerText: accentOverridden
        ? primary : colorValue("onPrimaryContainer")
    readonly property color secondary: colorValue("secondary")
    readonly property color tertiary: colorValue("tertiary")
    property color surface: colorValue("surface")
    readonly property color surfaceContainerLow: colorValue("surfaceContainerLow")
    property color surfaceContainer: colorValue("surfaceContainer")
    property color surfaceContainerHigh: colorValue("surfaceContainerHigh")
    property color surfaceText: colorValue("onSurface")
    readonly property color surfaceVariantText: colorValue("onSurfaceVariant")
    readonly property color outline: colorValue("outline")
    property color outlineVariant: colorValue("outlineVariant")
    readonly property color error: colorValue("error")
    readonly property color warning: colorValue("warning")
    readonly property color success: colorValue("success")

    Behavior on primary           { ColorAnimation { duration: root.paletteTransition } }
    Behavior on primaryText       { ColorAnimation { duration: root.paletteTransition } }
    Behavior on primaryContainer  { ColorAnimation { duration: root.paletteTransition } }
    Behavior on surface           { ColorAnimation { duration: root.paletteTransition } }
    Behavior on surfaceContainer  { ColorAnimation { duration: root.paletteTransition } }
    Behavior on surfaceContainerHigh { ColorAnimation { duration: root.paletteTransition } }
    Behavior on surfaceText       { ColorAnimation { duration: root.paletteTransition } }
    Behavior on outlineVariant    { ColorAnimation { duration: root.paletteTransition } }

    readonly property int space1: Math.max(3,
        Math.round(4 * Config.appearance.densityScale))
    readonly property int space2: Math.max(6,
        Math.round(8 * Config.appearance.densityScale))
    readonly property int space3: Math.max(9,
        Math.round(12 * Config.appearance.densityScale))
    readonly property int space4: Math.max(12,
        Math.round(16 * Config.appearance.densityScale))
    readonly property int space5: Math.max(18,
        Math.round(24 * Config.appearance.densityScale))
    // Rounder than upstream by design. Every surface in this shell is
    // conceptually the pill having changed shape, so a boxy corner reads as a
    // different object arriving rather than the same one growing. 8/14/24 ->
    // 12/20/34. This is one edit that reaches every component, because the
    // codebase references these tokens rather than hardcoding radii.
    readonly property int radiusSmall: Math.round(
        12 * Config.appearance.cornerScale)
    readonly property int radiusMedium: Math.round(
        20 * Config.appearance.cornerScale)
    readonly property int radiusLarge: Math.round(
        34 * Config.appearance.cornerScale)
    // Ink redesign radius scale (showcase tokens.css): page 34, card 22,
    // control 14. Fixed values, not cornerScale-relative, to match the
    // approved showcase exactly.
    readonly property int rPage: 34
    readonly property int rCard: 22
    readonly property int rCtl: 14
    // Ink hover pill. One definition: IslandController's target and the
    // Island content host both read it (they drifted apart once).
    readonly property int inkHoverW: 560
    readonly property int inkHoverH: 56
    // Ink rest pill: sized to its content (eq + clock + eq, lyrics, recording)
    // with this as the floor. A fixed 188 squashed the content into the ends.
    readonly property int inkRestMinW: 200
    readonly property int inkRestH: 38
    // Pill/panel radius follows the measured rule: min(h/2, 40).
    function radiusFor(h) { return Math.min(h / 2, 40 * Config.appearance.cornerScale) }
    // Settings > Appearance > "Font scale" (Config.appearance.fontScale,
    // 0.8-1.3, default 1) -- applied here so every call site that already
    // routes through these shared tokens (rather than a locally hardcoded
    // pixelSize) scales live and persists via SettingsStore.
    // Also carries DisplayScale.primary (core/DisplayScale.qml) -- shell-only
    // DPI scaling, so these tokens read full physical size on a high-PPI
    // panel (this laptop measures ~157 PPI vs the ~92 PPI desktop these
    // sizes were tuned at) without touching app font sizes anywhere else.
    readonly property int textSmall: Math.round(12 * Config.appearance.fontScale * DisplayScale.primary)
    readonly property int textBody: Math.round(14 * Config.appearance.fontScale * DisplayScale.primary)
    readonly property int textTitle: Math.round(18 * Config.appearance.fontScale * DisplayScale.primary)
    readonly property int iconSmall: Math.round(16 * Config.appearance.fontScale * DisplayScale.primary)
    readonly property int iconMedium: Math.round(20 * Config.appearance.fontScale * DisplayScale.primary)

    // ================================================================
    //  DESIGN LAYER  — added on top of upstream's Material tokens.
    //  Everything here is DERIVED from those tokens, so a wallpaper change
    //  still drives the whole shell and there is nothing to keep in sync.
    // ================================================================

    /**
     * accentFill — the colour used for LARGE FILLED AREAS (active tiles,
     * slider fills, selected rows).
     *
     * `primary` cannot do this job. Material parks dark-mode primary at tone
     * 80 (L~84), which is specified for TEXT on dark; used as a big fill it
     * reads as a pale wash. All four matugen scheme types were measured and
     * every one gives the same tone, so this is a property of the spec, not a
     * setting we missed.
     *
     * So: push primary toward a vivid mid-tone, then raise lightness until it
     * clears WCAG AA (4.5:1) against the text that sits on it. Contrast is
     * therefore guaranteed by construction for ANY wallpaper -- which was the
     * whole reason for choosing matugen over wallust in the first place.
     */
    readonly property color accentFill: {
        const base = primary
        const target = dark ? 0.62 : base.hslLightness
        if (!dark) return base
        const sat = Math.min(1.0, base.hslSaturation * 1.30)
        for (let L = target; L <= 0.86; L += 0.01) {
            const c = Qt.hsla(base.hslHue, sat, L, 1.0)
            if (contrastRatio(c, primaryText) >= 4.5) return c
        }
        return base
    }
    readonly property color accentFillText: primaryText

    /**
     * islandSurface — the island pill/expanded surface fill, and anything
     * that wants to match it (satellites). Solid, per the owner: no
     * translucency, alpha always 1. One token so "make the island black"
     * is a one-line change instead of a grep-and-replace across Island.qml.
     */
    readonly property color islandSurface: "#000000"
    // Glass redesign: alpha of the near-clear tint on every glass surface.
    // Must stay above Hyprland's glass ignore_alpha (0.19) or the blur
    // behind it switches off.
    readonly property real glassAlpha: 0.26

    // Ink redesign tokens (spec 2026-10-08-ink-redesign-design.md, values
    // from showcase tokens.css). Opaque ink replaces glass on the island and
    // its pages when Config.appearance.ink is on. Chrome stays monochrome;
    // colour comes only from content.
    readonly property color ink: "#000000"
    readonly property color inkRaised: "#121214"     // inactive control on ink
    readonly property color inkRaised2: "#1c1c1f"    // hover of inkRaised
    readonly property color inkRim: Qt.rgba(1, 1, 1, 0.07)  // 1px outer ring
    readonly property color fillOn: "#f5f5f7"        // active control fill
    readonly property color glyphOn: "#000000"         // glyph on fillOn
    readonly property color t1: Qt.rgba(1, 1, 1, 0.96)
    readonly property color t2: Qt.rgba(1, 1, 1, 0.62)
    readonly property color t3: Qt.rgba(1, 1, 1, 0.38)
    // Motion: one spring family. Island morph and micro transitions.
    readonly property int morphMs: 520
    readonly property int microMs: 240

    function relLuminance(c) {
        const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b)
    }
    function contrastRatio(a, b) {
        const la = relLuminance(a), lb = relLuminance(b)
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }

    /**
     * Surface treatment. Four devices, and NOT ONE of them is translucency --
     * a gradient is a vertex colour, a hairline is border.width, a sheen is a
     * 1px Rectangle. That is the entire reason this design survives an Intel
     * UHD 620: measured against the reference shells, the only expensive thing
     * any of them did was blur.
     */
    readonly property color surfaceTop: Qt.tint(surface,
        Qt.alpha(surfaceText, dark ? 0.045 : 0.02))
    readonly property color surfaceBot: dark ? surface
        : Qt.tint(surface, Qt.rgba(0, 0, 0, 0.015))
    readonly property color sheen: dark ? Qt.rgba(1, 1, 1, 0.10)
                                        : Qt.rgba(1, 1, 1, 0.85)
    readonly property color hairline: dark ? Qt.rgba(1, 1, 1, 0.09)
                                           : Qt.rgba(0, 0, 0, 0.09)
    readonly property color shadowColor: Qt.rgba(0, 0, 0, dark ? 0.55 : 0.18)

    /**
     * Typography. Upstream has NO font tokens at all, which is why it reads
     * flat -- system-ui by omission. Three roles, all OFL so they ship with
     * the repo (SF Pro and PP Editorial New were rejected as
     * non-redistributable: a shell that only looks right on the author's
     * machine is a screenshot, not a project).
     *
     * fontClock is separate from fontDisplay on purpose: the clock is the one
     * element on screen at all times, so it carries the identity alone.
     */
    //
    // Glass redesign (6 Oct 2026, spec 2026-10-06-glass-redesign-design.md):
    // display, UI and clock move to Poppins, bundled in assets/fonts (OFL)
    // and registered here so every surface -- including the greeter, which
    // can't read ~/.local fonts -- resolves the family by name.
    readonly property FontLoader _poppinsRegular: FontLoader { source: Qt.resolvedUrl("../assets/fonts/Poppins-Regular.ttf") }
    readonly property FontLoader _poppinsMedium: FontLoader { source: Qt.resolvedUrl("../assets/fonts/Poppins-Medium.ttf") }
    readonly property FontLoader _poppinsSemiBold: FontLoader { source: Qt.resolvedUrl("../assets/fonts/Poppins-SemiBold.ttf") }
    // Ink redesign (Config.appearance.ink): Geist for UI and display,
    // Instrument Serif for display numerals (fontSerif below). Geist is not
    // bundled, so it resolves as a system family by name.
    readonly property string fontDisplay: Config.appearance.ink ? "Geist" : "Poppins"
    readonly property string fontUi: Config.appearance.ink ? "Geist" : "Poppins"
    readonly property string fontData: "Geist Mono"
    readonly property string fontClock: "Poppins"
    readonly property int fontClockWeight: 600
    // Editorial accent only (lyrics, the odd hero line), never UI chrome.
    readonly property string fontSerif: "Instrument Serif"
    readonly property real trackDisplay: -0.02
    readonly property real trackMicro: 0.10

    /**
     * Dashboard typography scale -- Config.appearance.fontFamily/
     * handFontFamily (Gamja Flower) is a playful handwriting face:
     * Regular-only, small x-height, thin strokes. The dashboard's own Text
     * literals (panels/Dashboard*.qml, WeatherMetric.qml,
     * SystemMetricCard.qml) previously hardcoded raw pixelSize values
     * (8-18px) that never routed through fontScale at all -- unlike
     * textSmall/textBody/textTitle above, which ARE used correctly
     * elsewhere in the shell (island, launcher, settings) at sizes that
     * suit those larger surfaces. This is a SEPARATE, dashboard-scoped
     * scale, not a resize of those shared tokens.
     *
     * Measured with render-dashboard.qml (grabToImage swatch strip,
     * /tmp/dashrender): Qt/FreeType does NOT synthesize bold for Gamja
     * Flower on this system at ANY weight -- Font.Medium through
     * Font.Black all rendered pixel-identical (paintedWidth fixed at
     * 107px across every weight for the same string/size). So the old
     * font.weight: Font.DemiBold/Bold literals throughout the dashboard
     * were inert -- text looked thin no matter what weight was set.
     * A same-colour Text.Outline pass (~1px stroke, style/styleColor)
     * was the only technique in that swatch that visibly thickened the
     * glyphs, so THAT is "heavy" for this face, not font.weight.
     * dashHeavy below is applied only at title/body call sites that need
     * genuine emphasis (media title, weather location, notification
     * title) -- captions/labels stay Text.Normal so a dense strip like
     * DashboardQuickStrip doesn't turn into stroked mush at 14px.
     */
    readonly property int dashTitle: Math.round(24 * Config.appearance.fontScale * DisplayScale.primary)
    readonly property int dashBody: Math.round(18 * Config.appearance.fontScale * DisplayScale.primary)
    readonly property int dashLabel: Math.round(16 * Config.appearance.fontScale * DisplayScale.primary)
    readonly property int dashCaption: Math.round(14 * Config.appearance.fontScale * DisplayScale.primary)
    // DashboardQuickStrip only: 7 icon+label+value cells share the 789px
    // strip, leaving each cell's text column ~55-65px wide -- too narrow
    // for dashCaption to render whole words like "Bluetooth"/"Network"
    // without eliding them into "Bluet…"/"Netw…", which reads as broken
    // rather than premium. Verified in render-dashboard.qml: this is the
    // largest size at which every current quick-strip label renders in
    // full at the live fontScale.
    readonly property int dashMicro: Math.round(10 * Config.appearance.fontScale * DisplayScale.primary)
    readonly property int dashHeavy: Text.Normal  // Bricolage has real weights; the Gamja synthetic-bold outline is off

    // Measured from the reference video by edge-inset scanning at 2560x1440.
    // The collapsed pill is FIXED width, not content-hugging.
    readonly property int pillW: 185
    readonly property int pillH: 50
    readonly property int islandTopMargin: 10

    // ================================================================
    //  PHASE A DESIGN UNIT -- every metric in the HTML prototype
    //  (../proto) is a multiple of one base unit. 44 = 50 * 92.6/109: the
    //  prototype was authored at 109 PPI and this machine's HDMI-A-1 runs
    //  92.6 PPI (1920x1080 / 23.8"), so 50 CSS px there lands at 44 px
    //  here. u(k) is the ONLY way Phase A geometry should reach the
    //  screen -- never a new pixel literal.
    // ================================================================
    readonly property real unit: 44 * Config.appearance.densityScale
    // DisplayScale.primary (core/DisplayScale.qml): shell-only DPI scaling,
    // applied at the one function every Phase A geometry literal already
    // routes through, so this laptop's ~157 PPI panel (vs the ~92 PPI
    // desktop this unit was tuned at) doesn't render 59% physical size.
    function u(k: real): int { return Math.round(unit * k * DisplayScale.primary) }

    function colorValue(name: string): string {
        return colors && colors[name] ? colors[name]
            : (dark ? fallbackDark[name] : fallbackLight[name])
    }

    function foregroundFor(candidate: color): color {
        const luminance = 0.2126 * candidate.r + 0.7152 * candidate.g
            + 0.0722 * candidate.b
        return luminance > 0.53 ? "#17151b" : "#ffffff"
    }

    function loadPalette(text) {
    if (text === undefined)
        text = activePaletteFile.text();
        try {
            const parsed = JSON.parse(text)
            if (!parsed.dark && !parsed.light)
                throw new Error("palette requires a dark or light object")
            generated = parsed
            generatedMode = parsed.mode === "light" ? "light" : "dark"
            generatedAvailable = true
        } catch (error) {
            generated = ({})
            generatedAvailable = false
            try {
                const fallback = JSON.parse(fallbackPaletteFile.text())
                if (!fallback.dark && !fallback.light)
                    throw new Error("fallback palette requires a dark or light object")
                generated = fallback
                generatedMode = fallback.mode === "light" ? "light" : "dark"
                generatedAvailable = true
                console.warn("Odyssey: active palette unavailable; using packaged fallback:", error)
            } catch (fallbackError) {
                console.warn("Odyssey: palette fallback unavailable:", fallbackError)
            }
        }
    }

    property FileView activePaletteFile: FileView {
        path: Config.appearance.activePalettePath
        preload: true
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.loadPalette()
        onFileChanged: reload()
        onLoadFailed: {
            root.generated = ({})
            root.generatedAvailable = false
        }
    }

    property FileView fallbackPaletteFile: FileView {
        path: Config.appearance.fallbackPalettePath
        preload: true
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            if (!root.generatedAvailable)
                root.loadPalette(fallbackPaletteFile.text())
        }
        onFileChanged: {
            reload()
            if (!root.generatedAvailable)
                root.loadPalette(fallbackPaletteFile.text())
        }
    }
}
