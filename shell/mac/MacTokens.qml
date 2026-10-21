pragma Singleton
import QtQuick
import Quickshell
import "../core"

/**
 * MacTokens -- every measured value of the Tahoe ("mac") presentation, in one
 * place. Source: docs/superpowers/specs/2026-10-19-mac-style-design.md
 * sections 3 and 4, measured on the Tahoe 2x captures (.superpowers/tahoe-ref).
 *
 * Units are pt, the Tahoe values, never scaled to our screen width. Use
 * `s(pt)` at the point of use to apply DisplayScale, the same way Theme.u()
 * does. Confidence tags on each line:
 *   M = measured from clean edges
 *   E = estimated from the image; confirm in a live view before it is "done"
 *   A = Apple render, proportions only (no scale); see the call banner
 */
QtObject {
    id: root

    // False under the offscreen harnesses: PanelWindow has no layer-shell
    // backend there, so every mac layer window is left unbuilt (the harness
    // drives the Item content directly). The live Wayland shell is always true.
    readonly property bool layerShell: Quickshell.env("QT_QPA_PLATFORM") !== "offscreen"

    // Applies the shell's display scale and the mac scale (Config.appearance.
    // macScale, output width / 1440) to a pt value. Every mac geometry, font
    // size, radius and inset goes through here.
    function s(pt: real): real {
        return pt * DisplayScale.primary * Config.appearance.macScale
    }

    // True when tools/glass-plugin (alpha-mask mode) draws the glass. The plugin
    // frosts only where a surface paints solid alpha and adds its own rim and
    // highlight, so QML must not add drop shadows, rims or glow (any alpha above
    // Hyprland's ignore_alpha turns the whole window into a frosted halo). Set
    // false only when the plugin is not loaded.
    readonly property bool compositorGlass: true

    // ---- fonts (spec 3.x type sizes) ------------------------------------
    // SF Pro is used when Qt reports it, otherwise Geist. Nothing is bundled:
    // SF Pro is only ever read from the local system (~/.local/share/fonts).
    // Qt.fontFamilies() matches the family name exactly, and it reports
    // "SF Pro Text", "SF Pro Display" and "SF Pro" (verified 20 Oct, offscreen
    // and at startup). The detection was never the fault. The Geist that
    // showed in the renders came from mono numerals (Config.monoFontFamily,
    // Geist Mono) and from shared avatar text. Those now read these tokens.
    function _family(candidates: var, fallback: string): string {
        const installed = Qt.fontFamilies()
        for (const name of candidates) {
            if (installed.indexOf(name) >= 0)
                return name
        }
        return fallback
    }
    readonly property string textFamily: _family(["SF Pro Text", "SF Pro"], "Geist")
    readonly property string displayFamily: _family(["SF Pro Display", "SF Pro Text", "SF Pro"], "Geist")

    // ---- Tahoe palette (20 Oct, owner direction; replaces Theme.primary and
    // the semantic Theme.error / Theme.success inside shell/mac/) ----------
    readonly property color accentBlue: "#0a84ff"        // A, Apple systemBlue: active tiles, toggles, selected rows, Reminders
    readonly property color accentOn: "#ffffff"          // A, white text and glyphs on the accent
    readonly property color criticalFill: "#ff3b30"      // A, Apple systemRed: critical avatar
    readonly property color callDecline: "#ff3b30"       // A, Apple systemRed
    readonly property color callAnswer: "#34c759"        // A, Apple systemGreen
    readonly property color spotlightSelectedFill: ink ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0.55, 0.68, 0.80, 0.55)  // E, translucent blue-grey row (Tahoe 05), dark text kept

    // ---- 3.1 banner (single toast) --------------------------------------
    readonly property real bannerWidth: 343              // M
    readonly property real bannerHeight: 72              // E, method weak: re-measure
    readonly property real bannerInsetRight: 17          // M (NC right edge 1423 of 1440)
    readonly property real bannerInsetTop: 36            // E, clears the menu-bar strip (was 8, sat on it)
    readonly property real bannerRadius: 16              // E, reference crop corners read larger than 11-13
    readonly property real bannerTitleSize: 13           // E, semibold
    readonly property real bannerBodySize: 13            // E, regular (owner 19 Oct: 13 pt dark ink)
    readonly property int bannerSlideInMs: 350           // E, ease-out, from the right edge (brief: about 350 ms)
    readonly property int bannerSlideOutMs: 220          // E, to the right with a fade
    readonly property color bannerSampleFill: "#619CEF"  // M colour, over wallpaper: reference only

    // ---- 3.3 Notification Center column ---------------------------------
    readonly property real ncColumnLeft: 1080            // M
    readonly property real ncColumnRight: 1423           // M
    readonly property real ncColumnWidth: 343            // M
    readonly property real ncWidgetGap: 14               // E
    readonly property real ncWeatherWidth: 343           // M, medium weather widget
    readonly property real ncWeatherHeight: 163          // M
    readonly property real ncListWidgetHeight: 163       // M, list widget = weather widget height (crop 02)
    readonly property real ncWidgetRadius: 24            // E, 22-26 continuous
    readonly property color ncCalendarFill: "#F4F4F4"    // M
    readonly property color ncWeatherFill: "#66829B"     // M, dark blue-grey glass

    // Feathered backdrop behind the NC (MacNcBackdropWindow). Its alpha is the
    // mask the compositor glass plugin blurs by, so it fades in from the left.
    readonly property real ncBackdropWidth: 720          // E, the NC column plus a long feather
    readonly property real ncBackdropMaxAlpha: 0.22      // E, black alpha at the right edge
    // Top-right hot corner that toggles the NC (MacNcCorner), logical px.
    readonly property real ncCornerSize: 16              // E, clickable, paints nothing

    // ---- 3.4 Control Center (modules float on the wallpaper) ------------
    readonly property real ccGridLeft: 1134              // M
    readonly property real ccGridRight: 1426             // M
    readonly property real ccGridWidth: 292              // M
    readonly property real ccTileWidth: 138              // M, Wi-Fi / Bluetooth / Focus
    readonly property real ccTileHeight: 63              // M / E
    readonly property real ccTileRadius: 31              // M, full pill (half the height)
    readonly property real ccRowPitch: 76                // M, top to top
    readonly property real ccRowGap: 13                  // M (pitch minus tile height)
    readonly property real ccRoundDiameter: 62           // M, AirDrop / mirror / screenshot circles
    readonly property real ccSliderWidth: 292            // M, Display / Sound
    readonly property real ccSliderHeight: 63            // M
    readonly property real ccSliderTrack: 4              // E, 2x crop: about 8 px thick (was 3)
    readonly property real ccSliderHandle: 20            // E, hit height of a slider row
    readonly property real ccNowPlayingWidth: 138        // E
    readonly property real ccNowPlayingHeight: 139       // M, two rows high: 63 + 13 + 63
    readonly property real ccTitleSize: 13               // E, semibold, white
    readonly property real ccSubtitleSize: 11            // E, regular
    readonly property real ccSubtitleAlpha: 0.62         // E, white at 62% (Theme.t2)
    readonly property color ccActiveSample: "#8CB3FA"    // M, reference only: active fill is accentBlue
    readonly property int ccMotionMs: 260                // E, Motion.surfaceMorph
    readonly property real ccMotionFromScale: 0.96       // E, fade plus scale, anchored top right
    // Control Center additions (M/E/A as above). Grid cell pitch and placement.
    readonly property real ccInsetRight: 14              // M, 1440 - 1426 (grid right edge)
    readonly property real ccInsetTop: 70                // M, screen top to the Wi-Fi tile (Screenshot pill sits above it)
    readonly property real ccColPitch: 76                // M, round toggle to round toggle (62 + 14)
    readonly property real ccEditY: 460                  // M, Edit Controls pill top, from the grid top
    readonly property real ccEditWidth: 94               // E
    readonly property real ccEditHeight: 18              // E
    readonly property real ccEditTextSize: 11            // E
    readonly property real ccDiscDiameter: 36            // E, white icon disc inside pill tiles
    readonly property real ccDiscInset: 14               // E, disc left inset in a pill tile
    readonly property real ccTileTextLeft: 56            // E, title column left in a pill tile
    readonly property real ccSubtitleGap: 2              // E, title to subtitle
    readonly property real ccIconSize: 18                // E, Lucide glyph inside a disc
    readonly property real ccToggleIconSize: 22          // E, glyph inside a round toggle
    readonly property real ccNowPlayingRadius: 22        // E, rounded rect, not a pill
    readonly property real ccArtInset: 14                // E
    readonly property real ccArtSize: 40                 // E
    readonly property real ccArtRadius: 10               // E
    readonly property real ccNowPlayingTitleY: 74        // E, title top inside the tile
    readonly property real ccTransportY: 112             // E, transport row centre
    readonly property real ccTransportSpacing: 37        // E, prev and next centre offset from middle
    readonly property real ccTransportHit: 28            // E, square hit area around each transport glyph
    readonly property real ccTransportSize: 16           // E, prev / next glyph (capture: about 11 pt tall)
    readonly property real ccPlaySize: 20                // E, play / pause glyph (capture: about 18 pt)
    readonly property real ccSliderTitleY: 10            // E, slider title top
    readonly property real ccSliderPadX: 16              // E, slider title left
    readonly property real ccSliderRowCentre: 41         // E, slider track centre from the module top
    readonly property real ccSliderIconSize: 14          // E, sun / volume glyphs
    readonly property real ccSliderIconX: 21             // E, left glyph centre
    readonly property real ccSliderIconRightX: 270       // E, right glyph centre
    readonly property real ccSliderTrackStart: 34        // E, track left
    readonly property real ccSliderTrackEnd: 258         // E, track right (before the right glyph)
    readonly property real ccTrackRadius: 2              // E, half of ccSliderTrack
    readonly property color ccTitleColor: "#FFFFFF"      // M, white on the glass
    readonly property color ccActiveFill: accentBlue     // M, Tahoe's active colour is systemBlue (20 Oct owner direction, was Theme.primary)
    readonly property real ccActiveAlpha: 0.62           // E, blue-tinted glass body for an active tile (not a solid fill)
    readonly property color ccActiveText: accentOn       // E, text and glyphs ON the accent fill: white (20 Oct owner direction)
    readonly property real ccActiveSubtitleAlpha: 0.75   // E, subtitle on the accent fill
    readonly property color ccActiveGlyph: accentBlue    // E, active glyph on the white disc: #0a84ff (owner 20 Oct)
    readonly property color ccDiscFill: Qt.rgba(1, 1, 1, 0.96)  // E, active disc: white (Tahoe), glyph in accentBlue
    readonly property color ccDiscIdleFill: Qt.rgba(1, 1, 1, 0.22)   // E
    readonly property color ccIconIdle: "#FFFFFF"        // E, glyph on an idle module
    readonly property color ccTrackFill: "#FFFFFF"       // M, solid white level
    readonly property color ccTrackIdle: Qt.rgba(1, 1, 1, 0.28)      // E, unfilled track
    readonly property color ccEditBorder: Qt.rgba(1, 1, 1, 0.4)      // E
    readonly property real ccDisabledAlpha: 0.42         // E, unavailable module (ControlTile value)

    // ---- Quick Look (space on a file in Thunar; mac/MacQuickLook.qml) ----
    // Own values, not Apple-measured: a centred ink window, sized for reading.
    readonly property real quickLookWidth: 760           // E, centred preview window
    readonly property real quickLookHeight: 560          // E, header plus body
    readonly property real quickLookRadius: 26           // E, same family as Spotlight
    readonly property real quickLookHeaderHeight: 44     // E, file name row
    readonly property real quickLookPad: 16              // E, body inset
    readonly property real quickLookTitleSize: 13        // E, semibold file name
    readonly property real quickLookMetaSize: 12         // E, size, date, kind rows
    readonly property real quickLookIconSize: 120        // E, big icon for files with no preview

    // ---- 3.5 Spotlight ---------------------------------------------------
    // Re-measured 20 Oct from tahoe-spotlight-search.png (2x, 2880x1800):
    // panel x 800..2080 px (640 pt, kept at 639), search rule and chips span
    // x 840..2040 px = 600 pt, so the search field is 600 wide with a 20 pt
    // inset (the old 620 E did not fit a 639 panel with that inset).
    readonly property real spotlightWidth: 639           // M, centred (800..2080 px)
    readonly property real spotlightHeight: 466          // M (top 360 px, bottom 1292 px)
    readonly property real spotlightTop: 180             // M
    readonly property real spotlightRadius: 26           // E
    readonly property real spotlightInset: 20            // M, content inset each side (840 px - 800 px, 2x)
    readonly property real spotlightSearchWidth: 600     // M, re-measured: 840..2040 px = 600 pt (was 620 E)
    readonly property real spotlightSearchHeight: 40     // E, row centre at 27.5 pt from panel top (M)
    readonly property real spotlightSeparatorY: 56       // M, hairline under the search row (472 px)
    readonly property real spotlightChipTop: 67          // M, chips top 494 px from panel top 360 px
    readonly property real spotlightChipWidth: 141       // M, (600 - 3 x 12) / 4; MacSpotlightPanel derives the same value
    readonly property real spotlightChipHeight: 24       // M, 48 px at 2x
    readonly property real spotlightChipGap: 12          // M, 24 px at 2x between chips
    readonly property real spotlightChipRadius: 12       // M, full pill (half the height)
    readonly property real spotlightChipTextSize: 13     // E
    readonly property real spotlightListInset: 10        // M, row highlight 820..2060 px
    readonly property real spotlightRowHeight: 55        // M, highlight 566..677 px at 2x
    readonly property real spotlightRowGap: 3            // M, title pitch 58 pt vs row 55
    readonly property real spotlightRowRadius: 10        // E, rounded row highlight
    readonly property real spotlightIconSize: 32         // M, app thumbnail 65 px at 2x
    readonly property real spotlightIconGap: 18          // M, icon right edge to text (38 px at 2x)
    readonly property real spotlightQuerySize: 24        // M-ish: "Beach" advance width 69 pt, 22-24 range
    readonly property real spotlightMagnifierSize: 24    // M, 48 px at 2x
    readonly property real spotlightTitleSize: 16        // E, round 2: ref title runs about 1.2x our 15 pt render
    readonly property real spotlightSubtitleSize: 13     // E, round 2: ref subtitle runs about 1.2x our 12 pt render
    readonly property color spotlightPanelSample: "#84A7C0"   // M, translucent over wallpaper: reference only
    readonly property color spotlightSearchSample: "#C2EAF1"  // M, light tint: reference only
    readonly property int spotlightMotionMs: 220         // E
    readonly property real spotlightMotionFromScale: 0.97 // E
    readonly property real spotlightTintAlpha: 0.62      // E, light frosted panel body (reference #84A7C0-ish, brighter than the banners)

    // ---- 3.6 call banner (Apple render, A: proportions only) ------------
    // The render card is square, about 708 x 708 px in the 2048 px render (scale unknown).
    // Every ratio below is measured on the render and applied to callWidth.
    readonly property real callWidth: 343                // E, same width as the banners (scale not known)
    readonly property real callBannerHeight: 72          // E, same height as a banner: one row (avatar, name, buttons)
    readonly property real callRadius: 16                // E, banner radius (compact card)
    readonly property real callPadding: 14               // E, banner pad
    readonly property real callAvatarSize: 40            // E, avatar circle with the initial
    readonly property real callButtonDiameter: 40        // E, compact row button (was a square-card ratio)
    readonly property real callButtonGap: 8              // E, between the two buttons
    readonly property real callNameSize: 14              // E, semibold
    readonly property real callSubtitleSize: 12          // E
    readonly property real callSubtitleAlpha: 0.6        // E (A), secondary text
    readonly property int callSlideMs: 300               // E, same slide as banners
    // Call colours are Apple's systemRed and systemGreen (20 Oct owner direction).
    // Glyphs are white. The render's grey Reply / More buttons have no backend.

    // ---- 4 material (glass) ----------------------------------------------
    // Body and rim come from components/TahoeGlass.qml. The white body tint
    // is the surface alpha. Blur comes from the compositor (hypr glass.lua,
    // ignore_alpha must stay BELOW surfaceTintAlpha or the blur never applies).
    // Shadow, rim and glow reuse the dock's owner-approved Tahoe 1x values.
    readonly property real surfaceTintAlpha: compositorGlass ? 0.2 : 0.12        // E, white body alpha (dock value)
    readonly property real surfaceRimTop: 0.55           // E, specular rim, top edge
    readonly property real surfaceRimSide: 0.15          // E, sides and bottom
    readonly property real surfaceInnerGlow: 0.08        // E, 6 px falloff
    readonly property real surfaceShadowAlpha: 0.16      // E, black drop shadow peak
    readonly property real surfaceShadowBlur: 20         // E, falloff px
    readonly property real surfaceShadowY: 4             // E, offset px down

    // ---- added for the banner stack and Notification Center (mac-nc) -----
    // Every value below is E unless marked M. Keep this block small.
    readonly property real bannerIconSize: 30            // E, app icon (Tahoe 2x crop ~60 px)
    readonly property real bannerPad: 14                 // E, inner padding, banners and NC cards
    readonly property real bannerTextGap: 1              // E, title to body
    readonly property real bannerTimeSize: 11            // E, relative time
    readonly property real bannerStackGap: 10            // owner spec (20 Oct): 10 pt between stacked banners
    readonly property int bannerMaxVisible: 3            // stack shows 3; the rest wait behind a "+N" chip
    readonly property real ncExpandedGap: 8              // owner spec: 8 pt between expanded cards in a group
    readonly property real ncPeekStep: 6                 // owner spec (21 Oct): each back layer of a collapsed stack shows 6 pt below the one in front
    readonly property real ncPeekInset1: 10              // owner spec: first back layer inset 10 pt per side
    readonly property real ncPeekInset2: 20              // owner spec: second back layer inset 20 pt per side
    readonly property color ncPeekFill: ink ? Theme.inkRaised : Qt.rgba(1, 1, 1, 0.3)  // owner spec: first back layer (inkRaised); light glass edge otherwise
    readonly property color ncPeekFillBack: "#0b0b0c"    // owner spec (21 Oct): second back layer, darker than inkRaised
    readonly property real ncBottomPad: 16               // owner spec (20 Oct): bottom padding of the NC column
    readonly property real ncInsetRight: 12              // owner spec (21 Oct): NC column distance from the screen's right edge
    readonly property real ncHoverRoom: 12               // room left of the cards so a card's hover close button is not clipped
    readonly property real bannerSwipeFraction: 0.35     // E, share of the width to swipe away
    readonly property int bannerTimeoutTick: 100         // ms, countdown step (pauses on hover)
    // ---- screenshot thumbnail (MacShotThumbnail, bottom right) ---------
    readonly property real shotWidth: 160                // E, macOS floating thumbnail width
    readonly property real shotRadius: 16                // E, card corner (continuous)
    readonly property real shotInset: 4                  // E, ink rim between card edge and picture
    readonly property real shotInsetRight: 17           // E, same right edge as the banners
    readonly property real shotInsetBottom: 24           // E, clears the dock on the bottom edge
    readonly property int shotLifetimeMs: 5000           // E, about 5 s like macOS
    readonly property int shotMaxPending: 8              // queued captures beyond the one on screen
    readonly property int shotFadeMs: 220                // E, fade in on each new capture
    // Ink (owner, 21 Oct): every Tahoe surface is opaque ink like the island, because
    // light glass over a dark wallpaper made banners and NC cards unreadable.
    // false brings back the frosted white glass with dark labels.
    readonly property bool ink: true
    // A neutral at `a` that reads on the current surface: white on ink, black on glass.
    function onSurface(a: real): color {
        return ink ? Qt.rgba(1, 1, 1, a) : Qt.rgba(0, 0, 0, a)
    }
    readonly property color labelPrimary: ink ? Theme.t1 : Qt.rgba(0, 0, 0, 0.9)    // E, on light glass
    readonly property color labelSecondary: ink ? Theme.t2 : Qt.rgba(0, 0, 0, 0.55)  // E, on light glass
    readonly property color onGlassPrimary: "#FFFFFF"              // M (reference text on wallpaper / blue glass)
    readonly property color onGlassSecondary: Qt.rgba(1, 1, 1, 0.7) // E
    // Group headers and widget captions sit on the wallpaper: white 85%, with a
    // 1 pt shadow. A blurred shadow would paint alpha past the mac surface's
    // ignore_alpha (0.06, glass.lua) and frost halos around the text, so none.
    readonly property color onGlassHeader: Qt.rgba(1, 1, 1, 0.85)  // E, macOS group caption
    readonly property color onGlassShadow: Qt.rgba(0, 0, 0, 0.35)  // E, 0 1px 2px, drawn as a 1 pt hard offset
    // Ink pills (Clear All, group Clear / Show less, Show N more): inkRaised2 fill, t2 text.
    readonly property color ncPillFill: ink ? Theme.inkRaised2 : Qt.rgba(1, 1, 1, 0.25)     // owner spec (21 Oct): ink pill fill
    readonly property real ncPillHeight: 22              // owner spec (21 Oct): group pills are 22 pt tall, radius 11
    readonly property real ncPillPadX: 10                // owner spec (21 Oct): pill horizontal padding
    readonly property real ncPillTextSize: 12            // owner spec (21 Oct): group pill text
    readonly property real ncPillGap: 6                  // E, between two pills in a row
    readonly property real ncGroupPillInset: 8           // E, top of the group pill row inside the top card
    readonly property real ncClearAllHeight: 22          // owner spec (21 Oct): column Clear All pill
    readonly property real ncCloseGlyphSize: 15          // E, the x on a banner
    readonly property real ncClearAllTextSize: 11        // owner spec (21 Oct): column Clear All text
    readonly property real ncClearAllGap: 8              // E, Clear All row to the first group
    readonly property real ncShowMoreHeight: 24          // owner spec (21 Oct): "Show N more" pill, centred
    readonly property real ncShowMoreTextSize: 12        // owner spec (21 Oct): "Show N more" text
    // Notification action buttons (iPhone ANCS Accept/Decline, app actions) on banners and cards.
    readonly property real notifActionHeight: 22         // E, pill height
    readonly property real notifActionPadX: 10           // E, pill inner horizontal padding
    readonly property real notifActionGap: 6             // E, between buttons
    readonly property real notifActionTextSize: 12       // E, semibold label
    readonly property color notifActionFill: Qt.rgba(1, 1, 1, 0.16)   // E, ink-surface button body
    readonly property color notifActionPressed: Qt.rgba(1, 1, 1, 0.3) // E, while pressed

    readonly property real ncTopInset: 12                // owner spec (21 Oct): NC column 12 pt from the top
    readonly property real ncFillAlpha: 0.97             // E, flat widget fills read near-opaque in the reference
    readonly property real ncWeatherCitySize: 17         // E, semibold
    readonly property real ncWeatherTempSize: 46         // E, regular (reference cap height ~30 pt)
    readonly property real ncWeatherTopPad: 19           // M, city cap top ~19 pt below the widget top
    readonly property real ncWeatherConditionSize: 13    // E
    readonly property real ncWeatherIconSize: 20         // E, glyph
    readonly property real ncHourlyTimeSize: 11          // E, semibold
    readonly property real ncHourlyTempSize: 13          // E, semibold
    readonly property real ncHourlyIconSize: 18          // E, glyph (reference ~18 pt)
    readonly property real ncListLeftWidth: 108          // M, reference rows start ~122 pt into the widget
    readonly property real ncListIconSize: 34            // E
    readonly property real ncListCountSize: 34           // E, bold count; crop 02 "13" cap height ~23 pt (was 28)
    readonly property real ncListRowSize: 13             // E
    readonly property real ncListRowPitch: 38            // M, reference rows 76 px apart at 2x
    readonly property real ncListRadio: 22               // M, empty radio ring ~44 px at 2x
    readonly property real ncCompactHeight: 63           // M, the Control Center tile height
    readonly property real ncMediaHeight: 76             // owner spec (21 Oct): compact Now Playing widget
    readonly property real ncMediaPad: 12                // owner spec: Now Playing padding
    readonly property real ncMediaGap: 12                // E, artwork to text, text to controls
    readonly property real ncArtSize: 52                 // owner spec: artwork square
    readonly property real ncArtRadius: 10               // owner spec: artwork corner radius
    readonly property real ncMediaArtistSize: 12         // owner spec: artist line
    readonly property real ncMediaGlyphSize: 18          // E
    readonly property real ncMediaButtonSize: 30         // E
    readonly property real ncGroupLabelSize: 12          // E, app group caption
    readonly property real ncWidgetTitleSize: 13         // E, widget title (semibold)
    // Notification card (owner spec 21 Oct). Card width is ncColumnWidth, the same as widgets.
    readonly property real ncCardRadius: 18              // owner spec: squircle corner radius
    readonly property real ncCardMinHeight: 64           // owner spec: a one-line card is at least this tall
    readonly property real ncCardPadX: 14                // owner spec: horizontal padding
    readonly property real ncCardPadY: 12                // owner spec: vertical padding
    readonly property real ncCardIconSize: 32            // owner spec: app icon
    readonly property real ncCardIconRadius: 8           // owner spec: rounded corners on an image icon
    readonly property real ncCardIconGap: 12             // owner spec: icon to text
    readonly property color ncCardIconFill: Theme.inkRaised2  // owner spec: letter fallback circle (not bright blue)
    readonly property real ncCardTitleSize: 13           // owner spec: title, DemiBold, one line
    readonly property real ncCardBodySize: 13            // owner spec: body, Regular
    readonly property int ncCardBodyLines: 4             // owner spec: body wraps to up to 4 lines
    readonly property real ncCardTextGap: 2              // E, title to body
    readonly property real ncCardTimeGap: 8              // E, title to the relative time on its right
    readonly property real ncCardTimeSize: 11            // owner spec: relative time inside the card, top right
    readonly property real ncCardActionRow: 28           // E, reserved row under the text when a card has actions besides "default"
    readonly property real ncCardCloseSize: 18           // owner spec: hover close circle diameter
    readonly property real ncCardCloseOffset: -6         // owner spec: close circle top-left at (-6, -6) of the card
    readonly property real ncCardCloseGlyph: 11          // owner spec: the x inside the close circle
    readonly property color ncCardCloseBorder: Theme.inkRim  // E, hairline ring of the close circle
    readonly property int ncSlideMs: 300                 // E, NC column slide in and out
    // ---- light glass (mac-style fixes, 20 Oct) ----------------------
    readonly property real frostTintAlpha: compositorGlass ? 0.22 : 0.5           // E, white body tint for light glass: banners, NC cards, Spotlight
    // E, light widget body for the list, Now Playing and battery widgets. Reference crop 02 reads as
    // near-white (calendar fill #F4F4F4), so the alpha is high. Banners and cards keep frostTintAlpha.
    readonly property color ncWidgetFrost: Qt.rgba(0.97, 0.97, 0.98, 0.8)
    readonly property color ncWeatherFrost: Qt.rgba(0.37, 0.51, 0.69, 0.8)  // E, blue frosted weather (reference body samples #5E82B1)
    readonly property color ccModuleFill: Qt.rgba(0.05, 0.20, 0.40, 0.58)   // E, module body tint; 0.58 so white labels (Display, Sound) read on light wallpaper
}
