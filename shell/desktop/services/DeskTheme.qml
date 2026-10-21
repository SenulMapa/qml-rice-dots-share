// Desktop theme singleton
// Design tokens for desktop widgets

pragma Singleton

import QtQuick
import "../../core" as Core

// Reuses the shell's main Theme (adaptive wallpaper palette via
// core/PaletteAutoService -> core/Theme) for colors and adds desktop-specific
// metrics. Nothing here reads PaletteAutoService directly -- Theme already
// merges its `generated` palette, so DeskTheme just forwards Theme's tokens
// under impasto's naming.
QtObject {
    id: root

    // ── SEMANTIC COLOURS ─────────────────────────────────────────────────────
    //
    // impasto's own theme/Theme.qml values, verbatim -- its flat near-black
    // grounds and the iOS system accents (#0a84ff blue, #ff453a red,
    // #32d74b green, #ffd60a yellow) with pure-white ink over them. These
    // were piped through this shell's Material palette instead
    // (Core.Theme.primary etc.), which is why the ported cards read as
    // washed-out grey with a pale lilac accent next to impasto's own
    // screenshots: matugen's wallpaper-derived primary (#adc6ff today) is a
    // tint, not an accent, and surfaceVariantText is far lower contrast than
    // impasto's #8e8e93.
    //
    // `impastoPalette` false hands these straight back to the adaptive
    // Material tokens, which is what the "Adaptive (Wallpaper)" theme in
    // impasto's own settings does -- repainting these values from the
    // wallpaper is the repaint branch's job, and it recolours THESE tokens
    // rather than replacing them with ours.
    readonly property bool impastoPalette: Core.Config.appearance.impastoPalette

    // Ink redesign (Config.appearance.ink). When on, every token below takes
    // its ink value and the impasto grounds/accents step aside, so each face
    // that reads DeskTheme follows the ink language without its own branch.
    // Off, the values are exactly the impasto/adaptive ones above and below.
    readonly property bool inkMode: Core.Config.appearance.ink

    // Ink: cards are #000, text is the white alpha ramp, and the accent is
    // the active-control fill (#f5f5f7 with a black glyph), so chrome is
    // monochrome. Semantic red/green/amber keep their iOS values.
    property color background: root.inkMode ? Core.Theme.ink
        : root.impastoPalette ? "#0c0c0c" : Core.Theme.surface
    property color surface: root.inkMode ? Core.Theme.ink
        : root.impastoPalette ? "#141414" : Core.Theme.surfaceContainer
    property color surfaceHover: root.inkMode ? Core.Theme.inkRaised
        : root.impastoPalette ? "#202020" : Core.Theme.surfaceContainerHigh
    property color border: root.inkMode ? Core.Theme.inkRim
        : root.impastoPalette ? "#282828" : Core.Theme.outlineVariant
    property color text: root.inkMode ? Core.Theme.t1
        : root.impastoPalette ? "#ffffff" : Core.Theme.surfaceText
    property color textMuted: root.inkMode ? Core.Theme.t2
        : root.impastoPalette ? "#8e8e93" : Core.Theme.surfaceVariantText
    property color accent: root.inkMode ? Core.Theme.fillOn
        : root.impastoPalette ? "#0a84ff" : Core.Theme.primary
    property color accentHover: root.inkMode ? "#d2d2d7"
        : root.impastoPalette ? "#409cff" : Core.Theme.primaryContainer
    property color accentText: root.inkMode ? Core.Theme.glyphOn
        : root.impastoPalette ? "#ffffff" : Core.Theme.primaryText

    property color red: root.inkMode || root.impastoPalette ? "#ff453a" : Core.Theme.error
    property color green: root.inkMode || root.impastoPalette ? "#32d74b" : Core.Theme.success
    property color yellow: root.inkMode || root.impastoPalette ? "#ffd60a" : Core.Theme.warning
    property color blue: root.inkMode ? Core.Theme.fillOn
        : root.impastoPalette ? "#0a84ff" : Core.Theme.primary

    // Status indicators
    readonly property color indicator: root.text
    readonly property color indicatorDim: root.inkMode ? Core.Theme.t3
        : root.impastoPalette ? "#4d4d4d" : root.textMuted
    readonly property color indicatorGood: root.green
    readonly property color indicatorWarn: root.yellow
    readonly property color indicatorBad: root.red
    readonly property color indicatorTimer:
        root.inkMode ? root.text : root.impastoPalette ? "#64d2ff" : root.blue

    // Ground and ink over photographs
    readonly property color scrim: root.impastoPalette ? "#bf000000" : Qt.rgba(0, 0, 0, 0.75)
    readonly property color scrimText: "#ffffff"
    readonly property color hairline: root.impastoPalette && !root.inkMode ? "#20ffffff" : Core.Theme.hairline

    // The island/dock chrome colour, reused for a widget's resize handle and
    // drag-value pill so they read as part of the same chrome family.
    // Ink redesign (Config.appearance.ink): the island is #000 and its hover
    // is inkRaised, overriding the impasto grounds below.
    readonly property color islandSurface:
        Core.Config.appearance.ink ? Core.Theme.ink
        : root.impastoPalette ? "#141414" : Core.Theme.islandSurface
    readonly property color islandSurfaceHover:
        Core.Config.appearance.ink ? Core.Theme.inkRaised
        : root.impastoPalette ? "#1f1f1f" : Qt.lighter(Core.Theme.islandSurface, 1.35)
    readonly property color islandBorder:
        root.inkMode ? Core.Theme.inkRim
        : root.impastoPalette ? "#262626" : Core.Theme.outline
    // Back-compat alias for the handful of ported files still spelled "island".
    readonly property color island: root.islandSurface

    // Sticky-note paper: a palette tint washed towards white, with ink that
    // reads on it regardless of the active (light/dark) mode.
    readonly property color paperWash: "#c4ffffff"
    readonly property color paperInk: "#1c1c1e"
    readonly property color paperInkMuted: "#8a1c1c1e"
    readonly property color paperLine: "#261c1c1e"
    readonly property int paperRadius: 10

    // Contribution graph, empty to busiest. GitHub's dark ramp, fixed across
    // palettes; the empty step is lifted off black so it reads as a cell.
    readonly property var githubLevels: [
        "#26292e", "#0e4429", "#006d32", "#26a641", "#39d353"
    ]

    // Photo widget's corner crop, as a fraction of the shorter side.
    readonly property real pictureCorner: 0.24

    // A widget's right-click context menu (Tray/Inspector's PopMenu).
    readonly property int dockMenuWidth: 250
    readonly property int dockMenuRow: 30
    readonly property int dockMenuPadding: 6
    readonly property int panelPadding: 20

    // ── BAR METRICS ──────────────────────────────────────────────────────────
    //
    // The island pill reserves this much space at the top of the screen
    // (see island/Island.qml -> core/Theme pillH/islandTopMargin); the
    // desktop board sits below it so widgets never land under the pill.
    readonly property int capsuleHeight: Core.Theme.pillH
    readonly property int barTopMargin: Core.Theme.islandTopMargin
    readonly property int capsuleSpacing: 8
    readonly property int barReserve: root.barTopMargin + root.capsuleHeight
    readonly property int barBand: root.barReserve + 8

    // ── DESKTOP METRICS ──────────────────────────────────────────────────────
    //
    // A square is at least `desktopCell` and grows up to `desktopCellLargest`
    // when squeezing two rows or columns into one cell's space.
    readonly property int desktopCell: 86
    readonly property int desktopCellLargest: 108
    readonly property int desktopGutter: 18
    readonly property int desktopStride: root.desktopCell + root.desktopGutter
    // Ink: cards take the card radius (22), the same as the island's pages.
    readonly property int desktopRadius: root.inkMode ? Core.Theme.rCard : Core.Theme.radiusMedium
    readonly property int radiusSmall: Core.Theme.radiusSmall
    readonly property int radiusMedium: Core.Theme.radiusMedium
    readonly property int radiusLarge: Core.Theme.radiusLarge
    readonly property int radiusPill: 999

    // Ported verbatim from impasto's theme/Theme.qml (shadowRange/
    // shadowOpacity/shadowColor/shadowSpread only -- not shadowBarRange/
    // shadowBarSpread, which scale for impasto's own bar and have no user
    // here), for settings-impasto/components/WindowsPreview.qml's lifted-
    // window shadow.
    readonly property int shadowRange: 14
    readonly property real shadowOpacity: 0.5
    readonly property color shadowColor: "#000000"
    readonly property int shadowSpread: 4

    // ── CONTROL-CENTRE GRID METRICS ──────────────────────────────────────────
    //
    // Ported verbatim from impasto's theme/Theme.qml (github.com/andreumassanet/
    // impasto, GPL-3.0, Andreu Massanet): the freeform block grid's own cell
    // size, distinct from the desktop widget grid above (`desktopCell` etc.).
    // Used by dashboard/services/DashBlocksService.qml and dashboard/controls/
    // {Block,BlockFace,BlockInspector,ControlsTray}.qml.
    readonly property int centreColumns: 6
    readonly property int centreRows: 8
    readonly property int centreCellWidth: 140
    readonly property int centreCellHeight: 64
    readonly property int centreGutter: 12
    readonly property int centreStrideX: root.centreCellWidth + root.centreGutter
    readonly property int centreStrideY: root.centreCellHeight + root.centreGutter

    // ── TYPE ─────────────────────────────────────────────────────────────────
    //
    // impasto's own family list ("Inter, Cantarell, SF Pro Text, sans-serif")
    // -- Inter/Cantarell aren't installed on this machine, so Qt's font
    // fallback lands on SF Pro Text, which is (see `fc-list`). fontMono is
    // JetBrainsMono Nerd Font Mono, installed. Both kept as-is per the
    // "keep impasto's where installed" rule; Bricolage Grotesque (installed)
    // is the fallback family if that chain ever fully misses.
    readonly property string fontFamily: root.inkMode ? "Geist, sans-serif"
        : "Inter, Cantarell, SF Pro Text, Bricolage Grotesque, sans-serif"
    // Ink: display numerals (clock, temperature, %, counts) in Instrument
    // Serif. Faces opt in per reading; off, numerals stay in fontFamily.
    readonly property string fontNumeral: root.inkMode ? "Instrument Serif" : root.fontFamily
    readonly property string fontMono: "JetBrainsMono Nerd Font Mono, Geist Mono, monospace"
    // Notes' handwriting face: no signature/handwriting font is installed,
    // so this stays the body family rather than inventing a fourth font.
    // Script face for notes/the notes deck -- impasto's own
    // theme/Theme.qml checks Qt.fontFamilies() explicitly rather than
    // trusting Qt's silent substitution for a missing family. "Grape Nuts"
    // is installed on this machine (~/.local/share/fonts/
    // GrapeNuts-Regular.ttf, confirmed via `fc-list`); "Georgia" is
    // impasto's own second choice.
    readonly property string fontSignature: {
        const installed = Qt.fontFamilies()
        for (const family of ["Grape Nuts", "Georgia"]) {
            if (installed.indexOf(family) !== -1)
                return family
        }
        return root.fontFamily
    }

    // Note bodies: handwriting, unconditionally -- this shell has no
    // equivalent of impasto's SettingsService.notesHandwriting toggle to
    // gate it on, so it always resolves to fontSignature (which itself
    // still falls back to fontFamily above if no script face is
    // installed).
    readonly property string fontHand: root.fontSignature

    readonly property int fontSizeLabel: 10
    readonly property int fontSizeSmall: 11
    readonly property int fontSizeRegular: 13
    readonly property int fontSizeMedium: 14
    readonly property int fontSizeLarge: 16
    // Desktop widgets are read from further away.
    readonly property int fontSizeWidget: 30
    readonly property int fontSizeDisplay: 68

    // ── ANIMATIONS ──────────────────────────────────────────────────────────

    readonly property int paletteTransition: 260
    readonly property int durationFast: 140
    readonly property int durationMedium: 220
    // impasto: theme/Theme.qml's `durationMorph` (Math.round(380 *
    // motion)), used by the games shelf carousel (components/Carousel.qml).
    // This shell's own island-morph timing already lives in Config/
    // Animations, not DeskTheme; ported code that needs this exact token
    // gets a static 380 rather than wiring in this shell's separate motion-
    // scale mechanism, since DeskTheme has no motion-scale concept of its
    // own to multiply it by.
    readonly property int durationMorph: 380
    readonly property int easing: Easing.OutCubic

    // Ported from impasto's theme/Theme.qml `easingCurves`/`motionPresets`/
    // `easingTypeOf` (github.com/andreumassanet/impasto, GPL-3.0), for
    // settings-impasto/components/{MotionPreview,IslandMotionPreview}.qml's
    // animated tiles. Upstream keys its presets to its OWN motionScale/
    // motionCurve pair; this shell has no such pair, only
    // Config.appearance.motionSpeed's three-way enum
    // (SettingsStore.validMotionSpeeds: "quick"/"balanced"/"calm"), so the
    // list below is a new mapping of THAT enum onto the same
    // { id, label, scale, curve } preset shape, not a verbatim copy of
    // impasto's own smooth/snappy/springy/off set. Additive only: nothing
    // here changes durationFast/durationMedium above, so no existing
    // Behavior anywhere else in the shell changes speed. Wiring motionSpeed
    // into the shell's own global animation durations is a separate,
    // larger, pre-existing gap (SettingsStore/Config already define the
    // setting; nothing outside these settings previews reads it) that is
    // out of scope for a settings-window port.
    readonly property var easingCurves: [
        { id: "OutCubic", label: "Smooth",  type: Easing.OutCubic },
        { id: "OutQuint", label: "Snappy",  type: Easing.OutQuint },
        { id: "OutBack",  label: "Springy", type: Easing.OutBack },
        { id: "Linear",   label: "Flat",    type: Easing.Linear }
    ]

    function easingTypeOf(id: string): int {
        const curve = root.easingCurves.find(entry => entry.id === id)
        return curve ? curve.type : Easing.OutCubic
    }

    readonly property var motionPresets: [
        { id: "quick",    label: "Quick",    scale: 70,  curve: "OutQuint" },
        { id: "balanced", label: "Balanced", scale: 100, curve: "OutCubic" },
        { id: "calm",     label: "Calm",     scale: 140, curve: "OutCubic" }
    ]

    Behavior on background   { ColorAnimation { duration: root.paletteTransition } }
    Behavior on surface      { ColorAnimation { duration: root.paletteTransition } }
    Behavior on surfaceHover { ColorAnimation { duration: root.paletteTransition } }
    Behavior on border       { ColorAnimation { duration: root.paletteTransition } }
    Behavior on text         { ColorAnimation { duration: root.paletteTransition } }
    Behavior on textMuted    { ColorAnimation { duration: root.paletteTransition } }
    Behavior on accent       { ColorAnimation { duration: root.paletteTransition } }
    Behavior on accentHover  { ColorAnimation { duration: root.paletteTransition } }
}
