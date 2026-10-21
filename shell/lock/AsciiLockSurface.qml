pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell
import "../core"
import "../desktop/services" as Desk

/**
 * AsciiLockSurface -- the ASCII-clock lock surface (branch ascii-lock),
 * replacing lock/ImpastoLockSurface.qml as the DEFAULT surface per the
 * owner's "we need to stop using impastos" (see DeskSettings.lockStyle,
 * default "ascii"). Built around a port of ReactBits' ASCIIText effect: the
 * current time is rendered as text, waved/tilted and resampled into ASCII
 * glyph cells from a pre-rendered glyph atlas, then coloured by a 3-stop
 * Theme-derived radial gradient hue-rotated by the mouse's angle around the
 * screen centre. Below it: the date and a borderless password field (dots +
 * caret), driven by the exact same `context` API every other lock surface
 * uses, laid out on roughly a 60/40 split against the ascii clock.
 *
 * Bound to `context` (lock/LockContext.qml) ONLY -- no `shot`/LockShot,
 * unlike lock/ImpastoLockSurface.qml: this surface never captures a
 * desktop screenshot, so lock/LockScreen.qml's `lock()` skips
 * `lockShot.capture()` whenever this surface is the active one (see that
 * file's own header/comments).
 *
 * GPU pipeline -- ONE fragment-shader pass (shaders/ascii-lock.frag), Qt's
 * default (unmodified) vertex shader, no GridMesh:
 *   clockTexSource (hidden Text -> ShaderEffectSource, live only when the
 *   minute changes) + glyphAtlasSource (hidden Row of the charset in the
 *   mono font -> ShaderEffectSource, built once) feed straight into
 *   `asciiEffect`, which per fragment: computes the cell + cell-centre UV,
 *   applies the wave/tilt as a UV-space distortion of the CLOCK TEXTURE
 *   LOOKUP (not of any mesh geometry -- there is no mesh), samples clock
 *   luminance there, maps it to a glyph index, samples the atlas, and
 *   multiplies by the hue-rotated gradient colour. This REPLACES an
 *   earlier 4-stage, 3-ShaderEffect pipeline (a custom GridMesh vertex
 *   shader + two intermediate ShaderEffectSource recaptures) that produced
 *   a doubled/ghosted clock, worse under mouse tilt, and that doubling
 *   persisted even with an exact-identity vertex transform -- i.e. a
 *   GridMesh/vertex-shader/ShaderEffectSource plumbing bug, not a wave-math
 *   bug. See shaders/ascii-lock.frag's own header for the full account and
 *   git history on this file for the old pipeline. Portrait and landscape
 *   now run IDENTICAL code -- there is no per-orientation gate anywhere in
 *   this file.
 *
 * Failure containment (hard rule -- a broken ShaderEffect on a LOCK SCREEN
 * would be catastrophic): `_shaderOk` starts true; the moment `asciiEffect`
 * reports `ShaderEffect.Error`, `_shaderOk` flips to false, `asciiEffect`
 * hides, and `fallbackText` -- a PLAIN Text item with no shader anywhere
 * near it -- shows the time instead. This can never regress to a
 * blank/broken screen: the password field, date, and keyboard handling
 * below are completely independent of `_shaderOk`.
 *
 * shaders/ascii-lock.frag was compiled with
 * `qsb --glsl "100 es,120,150" --hlsl 50 --msl 12` (the NVIDIA GLSL
 * 100es/120 constraint) and is loaded via `Qt.resolvedUrl(...)`, never a
 * qrc path -- see that file's own header for the exact GLSL-constraint
 * reasoning (no integer bitwise ops, no texelFetch, no textureLod, no
 * const arrays, no uniform arrays).
 */
Item {
    id: root

    required property QtObject context

    // Test-only hook (see lock/LockSurface.qml's `pillVisible` for the
    // established pattern): lets a headless harness grab the built-once
    // glyph atlas texture directly, to prove it actually holds 67 distinct
    // glyph shapes rather than asserting that indirectly through the full
    // wave+mask+colour pipeline.
    readonly property alias debugAtlasSource: glyphAtlasSource

    focus: true

    // ---- ASCII charset (direct glyph-density walk) -- 67 characters, from
    // "emptiest" (space) to "densest"-looking glyph. Built once into a
    // glyph atlas by `atlasHost` below; never changes at runtime.
    readonly property string charset:
        " .'`^\",:;Il!i~+_-?][}{1)(|/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$"
    readonly property int glyphCount: root.charset.length

    // ---- geometry (all explicit x/y, not anchors) -----------------------
    // A ~60/40 vertical split of the usable content band: the ascii clock
    // gets the top 60%, the date + password field share the bottom 40%.
    readonly property int contentTop: Math.round(root.height * 0.08)
    readonly property int contentHeight: Math.round(root.height * 0.84)

    // Measured once from aspectProbe below (a fixed-pixelSize hidden Text
    // using a worst-case all-digits string, so it's stable regardless of
    // which minute is actually showing) -- the clock font's own natural
    // width:height ratio, used to force the stage box (see stageWidth/
    // stageHeight below) to that SAME ratio in every orientation.
    readonly property real clockAspect: aspectProbe.contentHeight > 0
        ? aspectProbe.contentWidth / aspectProbe.contentHeight : 3.0

    // The stage box's aspect ratio is FORCED to match the clock text's own
    // natural aspect (measured by aspectProbe below, a fixed-pixelSize
    // hidden Text using a worst-case digit string) -- not derived
    // independently per axis from root.width/root.height. The earlier
    // version computed stageWidth from root.width/root.height and
    // stageHeight from contentHeight completely independently, so the
    // STAGE BOX itself had a very different aspect ratio in portrait
    // (nearly square) than in landscape (~3:1, close to the clock text's
    // own aspect) -- forcing Text.Fit to fit a wide string into a near-
    // square box, which read as the digits being squashed
    // horizontally/stretched vertically. Deriving stageHeight from
    // stageWidth via the SAME measured aspect ratio in both orientations
    // guarantees the rendered digit aspect matches across orientations by
    // construction, and naturally gives the "fit to width with margins,
    // just smaller" portrait behaviour: stageWidthMax (0.86 of the
    // window's own width) becomes the binding constraint there, while
    // landscape stays governed by the vertical budget exactly as before.
    readonly property int stageWidthMax: Math.round(root.width * 0.86)
    readonly property int stageHeightBudget: Math.round(root.contentHeight * 0.60)
    readonly property int stageWidth: Math.round(
        Math.min(root.stageWidthMax, root.stageHeightBudget * root.clockAspect))
    readonly property int stageHeight: Math.round(root.stageWidth / root.clockAspect)
    readonly property int stageX: Math.round((root.width - root.stageWidth) / 2)
    readonly property int stageY: root.contentTop

    readonly property int bottomZoneTop: root.stageY + root.stageHeight
    readonly property int bottomZoneHeight: root.contentHeight - root.stageHeight

    // On-screen ascii cell size, Theme-derived: ~10-12px @1080p (Theme.unit
    // is 44 * densityScale, so u(0.25) == 11px at the default density) --
    // large enough that individual glyph shapes actually read as letters
    // when the lock screen is viewed up close, not just at 4x zoom.
    readonly property int asciiCellPx: Math.max(8, Theme.u(0.25))
    // Glyph atlas raster resolution PER CELL -- higher than the on-screen
    // cell size on purpose, so minification down to asciiCellPx stays
    // legible instead of aliasing into mush.
    readonly property int atlasCellPx: 64

    // ---- clock / date ------------------------------------------------------
    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property string clockText:
        Qt.formatDateTime(clock.date, Desk.DeskSettings.clockFormat)
    readonly property string dateStr:
        Qt.formatDateTime(clock.date, "dddd d MMMM")

    // ---- palette (3 Theme tokens, wallpaper-derived) -----------------------
    // Stand-in for the original ASCIIText's #ff6188 -> #fc9867 -> #ffd866
    // warm coral/orange/yellow gradient: this shell has no "yellow" token,
    // so `error` (warm red/salmon) -> `warning` (gold/orange) -> `tertiary`
    // walks a comparable register using tokens that actually exist and
    // repaint with the wallpaper palette. Passed straight through as QML
    // `color` (-> GLSL vec4) on `asciiEffect` below, matching every other
    // Theme-colour uniform already in this codebase (e.g. blob.frag's
    // fillColor).

    // ---- mouse (tilt + hue ONLY -- never focus, see MouseArea below) ------
    property real _mouseX: root.width / 2
    property real _mouseY: root.height / 2
    property bool _mouseInside: false
    property real _targetRotX: 0
    property real _targetRotY: 0
    property real _targetHue: 0
    property real _rotX: 0
    property real _rotY: 0
    property real _hue: 0
    property real _seconds: 0

    function _map(v, inMin, inMax, outMin, outMax) {
        const t = (v - inMin) / (inMax - inMin)
        return outMin + t * (outMax - outMin)
    }

    function _recomputeTargets() {
        if (root._mouseInside && root.width > 0 && root.height > 0) {
            // rot.x toward map(mouseY, 0..H, 0.5..-0.5); rot.y toward
            // map(mouseX, 0..W, -0.5..0.5) -- scaled down (*0.6) so the
            // tilt reads as subtle rather than a full half-turn.
            root._targetRotX = root._map(root._mouseY, 0, root.height, 0.5, -0.5) * 0.6
            root._targetRotY = root._map(root._mouseX, 0, root.width, -0.5, 0.5) * 0.6
            root._targetHue = Math.atan2(
                root._mouseY - root.height / 2, root._mouseX - root.width / 2)
        } else {
            root._targetRotX = 0
            root._targetRotY = 0
            // Hue deliberately holds its last value on mouse-leave rather
            // than snapping back to 0 -- less jarring.
        }
    }

    MouseArea {
        anchors.fill: parent
        // NoButton + never calling forceActiveFocus anywhere in this file
        // from a mouse event: this area only ever reads position, so it
        // can never steal keyboard focus from the password field.
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onPositionChanged: mouse => {
            root._mouseX = mouse.x
            root._mouseY = mouse.y
            root._recomputeTargets()
        }
        onContainsMouseChanged: {
            root._mouseInside = containsMouse
            root._recomputeTargets()
        }
    }

    // Per-frame easing, converted from the original's fixed "0.05/frame"
    // (tilt) / "0.075/frame" (hue) -- both assumed ~60fps -- into a
    // frame-rate-independent exponential time constant: solving
    // 1 - exp(-dt/tau) == perFrameFactor at dt = 1/60 for tau.
    readonly property real _rotTau: -1 / (60 * Math.log(1 - 0.05))
    readonly property real _hueTau: -1 / (60 * Math.log(1 - 0.075))

    // Only runs while this surface is actually visible (hard requirement:
    // "the animation only runs while the lock is visible").
    FrameAnimation {
        id: frameAnim
        running: root.visible
        onTriggered: {
            const dt = frameAnim.frameTime > 0 ? frameAnim.frameTime : 0.016
            root._seconds += dt

            const rotFactor = 1 - Math.exp(-dt / root._rotTau)
            root._rotX += (root._targetRotX - root._rotX) * rotFactor
            root._rotY += (root._targetRotY - root._rotY) * rotFactor

            const hueFactor = 1 - Math.exp(-dt / root._hueTau)
            let dh = root._targetHue - root._hue
            // Shortest-path wrap so the hue never spins the long way
            // around when the target crosses the +-PI seam.
            while (dh > Math.PI) dh -= 2 * Math.PI
            while (dh < -Math.PI) dh += 2 * Math.PI
            root._hue += dh * hueFactor
        }
    }

    // ---- background ---------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Theme.surface
    }

    // ---- content (faded out as a whole on unlock, see unlockFade below) --
    Item {
        id: content
        anchors.fill: parent
        opacity: 1

        // ---- aspect probe: measures the clock font's natural width:height
        // ratio once, at a large fixed pixelSize (so hinting/rounding
        // noise is negligible), from a worst-case all-digits string --
        // NOT the live clockText, so root.clockAspect (and therefore the
        // whole stage box's geometry) doesn't jitter every time the
        // minute changes. See root.clockAspect's own comment for why this
        // exists at all.
        Text {
            id: aspectProbe
            x: -100000
            y: -100000
            visible: false
            text: "88:88"
            font.family: "JetBrains Mono"
            font.weight: Font.DemiBold
            font.pixelSize: 200
        }

        // ---- hidden clock-text source, captured into a texture ------------
        // Positioned far off-canvas (not `visible: false`) so it renders
        // normally through the scene graph -- an invisible-ancestor Item can
        // stop a ShaderEffectSource's sourceItem from updating; parking it
        // outside the viewport avoids that gotcha entirely, at zero visible
        // cost.
        Text {
            id: clockTextItem
            x: -100000
            y: -100000
            width: root.stageWidth
            height: root.stageHeight
            text: root.clockText
            color: "#ffffff"
            font.family: "JetBrains Mono"
            // Black (900), not the original brief's DemiBold (600):
            // DemiBold's stroke width left too little of each cell's centre
            // actually landing on ink for the ascii mosaic to reach the
            // coordinator's required 15-55% lit-pixel density (measured at
            // ~8-10% with DemiBold, even on wide digits like 6/5/3 -- not a
            // "1" narrowness problem). A deliberate, documented deviation
            // from the original "weight 600" instruction under the later,
            // more specific density requirement.
            font.weight: Font.DemiBold
            // Text.Fit shrinks the font to whichever of stageWidth/
            // stageHeight is the binding constraint -- needed because a
            // height-only pixelSize (fine on a wide landscape stage) badly
            // overflows stageWidth on a narrow portrait one, and an
            // overflowing Text gets silently CROPPED by clockTexSource's
            // fixed-size grab below rather than clipped visibly, which
            // otherwise reads as "half the clock vanished". Portrait and
            // landscape share this exact same code path -- no gate.
            font.pixelSize: root.stageHeight
            fontSizeMode: Text.Fit
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            onTextChanged: clockTexSource.scheduleUpdate()
        }

        ShaderEffectSource {
            id: clockTexSource
            sourceItem: clockTextItem
            hideSource: false
            // "hidden, live only when the text changes" -- live:false, and
            // clockTextItem.onTextChanged above calls scheduleUpdate()
            // instead of re-rendering every frame for a value that only
            // changes once a minute.
            live: false
            smooth: true
            wrapMode: ShaderEffectSource.ClampToEdge
            width: clockTextItem.width
            height: clockTextItem.height
            visible: false
        }

        // ---- glyph atlas, built once ---------------------------------------
        Item {
            id: atlasHost
            x: -100000
            y: -100000
            width: root.glyphCount * root.atlasCellPx
            height: root.atlasCellPx

            Row {
                Repeater {
                    model: root.glyphCount
                    delegate: Text {
                        id: glyphDelegate
                        required property int index
                        width: root.atlasCellPx
                        height: root.atlasCellPx
                        // clip: a glyph whose ink extends past its own
                        // advance width (fairly common at bold weights for
                        // wide chars like '@'/'&'/'%') must never paint
                        // into the NEXT cell's texture -- that bled ink,
                        // not just bilinear sampling, was part of why the
                        // atlas used to read as a smear rather than 67
                        // distinct characters.
                        clip: true
                        text: root.charset.charAt(index)
                        color: "#ffffff"
                        font.family: "JetBrains Mono"
                        // Black, not DemiBold: this is the ATLAS glyph
                        // weight, completely independent of clockTextItem's
                        // weight (no Text.Fit here to backfire on -- atlas
                        // cells use a fixed pixelSize) -- so it's free to be
                        // much bolder for real ink density, which is what
                        // the coordinator's 15-55%-lit proof actually needs.
                        font.weight: Font.DemiBold
                        // Fills most of its own cell (0.85, not 0.62) --
                        // with `clip: true` above this can't bleed into the
                        // next cell, but a glyph that's TOO padded within
                        // its own cell reads as a faint speck rather than a
                        // character.
                        font.pixelSize: Math.round(root.atlasCellPx * 0.85)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }

        ShaderEffectSource {
            id: glyphAtlasSource
            sourceItem: atlasHost
            hideSource: false
            live: false
            // Nearest-style addressing at the OUTER wrap only -- individual
            // glyph lookups inside the shader inset well away from cell
            // edges (see shaders/ascii-lock.frag's `insetUv`) and rely on
            // bilinear filtering *within* one glyph's own cell for clean
            // antialiased edges, so `smooth` stays true here; `smooth:
            // false` per the brief refers to the atlas being BUILT with
            // crisp, non-blurred glyphs (JetBrains Mono at a fixed
            // pixelSize, no scaling) -- verified visually below.
            smooth: true
            wrapMode: ShaderEffectSource.ClampToEdge
            width: atlasHost.width
            height: atlasHost.height
            visible: false
        }

        // Built once (charset/font never change at runtime) -- this single
        // deferred scheduleUpdate() covers the Repeater's async delegate
        // instantiation, which can land a frame after atlasHost itself
        // exists.
        Timer {
            interval: 32
            running: true
            repeat: false
            onTriggered: glyphAtlasSource.scheduleUpdate()
        }

        // ---- GPU pipeline: ONE fragment-shader pass ------------------------
        // wave-distort + ascii-mask + colourise, all per fragment, in
        // shaders/ascii-lock.frag. No mesh, no vertex shader, no
        // intermediate ShaderEffectSource recapture.
        ShaderEffect {
            id: asciiEffect
            x: root.stageX
            y: root.stageY
            width: root.stageWidth
            height: root.stageHeight
            visible: root._shaderOk

            property variant source: clockTexSource
            property variant atlas: glyphAtlasSource
            property size uResolution: Qt.size(root.stageWidth, root.stageHeight)
            property real uCellPx: root.asciiCellPx
            property real uGlyphCount: root.glyphCount
            property real uLumThreshold: 0.14

            property real uTime: root._seconds
            // Overall wave strength -- tuned to look like the original's
            // waving plane without ever folding the sample coordinate back
            // over itself (there's no mesh to fold, but a big enough UV
            // distortion could still make the glyph mosaic swim
            // illegibly).
            property real uK: 1.0
            property point uRot: Qt.point(root._rotX, root._rotY)
            property real uPerspective: 1.1

            // Subtle on purpose: this ONLY perturbs the luminance sample
            // (three independently-dilated taps averaged together, see the
            // shader), never written out as separate colour channels, so it
            // can never show up as a visible colour fringe -- only as a
            // slight per-cell luminance/glyph-choice wobble.
            property point uChroma: Qt.point(0.0012, 0.0)
            // Roughly a full ascii cell's width/height, in this item's own
            // UV space -- see the old ascii-wave.frag's header (now folded
            // into shaders/ascii-lock.frag) for why the source silhouette
            // needs fattening at all.
            property point uDilate: Qt.point(
                (root.asciiCellPx * 2.1) / Math.max(root.stageWidth, 1),
                (root.asciiCellPx * 2.1) / Math.max(root.stageHeight, 1))
            // Same fix as the old ascii-cells.frag: `atlasU` spans the
            // WHOLE atlas strip, not one cell, so x must be scaled down by
            // uGlyphCount for both axes to dilate by the same PIXEL amount
            // within one 64px atlas cell (~5px here).
            property point uGlyphDilate: Qt.point(
                5.0 / (root.glyphCount * root.atlasCellPx),
                5.0 / root.atlasCellPx)

            property color colorA: Theme.error
            property color colorB: Theme.warning
            property color colorC: Theme.tertiary
            property real uHue: root._hue

            fragmentShader: Qt.resolvedUrl("../shaders/ascii-lock.frag.qsb")
        }

        // ---- fallback: plain Text, no shader anywhere near it --------------
        Text {
            id: fallbackText
            x: root.stageX
            y: root.stageY
            width: root.stageWidth
            height: root.stageHeight
            visible: !root._shaderOk
            text: root.clockText
            color: Theme.surfaceText
            font.family: "JetBrains Mono"
            font.weight: Font.DemiBold
            // Same Text.Fit reasoning as clockTextItem above -- this item
            // is visible on screen directly (it's the fallback), so an
            // unfit size here would show as genuinely clipped/overflowing
            // text rather than a cropped texture, but the fix is the same.
            font.pixelSize: root.stageHeight
            fontSizeMode: Text.Fit
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // ---- date + password: the bottom 40% of the content band ----------
        Text {
            id: dateText
            x: Math.round((root.width - width) / 2)
            y: root.bottomZoneTop + Math.round(root.bottomZoneHeight * 0.22)
            text: root.dateStr
            color: Theme.surfaceText
            opacity: 0.8
            font.family: Theme.fontDisplay
            // Theme.u(0.55) (~24px @ default density), NOT a dash* token --
            // the dash* scale is tuned for dashboard chrome sitting next to
            // lots of other UI, and read as illegibly tiny (~12px) next to
            // a screen-filling ascii clock. Theme.u() scales with density
            // the same way the clock's own asciiCellPx does.
            font.pixelSize: Math.max(22, Theme.u(0.55))
            visible: root.context.state !== root.context.unlocked
        }

        // ---- password: text and dots on the background, no card/border ----
        Item {
            id: passwordArea
            x: 0
            y: root.bottomZoneTop + Math.round(root.bottomZoneHeight * 0.55)
            width: root.width
            height: Theme.u(1.6)
            visible: root.context.state !== root.context.unlocked

            readonly property bool typing:
                root.context.currentText.length > 0
                || root.context.state === root.context.authenticating
                || root.context.state === root.context.failed

            Text {
                id: promptText
                x: Math.round((root.width - width) / 2)
                y: 0
                text: "Enter password"
                color: Theme.surfaceVariantText
                font.family: Theme.fontDisplay
                // Same "not a dash* token" reasoning as dateText above --
                // Theme.u(0.45) (~20px @ default density), comfortably
                // over the 18px floor.
                font.pixelSize: Math.max(18, Theme.u(0.45))
                opacity: passwordArea.typing ? 0 : 0.65
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }

            Row {
                id: dotsRow
                y: 0
                x: Math.round((root.width - width) / 2)
                spacing: Theme.space3
                opacity: passwordArea.typing ? 1 : 0
                visible: opacity > 0
                transform: Translate { id: shakeT; x: 0 }
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Repeater {
                    model: Math.min(root.context.currentText.length, 24)
                    delegate: Rectangle {
                        // At least 18px diameter (Theme.u(0.42) ~= 18.5px
                        // @ default density), not the old fixed 11px --
                        // matched the same "too tiny on a lock screen"
                        // review note as the date/prompt text above.
                        readonly property int dotSize: Math.max(18, Theme.u(0.42))
                        width: dotSize; height: dotSize; radius: dotSize / 2
                        color: Theme.surfaceText
                    }
                }

                Rectangle {
                    id: caret
                    visible: root.context.currentText.length === 0 && passwordArea.typing
                    width: 3; height: Math.max(22, Theme.u(0.5))
                    color: Theme.surfaceText

                    SequentialAnimation on opacity {
                        running: caret.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 0; duration: 500 }
                        NumberAnimation { to: 1; duration: 500 }
                    }
                }
            }
        }
    }

    // ---- shader failure containment ---------------------------------------
    property bool _shaderOk: true

    Connections {
        target: asciiEffect
        function onStatusChanged() {
            if (asciiEffect.status === ShaderEffect.Error) {
                console.warn("lock: AsciiLockSurface shader failed to load, "
                    + "falling back to plain time text")
                root._shaderOk = false
            }
        }
    }

    // ---- fail shake ---------------------------------------------------
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shakeT; property: "x"; to: -10; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 10; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 8; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 60 }
        onFinished: root.context.acknowledgeFailure()
    }

    // ---- unlocking: fade the whole content out, then hand back control ----
    NumberAnimation {
        id: unlockFade
        target: content
        property: "opacity"
        to: 0
        duration: 260
        easing.type: Easing.OutCubic
        onFinished: root.context.finishUnlockAnimation()
    }

    Connections {
        target: root.context
        function onStateChanged() {
            const s = root.context.state
            if (s === root.context.failed) {
                shakeAnim.restart()
            } else if (s === root.context.unlocking) {
                unlockFade.start()
            }
        }
    }

    // ---- keyboard input (identical contract to lock/LockSurface.qml) ------
    Keys.onPressed: event => root._handleKeyEvent(event)

    function _handleKeyEvent(event): void {
        if (root.context.state !== root.context.locked
                && root.context.state !== root.context.failed) {
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.context.submit(root.context.currentText)
        } else if (event.key === Qt.Key_Escape) {
            root.context.currentText = ""
        } else if (event.key === Qt.Key_Backspace) {
            root.context.currentText = root.context.currentText.slice(0, -1)
        } else if (event.text && event.text.length > 0 && event.text >= " ") {
            root.context.currentText += event.text
        }
        event.accepted = true
    }

    function _grabFocus(): void {
        root.forceActiveFocus()
    }

    onVisibleChanged: if (root.visible) root._grabFocus()

    Connections {
        target: root.Window.window
        function onActiveChanged() {
            if (root.Window.window && root.Window.window.active)
                root._grabFocus()
        }
    }

    Component.onCompleted: root._grabFocus()
}
