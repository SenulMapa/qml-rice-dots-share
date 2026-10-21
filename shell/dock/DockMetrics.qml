pragma Singleton
import QtQuick

/**
 * DockMetrics -- every tunable of the dock, in one place.
 *
 * Source of each value: "Tahoe 1x scaled to 92 PPI" = the macOS 26 Dock at its
 * 1x defaults, scaled to this machine (1080p at 92 PPI), owner-approved 19 Oct.
 * Values still marked "pending reference capture" are the earlier estimates.
 * tools/mac-dock/analyze_capture.py measures the real dock from a screen
 * recording and tools/mac-dock/apply-metrics.py overwrites the values below
 * (it edits the numbers on the `property` lines and replaces the trailing
 * "// src:" comment). Keep one property per line in that exact shape.
 *
 * Pixel values are at the 1080p reference (Theme.unit 44); Dock scales them
 * by Theme.u(1) / 44.
 */
QtObject {
    // ---- geometry ----
    readonly property real tileSize: 44            // src: compact, owner 19 Oct ("dock smaller, apps need more space"). Icon edge px @1x, resting
    readonly property real slotGap: 6              // src: compact, owner 19 Oct ("dock smaller, apps need more space"). Gap between icon edges
    readonly property real shelfPadding: 7        // src: compact, owner 19 Oct ("dock smaller, apps need more space"). Shelf padding around the icons (top, sides, bottom; the running dot sits in the bottom padding)
    readonly property real shelfRadius: 20         // src: compact, owner 19 Oct ("dock smaller, apps need more space"). Shelf corner radius; (iconSize + 2 x padding) / 2.8, never a full pill
    readonly property real bottomMargin: 6         // src: compact, owner 19 Oct ("dock smaller, apps need more space"). Gap between screen edge and shelf
    readonly property real separatorWidth: 1       // src: Tahoe 1x scaled to 92 PPI (owner-approved direction 19 Oct). Separator line width
    readonly property real separatorMargin: 6      // src: compact, owner 19 Oct ("dock smaller, apps need more space"). Space each side of the separator
    readonly property real separatorInset: 9      // src: compact, owner 19 Oct ("dock smaller, apps need more space"). Separator inset from the shelf top and bottom
    readonly property real dotSize: 3.5              // src: compact, owner 19 Oct ("dock smaller, apps need more space"). Running indicator diameter
    readonly property real dotGap: 1.5               // src: compact, owner 19 Oct ("dock smaller, apps need more space"). Gap icon bottom to dot top; dot centre sits 5 px below the icon
    readonly property real dotAlpha: 0.75          // src: Tahoe 1x scaled to 92 PPI (owner-approved direction 19 Oct). Running indicator white alpha

    // ---- shelf glass (shaders/tahoe-glass.frag via components/TahoeGlass.qml) ----
    readonly property real glassTintAlpha: 0.12    // src: Tahoe 1x scaled to 92 PPI (owner-approved direction 19 Oct). White body alpha
    readonly property real glassRimTop: 0.55       // src: Tahoe 1x scaled to 92 PPI (owner-approved direction 19 Oct). Specular rim alpha at the top edge
    readonly property real glassRimSide: 0.15      // src: Tahoe 1x scaled to 92 PPI (owner-approved direction 19 Oct). Specular rim alpha on sides and bottom
    readonly property real glassInnerGlow: 0.08    // src: Tahoe 1x scaled to 92 PPI (owner-approved direction 19 Oct). Inner glow alpha at the edge (6 px falloff)
    readonly property real glassShadowAlpha: 0.16  // src: Tahoe 1x scaled to 92 PPI (owner-approved direction 19 Oct). Drop shadow peak (black), fix round 1
    readonly property real glassShadowBlur: 20     // src: Tahoe 1x scaled to 92 PPI (owner-approved direction 19 Oct). Drop shadow falloff px
    readonly property real glassShadowY: 4         // src: Tahoe 1x scaled to 92 PPI (owner-approved direction 19 Oct). Drop shadow offset px, down

    // Per-icon optical offset [dx, dy] as fractions of the icon edge, applied
    // after scale. text-editor is the Papirus glyph, measured off-centre by
    // +0.078 x and +0.016 y of its 512 canvas (bbox centre), times its 0.89 scale.
    readonly property var iconVisualOffset: ({
        "text-editor": [-0.069, -0.014]
    })

    // Per-icon visual size correction, keyed by the theme icon name (the
    // model's icon). The qml-rice-mac theme plates most apps at 80.5% of the
    // canvas; a factor of 0.805 / measured size makes an icon read the same
    // size as a standard plate. Measured on theme 512x512 PNGs (19 Oct); only
    // icons more than 2% off are listed. text-editor is not in the theme, so it
    // is measured on the Papirus fallback. Re-measure after a theme rebuild.
    readonly property var iconVisualScale: ({
        "claude-desktop": 1.25, "com.anthropic.Claude": 1.25, "com.anthropic.claude": 1.25,
        "libreoffice-calc": 1.24, "libreoffice-impress": 1.25, "libreoffice-startcenter": 0.975,
        "nvidia-settings": 1.03, "discord": 1.02, "qalculate": 1.09, "qalculate-gtk": 1.09,
        "zen": 0.805, "zen-browser": 0.805, "zen-alpha": 0.805, "zen-twilight": 0.805,
        "app.zen_browser.zen": 0.805,
        "text-editor": 0.89
    })

    // ---- magnification ----
    readonly property real peakScale: 1.45         // src: Tahoe 1x scaled to 92 PPI (owner-approved direction 19 Oct). Scale under pointer, capped at 1.45
    readonly property real radiusTiles: 2.5        // src: pending reference capture. Influence radius in tile pitches
    readonly property string falloff: "cosine"     // src: pending reference capture. cosine or gauss
    readonly property real pointerOmega: 34        // src: pending reference capture. Pointer follow stiffness 1/s (critically damped, ~135 ms settle)
    readonly property real rampOmega: 22           // src: pending reference capture. Enter/leave magnification ramp 1/s (~210 ms)

    // ---- launch bounce ----
    readonly property real bounceHeight: 0.5       // src: pending reference capture. Rise as a fraction of the tile height
    readonly property real bouncePeriod: 0.6       // src: pending reference capture. Seconds per bounce
    readonly property real bounceRestFraction: 0.1 // src: pending reference capture. Share of each period spent on the ground
    readonly property real bounceMaxSeconds: 10    // src: pending reference capture. Give up waiting for the window after this

    // ---- autohide ----
    readonly property real revealDelay: 0.2        // src: pending reference capture. Seconds the pointer must rest on the edge
    readonly property real hideDelay: 0.3          // src: pending reference capture. Seconds after the pointer leaves before hiding
    readonly property real slideDuration: 0.45     // src: pending reference capture. Slide in/out seconds
    readonly property real edgeTrigger: 2          // src: pending reference capture. Screen-bottom hover strip height px

    // ---- label, press, poof ----
    readonly property real labelGap: 10            // src: pending reference capture. Gap icon-top to tooltip
    readonly property real labelFontPx: 13         // src: Tahoe 1x scaled to 92 PPI (owner-approved direction 19 Oct). Tooltip text px
    readonly property real labelDelay: 0.0         // src: pending reference capture. Seconds hovering before the label shows
    readonly property real pressDarken: 0.3        // src: pending reference capture. Black overlay opacity while pressed
    readonly property real poofSeconds: 0.45       // src: pending reference capture. Unpin poof duration
    readonly property real unpinDistance: 70       // src: pending reference capture. Px above the shelf where release unpins
    readonly property real reorderStartPx: 6       // src: pending reference capture. Movement before a press becomes a drag
}
