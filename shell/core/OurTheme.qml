pragma Singleton
import QtQuick

/**
 * Theme — generated from the HTML prototype, not hand-transcribed.
 *
 * Every palette here was produced by matugen from a real wallpaper, then
 * had two tokens added that matugen structurally cannot provide:
 *
 *   accent_fill  Material parks dark-mode `primary` at tone 80 (L~84), which
 *                is specified for TEXT on dark and reads as a pale wash when
 *                used as a large fill. Every matugen scheme type was tested;
 *                all four give the same tone. So accent_fill is derived here
 *                instead, pushed to a vivid mid-tone and then lifted until it
 *                clears 4.5:1 against accent_fg. Worst case across all 16
 *                palettes is 4.57:1, asserted in the prototype suite.
 *   surface_top/bot, sheen, hairline
 *                The surface treatment. Cheap on integrated graphics because
 *                it is geometry and colour, never translucency: a gradient is
 *                a vertex colour, a hairline is border.width, a sheen is a 1px
 *                Rectangle. No blur anywhere, which is the single reason this
 *                design survives a UHD 620.
 *
 * QML cannot parse CSS rgba(); alpha colours are emitted as #AARRGGBB.
 */
QtObject {
    id: root

    property string paletteName: "wall1-dark"
    readonly property bool dark: paletteName.indexOf("light") === -1

    readonly property var palettes: ({
        "wall1-dark": ({ accent: "#adc6ff", accent_fg: "#102f60", accent_fill: "#6695ff", bg: "#111318", bg_raised: "#1e1f25", bg_sunken: "#0c0e13", danger: "#ffb4ab", fg: "#e2e2e9", fg_dim: "#c4c6d0", fg_mute: "#8e9099", hairline: "#17ffffff", shadow: "#8c000000", sheen: "#1affffff", surface_bot: "#111318", surface_top: "#1a1c21", track: "#282a2f" }),
        "wall1-light": ({ accent: "#445e91", accent_fg: "#ffffff", accent_fill: "#445e91", bg: "#f9f9ff", bg_raised: "#ededf4", bg_sunken: "#ffffff", danger: "#ba1a1a", fg: "#1a1b20", fg_dim: "#44474f", fg_mute: "#74777f", hairline: "#17000000", shadow: "#29000000", sheen: "#d9ffffff", surface_bot: "#f5f5fb", surface_top: "#f5f5fb", track: "#e8e7ee" }),
        "wall2-dark": ({ accent: "#8ed5b1", accent_fg: "#003825", accent_fill: "#5cd698", bg: "#0f1511", bg_raised: "#1b211d", bg_sunken: "#0a0f0c", danger: "#ffb4ab", fg: "#dee4de", fg_dim: "#c0c9c1", fg_mute: "#8a938c", hairline: "#17ffffff", shadow: "#8c000000", sheen: "#1affffff", surface_bot: "#0f1511", surface_top: "#181e1a", track: "#262b28" }),
        "wall2-light": ({ accent: "#216a4d", accent_fg: "#ffffff", accent_fill: "#216a4d", bg: "#f5fbf5", bg_raised: "#eaefe9", bg_sunken: "#ffffff", danger: "#ba1a1a", fg: "#171d19", fg_dim: "#404943", fg_mute: "#707973", hairline: "#17000000", shadow: "#29000000", sheen: "#d9ffffff", surface_bot: "#f1f7f1", surface_top: "#f1f7f1", track: "#e4eae4" }),
        "wall3-dark": ({ accent: "#dfc56d", accent_fg: "#3b2f00", accent_fill: "#eec744", bg: "#16130b", bg_raised: "#221f17", bg_sunken: "#100e07", danger: "#ffb4ab", fg: "#e9e2d4", fg_dim: "#cec6b4", fg_mute: "#979080", hairline: "#17ffffff", shadow: "#8c000000", sheen: "#1affffff", surface_bot: "#16130b", surface_top: "#1f1c14", track: "#2d2a21" }),
        "wall3-light": ({ accent: "#705d0d", accent_fg: "#ffffff", accent_fill: "#705d0d", bg: "#fff8ef", bg_raised: "#f5eddf", bg_sunken: "#ffffff", danger: "#ba1a1a", fg: "#1e1b13", fg_dim: "#4b4639", fg_mute: "#7d7767", hairline: "#17000000", shadow: "#29000000", sheen: "#d9ffffff", surface_bot: "#fbf4eb", surface_top: "#faf4eb", track: "#efe7da" }),
        "wall4-dark": ({ accent: "#ffb3ad", accent_fg: "#571e1b", accent_fill: "#ff685c", bg: "#1a1110", bg_raised: "#271d1c", bg_sunken: "#140c0b", danger: "#ffb4ab", fg: "#f1dedc", fg_dim: "#d8c2bf", fg_mute: "#a08c8a", hairline: "#17ffffff", shadow: "#8c000000", sheen: "#1affffff", surface_bot: "#1a1110", surface_top: "#241a19", track: "#322827" }),
        "wall4-light": ({ accent: "#904a45", accent_fg: "#ffffff", accent_fill: "#904a45", bg: "#fff8f7", bg_raised: "#fceae8", bg_sunken: "#ffffff", danger: "#ba1a1a", fg: "#231918", fg_dim: "#534342", fg_mute: "#857371", hairline: "#17000000", shadow: "#29000000", sheen: "#d9ffffff", surface_bot: "#fbf4f3", surface_top: "#fbf4f3", track: "#f6e4e2" }),
        "wall5-dark": ({ accent: "#ffb4a7", accent_fg: "#561e16", accent_fill: "#ff674d", bg: "#1a1110", bg_raised: "#271d1c", bg_sunken: "#140c0b", danger: "#ffb4ab", fg: "#f1dfdb", fg_dim: "#d8c2be", fg_mute: "#a08c89", hairline: "#17ffffff", shadow: "#8c000000", sheen: "#1affffff", surface_bot: "#1a1110", surface_top: "#241a19", track: "#322826" }),
        "wall5-light": ({ accent: "#904b3f", accent_fg: "#ffffff", accent_fill: "#904b3f", bg: "#fff8f6", bg_raised: "#fceae7", bg_sunken: "#ffffff", danger: "#ba1a1a", fg: "#231918", fg_dim: "#534340", fg_mute: "#857370", hairline: "#17000000", shadow: "#29000000", sheen: "#d9ffffff", surface_bot: "#fbf4f2", surface_top: "#fbf4f2", track: "#f7e4e1" }),
        "wall6-dark": ({ accent: "#dac76f", accent_fg: "#393000", accent_fill: "#e7cc4b", bg: "#15130b", bg_raised: "#222017", bg_sunken: "#100e07", danger: "#ffb4ab", fg: "#e8e2d4", fg_dim: "#cdc6b4", fg_mute: "#969080", hairline: "#17ffffff", shadow: "#8c000000", sheen: "#1affffff", surface_bot: "#15130b", surface_top: "#1e1c14", track: "#2c2a21" }),
        "wall6-light": ({ accent: "#6c5e0f", accent_fg: "#ffffff", accent_fill: "#6c5e0f", bg: "#fff9ed", bg_raised: "#f4eddf", bg_sunken: "#ffffff", danger: "#ba1a1a", fg: "#1e1c13", fg_dim: "#4a4739", fg_mute: "#7c7768", hairline: "#17000000", shadow: "#29000000", sheen: "#d9ffffff", surface_bot: "#fbf5e9", surface_top: "#faf5e9", track: "#eee8da" }),
        "wall7-dark": ({ accent: "#cdca75", accent_fg: "#333200", accent_fill: "#d7d35b", bg: "#14140c", bg_raised: "#212018", bg_sunken: "#0f0e07", danger: "#ffb4ab", fg: "#e6e2d5", fg_dim: "#cac7b6", fg_mute: "#939181", hairline: "#17ffffff", shadow: "#8c000000", sheen: "#1affffff", surface_bot: "#14140c", surface_top: "#1d1d15", track: "#2b2a22" }),
        "wall7-light": ({ accent: "#636117", accent_fg: "#ffffff", accent_fill: "#636117", bg: "#fdf9ec", bg_raised: "#f2eee0", bg_sunken: "#ffffff", danger: "#ba1a1a", fg: "#1c1c14", fg_dim: "#48473a", fg_mute: "#797869", hairline: "#17000000", shadow: "#29000000", sheen: "#d9ffffff", surface_bot: "#f9f5e8", surface_top: "#f8f5e8", track: "#ece8db" }),
        "wall8-dark": ({ accent: "#8ccff0", accent_fg: "#003547", accent_fill: "#33bcff", bg: "#0f1417", bg_raised: "#1b2023", bg_sunken: "#0a0f12", danger: "#ffb4ab", fg: "#dfe3e7", fg_dim: "#c0c8cd", fg_mute: "#8a9297", hairline: "#17ffffff", shadow: "#8c000000", sheen: "#1affffff", surface_bot: "#0f1417", surface_top: "#181d20", track: "#262b2e" }),
        "wall8-light": ({ accent: "#146683", accent_fg: "#ffffff", accent_fill: "#146683", bg: "#f6fafe", bg_raised: "#eaeef2", bg_sunken: "#ffffff", danger: "#ba1a1a", fg: "#171c1f", fg_dim: "#40484c", fg_mute: "#70787d", hairline: "#17000000", shadow: "#29000000", sheen: "#d9ffffff", surface_bot: "#f2f6fa", surface_top: "#f2f6fa", track: "#e4e9ec" })
    })

    readonly property var p: palettes[paletteName] || palettes["wall1-dark"]

    readonly property color accent: p.accent
    readonly property color accent_fg: p.accent_fg
    readonly property color accent_fill: p.accent_fill
    readonly property color bg: p.bg
    readonly property color bg_raised: p.bg_raised
    readonly property color bg_sunken: p.bg_sunken
    readonly property color danger: p.danger
    readonly property color fg: p.fg
    readonly property color fg_dim: p.fg_dim
    readonly property color fg_mute: p.fg_mute
    readonly property color hairline: p.hairline
    readonly property color shadow: p.shadow
    readonly property color sheen: p.sheen
    readonly property color surface_bot: p.surface_bot
    readonly property color surface_top: p.surface_top
    readonly property color track: p.track

    // ---- typography -------------------------------------------------
    // Three roles, all OFL so they ship with the repo. SF Pro and
    // PP Editorial New were rejected for being non-redistributable: a
    // shell that only looks right on the author's machine is a screenshot,
    // not a project.
    readonly property string fontDisplay: "Instrument Serif"
    readonly property string fontUi: "Geist"
    readonly property string fontData: "Geist Mono"
    readonly property real trackDisplay: -0.02
    readonly property real trackMicro: 0.1

    // ---- geometry ---------------------------------------------------
    // Measured from the source video by edge-inset scanning, at native
    // 2560x1440. The collapsed pill is FIXED width, not content-hugging.
    readonly property real unit: 50            // collapsed pill height
    readonly property real pillW: 185
    readonly property real pillH: 50
    readonly property real expandedW: 700      // every wide state is 700
    readonly property real expandedH: 114
    readonly property real topMargin: 10
    // One rule fits 5 of 6 measured states.
    function radiusFor(h) { return Math.min(h / 2, 40) }
}
