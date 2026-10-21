import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../services"
import "../core"

PanelWindow {
    required property var modelData
    id: root

    readonly property var screenObject: modelData

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "qml-rice-dither"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    color: "transparent"

    // Determine if wallpaper should be paused
    readonly property bool shouldPause: {
        const monitor = Hyprland.monitorFor(screenObject)
        if (!monitor || !monitor.activeWorkspace)
            return true

        // Paused if workspace has fullscreen client
        if (monitor.activeWorkspace.hasFullscreen)
            return true

        // Check if any tiled window covers ≥90% of output
        const toplevels = monitor.activeWorkspace.toplevels?.values || []
        const screenArea = screenObject.width * screenObject.height
        let tiledArea = 0

        for (const toplevel of toplevels) {
            const ipc = toplevel.lastIpcObject || {}
            // Only count tiled windows (not floating)
            if (!ipc.floating && ipc.size) {
                tiledArea += ipc.size[0] * ipc.size[1]
            }
        }

        return tiledArea >= screenArea * 0.9
    }

    readonly property bool isActive: !root.shouldPause
        && SettingsStore.boolValue("wallpaper", "dither", false)
        && !WallpaperService.currentIsAnimated

    // ---- Focal-point aware cropping for portrait monitors --------
    // Load focal-points cache to enable subject-aware cropping.
    //
    // CACHE KEY CONTRACT (must match tools/focal-points.py exactly -- see
    // that file's module docstring for the full rationale): key is
    // "<path>|<mtime>" where <path> is WallpaperService.currentStill
    // verbatim (no resolving on this side) and <mtime> is the integer
    // seconds mtime from `stat -c %Y <path>` (which dereferences symlinks,
    // same as Python's os.stat()). This works because currentStill is
    // never a ~/.local/share/wallpapers/<symlink>/... path in the first
    // place -- Config.wallpaper.directories (core/Config.qml) points
    // wallpaperctl.sh's scan straight at the real ~/Pictures/Wallpapers and
    // ~/Pictures/wallpapers directories, so currentStill already IS the
    // resolved real path that focal-points.py's scan also keys on.
    property var focalPointsCache: ({})

    readonly property string focalScriptPath: Quickshell.shellDir + "/tools/focal-points.py"
    readonly property string focalPythonPath: Quickshell.shellDir + "/tools/.venv/bin/python3"

    // Declarative load/reload of the focal-points cache. There is no
    // Quickshell.Io `TextFile` type -- that was always a runtime error
    // ("TextFile is not a type"), which is why focal points never loaded.
    // FileView is the real Quickshell.Io type for this; watchChanges plus
    // onFileChanged picks up focal-points.py's writes automatically, and
    // ensureFocalPoint() also calls reload() once its Process exits so a
    // freshly-computed point is picked up without waiting on a filesystem
    // change notification race.
    FileView {
        id: focalPointsFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell/focal-points.json"
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                root.focalPointsCache = JSON.parse(text())
            } catch (e) {
                console.warn("Could not parse focal-points.json:", e)
            }
            root.ensureFocalPoint()
        }
        onFileChanged: reload()
        onLoadFailed: error => {
            // Missing on first run (no focal points computed yet) -- not fatal.
        }
    }

    // currentStill is WallpaperService's readonly computed property
    // (currentStillPath || currentWallpaper); it emits currentStillChanged
    // whenever either backing property changes, so this is the one place
    // that needs to react to a wallpaper switch.
    readonly property string currentImagePath: WallpaperService.currentStill || ""

    // The cache-key mtime (see CACHE KEY CONTRACT above) has to come from
    // `stat -c %Y`, and there is no synchronous `Quickshell.exec()` --
    // that method does not exist on the Quickshell singleton (only `env`
    // and the fire-and-forget `execDetached` do), so the previous
    // `Quickshell.exec(...)` calls here always threw and were silently
    // swallowed by their own try/catch, permanently falling back to
    // center-crop regardless of the TextFile bug. mtime is now fetched
    // asynchronously via Process + StdioCollector (same pattern as
    // PaletteAutoService's resolveProcess) and cached per path; focalPoint
    // below only reads this cached value, it never shells out itself.
    property int currentImageMtime: -1

    Process {
        id: statProcess
        property string forPath: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const mtime = parseInt(text.trim())
                if (!isNaN(mtime) && statProcess.forPath === root.currentImagePath)
                    root.currentImageMtime = mtime
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("stat failed for", statProcess.forPath)
        }
    }

    function refreshImageMtime(imagePath: string): void {
        root.currentImageMtime = -1
        if (!imagePath)
            return
        statProcess.forPath = imagePath
        statProcess.command = ["stat", "-c", "%Y", imagePath]
        statProcess.running = true
    }

    onCurrentImagePathChanged: {
        root.refreshImageMtime(root.currentImagePath)
        root.introT = 0
        introAnim.restart()
    }

    // ---- intro dissolve on wallpaper change -------------------------------
    // 1.1s radial+Bayer cross-dissolve FROM ink (see dither.frag's `appear`)
    // whenever the shown image changes. A cross-dissolve from the PREVIOUS
    // wallpaper's own frame (rather than flat ink) was in scope per the port
    // brief but is deferred -- it needs an extra held ShaderEffectSource
    // snapshotting the prior frame before the Image source swaps, which
    // risks a stale/garbage texture on the very first paint after a
    // fullscreen-pause resume. Ink fallback is the spec's explicitly stated
    // "otherwise" path and is what's shipped here.
    property real introT: 1.0
    NumberAnimation {
        id: introAnim
        target: root
        property: "introT"
        from: 0.0
        to: 1.0
        duration: 1100
        easing.type: Easing.OutCubic
    }

    // Runs focal-points.py for the current image when it has no cache
    // entry yet. FileView's watchChanges/onFileChanged above reloads
    // focalPointsCache once this writes the JSON, which is what makes
    // focalPoint below pick up the freshly computed value. Without this,
    // any wallpaper never previously scanned by a manual `focal-points.py`
    // run would silently and permanently fall back to center-crop.
    Process {
        id: focalComputeProcess
        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn("focal-points.py failed for", root._pendingFocalPath)
            focalPointsFile.reload()
        }
    }
    property string _pendingFocalPath: ""

    function ensureFocalPoint(): void {
        const imagePath = root.currentImagePath
        if (!imagePath || root.currentImageMtime < 0 || focalComputeProcess.running)
            return
        const cacheKey = imagePath + "|" + root.currentImageMtime
        if (cacheKey in focalPointsCache)
            return
        root._pendingFocalPath = imagePath
        focalComputeProcess.command = [root.focalPythonPath, root.focalScriptPath, imagePath]
        focalComputeProcess.running = true
    }

    onCurrentImageMtimeChanged: root.ensureFocalPoint()

    Component.onCompleted: {
        root.refreshImageMtime(root.currentImagePath)
        root.ensureBake()
    }

    // The cache entry for the current image (fx, fy, w, h -- w/h added by
    // tools/focal-points.py alongside the focal point itself, read from
    // the same cv2.imread() decode it already does; see that file's
    // compute_focal_point() docstring). This is the ONLY source of image
    // dimensions used for crop math below -- deliberately never
    // wallpaperImage.implicitWidth/implicitHeight. Those report the
    // CLIPPED pixmap size once sourceClipRect is set (confirmed against
    // the Qt 6.8 docs: "the actual size of the image after scaling is
    // available via implicitWidth/implicitHeight", and sourceClipRect
    // affects that same loaded/scaled pixmap), so a crop computed from
    // them and then fed back into sourceClipRect shrinks a little further
    // on every recompute -- converging on a near-zero region after a
    // handful of iterations. That's what made the previous landscape
    // render show a tiny zoomed-in patch of wire instead of ~80% of the
    // image. Keying crop math to the cache's independently-known natural
    // size breaks that feedback loop entirely.
    readonly property var focalEntry: {
        const imagePath = root.currentImagePath
        if (!imagePath || root.currentImageMtime < 0)
            return null
        const cacheKey = imagePath + "|" + root.currentImageMtime
        return (cacheKey in focalPointsCache) ? focalPointsCache[cacheKey] : null
    }

    // Compute focal point for wallpaper image
    readonly property var focalPoint: {
        const e = root.focalEntry
        return e ? { fx: e.fx, fy: e.fy } : { fx: 0.5, fy: 0.5 }
    }

    // Compute the source-image-pixel crop rect (Image.sourceClipRect is
    // documented -- doc.qt.io/qt-6.8/qml-qtquick-image.html -- to take
    // SOURCE PIXEL coordinates, e.g. Qt.rect(100, 100, 512, 512), not a
    // normalised 0..1 fraction of the image). An earlier version of this
    // fix divided the pixel-space crop back down to a 0..1 fraction before
    // returning it, so sourceClipRect was being handed a sub-single-pixel
    // region on every screen -- QImageReader clips that to nothing, which
    // is what actually left the dither layer transparent/blank and let
    // awww show through. It also hardcoded a literal 1x1-pixel
    // Qt.rect(0,0,1,1) for every landscape/square screen regardless of
    // image size, which broke DP-1 (1920x1080, landscape) the same way.
    // Fixed by keeping the whole computation in source-pixel units and
    // applying the same focal-point-centered aspect crop to every
    // orientation (still a no-op crop when the image aspect already
    // matches the screen aspect) -- see focalEntry above for why the
    // dimensions come from the cache, not the Image item itself.
    //
    // No cache entry yet (image not scanned, or mtime lookup still
    // pending) returns a zero-size sentinel rect; the Image binding below
    // treats that as "no crop available yet" and sets sourceClipRect to
    // `undefined` (Qt's documented way to clear the clip / show the full
    // image) rather than clipping to a zero-area region, which would
    // render blank.
    readonly property rect imageCropRect: {
        const e = root.focalEntry
        if (!e || !e.w || !e.h)
            return Qt.rect(0, 0, 0, 0)

        const imgW = e.w
        const imgH = e.h
        const targetAspect = root.width / Math.max(root.height, 1)
        const imgAspect = imgW / imgH
        let cropW, cropH

        if (imgAspect > targetAspect) {
            // Image is too wide relative to the screen -- crop its sides.
            cropH = imgH
            cropW = targetAspect * imgH
        } else {
            // Image is too tall relative to the screen -- crop top/bottom.
            cropW = imgW
            cropH = imgW / targetAspect
        }

        // Center crop on focal point (in source-pixel coordinates).
        const focalX = focalPoint.fx * imgW
        const focalY = focalPoint.fy * imgH
        let cropX = focalX - cropW / 2
        let cropY = focalY - cropH / 2

        // Clamp to image bounds.
        cropX = Math.max(0, Math.min(cropX, imgW - cropW))
        cropY = Math.max(0, Math.min(cropY, imgH - cropH))

        return Qt.rect(cropX, cropY, cropW, cropH)
    }

    // ---- DitherVeil palette: theme-derived ink/paper, explicit overrides --
    // WCAG 2.x relative luminance / contrast ratio (sRGB -> linear-light,
    // then the standard (L1+0.05)/(L2+0.05)) -- used below to GUARANTEE the
    // ink/paper pair actually renders as "deep ink on genuinely light paper"
    // rather than trusting whatever Theme.surface/surfaceText happen to be
    // for the current wallpaper-derived (matugen) palette. The owner
    // explicitly complained about a muddy dark-grey-on-light-grey result
    // before, so this is an enforced floor (>= 7:1, WCAG AAA for normal
    // text), not just a hopeful default.
    function _relLuminance(c) {
        function lin(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }
    function _contrastRatio(a, b) {
        const la = root._relLuminance(a), lb = root._relLuminance(b)
        const hi = Math.max(la, lb), lo = Math.min(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }
    function _mixColor(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
            a.b + (b.b - a.b) * t, 1.0)
    }
    // "darkest surface" / "lightest on-surface" per the port brief, by
    // comparing the two candidate Theme tokens' own (perceptual, not WCAG --
    // this comparison only needs to pick a direction) luma so this still
    // reads correctly if Theme.dark flips (Theme.surface is near-black in
    // dark mode but near-white in light mode; surfaceText is the inverse).
    readonly property color _darkToken: root._relLuminance(Theme.surface) <= root._relLuminance(Theme.surfaceText)
        ? Theme.surface : Theme.surfaceText
    readonly property color _lightToken: root._relLuminance(Theme.surface) <= root._relLuminance(Theme.surfaceText)
        ? Theme.surfaceText : Theme.surface
    // Paper is lightly tinted with the wallpaper-derived primary (15%) --
    // matches DitherVeil's own warm #f4f1ea paper-on-#120f17-ink pair
    // (paper isn't flat neutral white, it carries a hint of the palette)
    // rather than a clinical grey/white.
    readonly property color _tintedPaper: root._mixColor(root._lightToken, Theme.primary, 0.15)

    // Enforced floor: if the theme-derived pair (after tinting) doesn't
    // clear 7:1, push ink toward true black / paper toward true white in
    // three widening steps until it does -- guarantees the shipped default
    // is never "dark grey on light grey" regardless of what a given
    // wallpaper's generated palette happens to produce.
    readonly property var _contrastSafePair: {
        let ink = root._darkToken
        let paper = root._tintedPaper
        const black = Qt.rgba(0, 0, 0, 1)
        const white = Qt.rgba(1, 1, 1, 1)
        for (let step = 0; step < 4; step++) {
            if (root._contrastRatio(ink, paper) >= 7.0)
                break
            ink = root._mixColor(ink, black, 0.4)
            paper = root._mixColor(paper, white, 0.4)
        }
        return [ink, paper]
    }
    readonly property color themeInk: root._contrastSafePair[0]
    readonly property color themePaper: root._contrastSafePair[1]
    readonly property real themeContrastRatio: root._contrastRatio(root.themeInk, root.themePaper)

    readonly property color ditherInkColor: Config.wallpaper.ditherInk.length > 0
        ? Config.wallpaper.ditherInk : root.themeInk
    readonly property color ditherPaperColor: Config.wallpaper.ditherPaper.length > 0
        ? Config.wallpaper.ditherPaper : root.themePaper
    readonly property color ditherRimColorValue: Config.wallpaper.ditherRimColor.length > 0
        ? Config.wallpaper.ditherRimColor : Theme.primary

    // ---- pattern/palette string -> shader-numeric mode --------------------
    readonly property real patternModeValue: {
        switch (Config.wallpaper.ditherPattern) {
        case "noise": return 1
        case "lines": return 2
        case "floyd": case "atkinson": return 3
        default: return 0 // "bayer"
        }
    }
    readonly property bool patternIsDiffused: Config.wallpaper.ditherPattern === "floyd"
        || Config.wallpaper.ditherPattern === "atkinson"
    readonly property real paletteModeValue: Config.wallpaper.ditherPaletteMode === "rgb" ? 1 : 0

    // ---- floyd/atkinson CPU bake management --------------------------------
    // Baked cells texture cache: ~/.cache/qml-rice/dither/<hash>.png (this
    // shell's own cache root, Config.appearance.cacheRoot -- the port brief
    // sketches ~/.local/cache/qml-rice, but that path doesn't exist anywhere
    // else in this repo and cacheRoot already IS the shell's one real cache
    // directory contract). One PNG per (image+mtime, screen size, cell size,
    // pattern, levels, contrast, brightness, crop rect) combination --
    // exactly the inputs tools/dither-bake.py's CPU error-diffusion result
    // depends on.
    function _hashString(s) {
        // FNV-1a, good enough for a cache-busting filename key (not security).
        let h = 0x811c9dc5
        for (let i = 0; i < s.length; i++) {
            h ^= s.charCodeAt(i)
            h = (h * 0x01000193) >>> 0
        }
        return h.toString(16).padStart(8, "0")
    }

    readonly property string bakeKey: {
        if (!root.patternIsDiffused || !root.currentImagePath || root.currentImageMtime < 0
                || root.width <= 0 || root.height <= 0 || !root.focalEntry)
            return ""
        const r = root.imageCropRect
        const parts = [
            root.currentImagePath, root.currentImageMtime,
            Math.round(root.width), Math.round(root.height),
            Config.wallpaper.ditherDotSize, Config.wallpaper.ditherPattern,
            Config.wallpaper.ditherLevels, Config.wallpaper.ditherContrast,
            Config.wallpaper.ditherBrightness,
            r.x.toFixed(1), r.y.toFixed(1), r.width.toFixed(1), r.height.toFixed(1)
        ]
        return parts.join("|")
    }

    readonly property string bakeCacheDir: Config.appearance.cacheRoot + "/dither"
    property string bakeReadyKey: ""
    property string bakeOutputPath: ""

    readonly property string bakeTargetPath: root.bakeKey.length > 0
        ? root.bakeCacheDir + "/" + root._hashString(root.bakeKey) + ".png"
        : ""

    // cellsValid (fed to dither.frag) is true only when the baked file on
    // disk actually matches the CURRENT bakeKey and cellsTex has finished
    // loading it -- a stale bake from a previous wallpaper/setting never
    // gets treated as valid just because a Process happens to be mid-flight
    // for the new one.
    readonly property bool cellsValid: root.patternIsDiffused
        && root.bakeReadyKey === root.bakeKey && root.bakeKey.length > 0
        && cellsTexImage.status === Image.Ready

    Process {
        id: bakeProcess
        property string forKey: ""
        stderr: StdioCollector { id: bakeErr }
        onExited: exitCode => {
            if (exitCode === 0) {
                root.bakeReadyKey = bakeProcess.forKey
                cellsTexImage.source = ""
                cellsTexImage.source = "file://" + root.bakeOutputPath
            } else {
                console.warn("dither-bake.py failed for", bakeProcess.forKey, "exit", exitCode, bakeErr.text)
            }
        }
    }

    function ensureBake(): void {
        if (!root.patternIsDiffused || root.bakeKey.length === 0)
            return
        if (root.bakeReadyKey === root.bakeKey)
            return
        if (bakeProcess.running && bakeProcess.forKey === root.bakeKey)
            return
        const r = root.imageCropRect
        // Computed from bakeKey here, not read from bakeTargetPath: this runs
        // from onBakeKeyChanged, which can fire before bakeTargetPath's own
        // binding has re-evaluated, handing the bake a stale "" output path.
        root.bakeOutputPath = root.bakeCacheDir + "/" + root._hashString(root.bakeKey) + ".png"
        bakeProcess.forKey = root.bakeKey
        bakeProcess.command = [
            Quickshell.shellDir + "/tools/.venv/bin/python3",
            Quickshell.shellDir + "/tools/dither-bake.py",
            root.currentImagePath,
            String(Math.round(root.width)), String(Math.round(root.height)),
            String(Config.wallpaper.ditherDotSize), Config.wallpaper.ditherPattern,
            String(Config.wallpaper.ditherLevels), String(Config.wallpaper.ditherContrast),
            String(Config.wallpaper.ditherBrightness),
            String(r.x), String(r.y), String(r.width), String(r.height),
            root.bakeOutputPath
        ]
        bakeProcess.running = true
    }

    onBakeKeyChanged: root.ensureBake()

    Image {
        id: cellsTexImage
        visible: false
        cache: false
        asynchronous: true
        smooth: false // NEAREST -- crisp cell blocks, never grey anti-aliased dots
        mipmap: false
    }

    // Raw cursor position and shader clock.
    property real cursorX: 0
    property real cursorY: 0
    property real shaderTime: 0

    // The reveal "spotlight" does NOT track the raw cursor 1:1 -- the owner
    // wants it to feel heavier, swaying/lagging behind with a bit of
    // overshoot, not crosshair-accurate. Two MotionValues (closed-form
    // damped springs, core/MotionValue.qml) chase cursorX/cursorY:
    // underdamped (zeta 0.7 < 1) so it gently oscillates past the target
    // when the cursor stops, response ~0.55s so the lag/sway is visible but
    // not sluggish. The trail buffer deposits at THIS position, not the raw
    // cursor.
    property MotionValue springX: MotionValue {
        value: 0
        target: root.cursorX
        omega: 2 * Math.PI / 0.55
        zeta: 0.7
        unit: "px"
    }
    property MotionValue springY: MotionValue {
        value: 0
        target: root.cursorY
        omega: 2 * Math.PI / 0.55
        zeta: 0.7
        unit: "px"
    }

    // The ambient wave keeps FrameAnimation running forever, which damages the
    // whole Background layer every frame and forces Hyprland to recomposite
    // (and re-blur) the full screen. Only pay for that on AC power.
    readonly property bool waveOn: SettingsStore.boolValue("wallpaper", "ditherWave", true)
        && !BatteryService.onBattery

    // Previous-frame spring position, for trail.frag's segment-distance
    // capsule stroke (current spring position to previous spring position,
    // not a single point) -- see frameAnim.onTriggered below, which is the
    // only place this is written (once per frame, after the mask uniforms
    // for THIS frame have already bound to the old value).
    property real prevSpringX: 0
    property real prevSpringY: 0

    // Cursor-presence, eased (tau 0.16s per the DitherVeil port brief) rather
    // than a hard containsMouse toggle -- scales both the trail.frag capsule
    // deposit strength and the reveal radius (0.45 + 0.55*presence) below,
    // so the reveal grows in/fades out instead of snapping.
    property real presence: 0
    readonly property real presenceTarget: root.pointerOver ? 1.0 : 0.0

    // Perf: stay alive while there's still trail content to decay (a window
    // opened on every hover/move, long enough to cover the spring settling
    // -- ~0.5s beyond the last cursor movement -- plus the trail's own
    // ~0.6s decay constant, with margin) or while the idle wave is on.
    // Fully settled with wave off means this drops to false and the whole
    // FrameAnimation below stops -- zero redraws.
    property bool trailActive: false
    Timer {
        id: trailIdleTimer
        interval: 2200
        onTriggered: root.trailActive = false
    }
    function _kickTrail() {
        trailActive = true
        trailIdleTimer.restart()
    }

    // ---- click burst: up to 4 shockwave rings, round-robin --------------
    // Four separate vec4 uniforms (burst0..3 in dither.frag), not a uniform
    // array -- uniform arrays are risky on the GLSL 100es/120 variants this
    // shell's NVIDIA GL context picks. `t < 0` is the shader-side sentinel
    // for "inactive slot".
    property var burstX: [0, 0, 0, 0]
    property var burstY: [0, 0, 0, 0]
    property var burstStart: [-1, -1, -1, -1]
    property var burstReach: [0, 0, 0, 0]
    property int burstNext: 0

    function fireBurst(x, y) {
        const corners = [
            Qt.point(0, 0), Qt.point(root.width, 0),
            Qt.point(0, root.height), Qt.point(root.width, root.height)
        ]
        let maxDist = 0
        for (const c of corners)
            maxDist = Math.max(maxDist, Math.hypot(x - c.x, y - c.y))
        // reach = max corner distance + (final ring) width margin. The
        // shader's own width = max(60, radius*0.9) is circular with radius,
        // so this is a fixed additive approximation rather than solving it
        // exactly -- close enough that the ring still fully clears the
        // screen before its 1.2s lifetime ends.
        const reach = maxDist + 60

        const i = root.burstNext
        const nx = root.burstX.slice(), ny = root.burstY.slice()
        const ns = root.burstStart.slice(), nr = root.burstReach.slice()
        nx[i] = x; ny[i] = y; ns[i] = root.shaderTime; nr[i] = reach
        root.burstX = nx; root.burstY = ny
        root.burstStart = ns; root.burstReach = nr
        root.burstNext = (i + 1) % 4
        root._kickTrail()
    }

    FrameAnimation {
        id: frameAnim
        running: root.isActive && (root.trailActive || root.waveOn)
        onTriggered: {
            const dt = frameAnim.frameTime > 0 ? frameAnim.frameTime : 0.016
            root.shaderTime += dt

            // Presence: exponential ease toward presenceTarget, tau 0.16s.
            const alpha = 1 - Math.exp(-dt / 0.16)
            root.presence += (root.presenceTarget - root.presence) * alpha

            // Advance the capsule stroke's "previous" endpoint to THIS
            // frame's spring position only after this frame's shader
            // uniforms (bound to the old prevSpringX/Y) have already been
            // read by the scene graph sync that follows this signal.
            root.prevSpringX = root.springX.value
            root.prevSpringY = root.springY.value
        }
    }

    // Desktop.qml sits on the Bottom layer with a full-screen input mask (so
    // its right-click menu works anywhere), so on Wayland IT owns the pointer
    // and cursorArea below never sees a hover while it's present. Desktop
    // republishes the position through PointerService for exactly this.
    readonly property bool externalHover:
        PointerService.hovered && PointerService.screenName === (root.screenObject ? root.screenObject.name : "")
    readonly property bool pointerOver: root.externalHover || cursorArea.containsMouse

    Connections {
        target: PointerService
        function onXChanged() { if (root.externalHover) { root.cursorX = PointerService.x; root._kickTrail() } }
        function onYChanged() { if (root.externalHover) { root.cursorY = PointerService.y; root._kickTrail() } }
        function onHoveredChanged() { if (root.externalHover) root._kickTrail() }
    }

    // Mouse area for cursor tracking and click bursts (only receives events
    // where no window covers the desktop -- Background layershell layer,
    // and this MouseArea claims no keyboard focus and has no sibling to
    // block, so it cannot intercept anything else on the desktop).
    MouseArea {
        id: cursorArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true

        onMouseXChanged: if (containsMouse) { root.cursorX = mouseX; root._kickTrail() }
        onMouseYChanged: if (containsMouse) { root.cursorY = mouseY; root._kickTrail() }

        onContainsMouseChanged: if (containsMouse) root._kickTrail()

        onClicked: mouse => root.fireBurst(mouse.x, mouse.y)
    }

    Image {
        id: wallpaperImage
        width: root.width
        height: root.height
        // wallpaper.ditherImage overrides the awww-managed wallpaper only
        // when the user has explicitly set one (Config.wallpaper.ditherImage
        // default is "" -- see core/Config.qml); otherwise this shows
        // WallpaperService.currentStill, i.e. whatever was actually applied,
        // same as the awww layer underneath it.
        source: {
            const custom = Config.wallpaper.ditherImage
            return (custom && custom.length > 0)
                ? (custom.startsWith("/") ? "file://" + custom : custom)
                : (WallpaperService.currentStill || "")
        }
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false

        // Focal-point aware cropping (see root.imageCropRect/focalEntry
        // above for both the source-pixel-vs-fraction bug and the
        // implicitWidth/implicitHeight feedback-loop bug this used to
        // have). Deliberately gated on root.focalEntry's cached w/h, NOT
        // wallpaperImage.implicitWidth/implicitHeight -- reading this
        // Image's own (post-clip) size back into its own sourceClipRect
        // is exactly the feedback loop that shrank the crop every
        // recompute. No cache entry yet (image not scanned, or mtime
        // lookup still pending) falls back to `undefined` (Qt's
        // documented way to clear sourceClipRect / use the full image)
        // rather than clipping to the zero-size sentinel rect, which
        // would render blank.
        sourceClipRect: (root.focalEntry && root.focalEntry.w && root.focalEntry.h)
            ? root.imageCropRect
            : undefined
    }

    // ---- Liquid warp domain displacement ---------------------------------
    // Applies a time-driven looping UV warp to the wallpaper image.
    // Paused (visible:false) when screen has fullscreen window or warp is
    // disabled (visible controls whether the shader effect is rendered at all).
    ShaderEffect {
        id: warpShader
        anchors.fill: parent
        visible: root.isActive && Config.wallpaper.warp && !root.shouldPause

        property variant source: wallpaperImage
        property real time: root.shaderTime
        property real warpStrength: Config.wallpaper.warpStrength
        property size resolution: Qt.size(parent.width, parent.height)

        fragmentShader: Qt.resolvedUrl("../shaders/warp.frag.qsb")
    }

    // Capture the warp shader output for the dither shader to sample.
    // This ensures the dither operates on the warped image.
    // Only kept live while warp is actually enabled: the dither ShaderEffect
    // below reads `wallpaperImage` directly (not this source) when
    // Config.wallpaper.warp is false, so a live binding here regardless of
    // that setting would just be wasted per-frame texture re-rendering.
    ShaderEffectSource {
        id: warpedImage
        sourceItem: root.isActive && Config.wallpaper.warp ? warpShader : wallpaperImage
        hideSource: false
        live: root.isActive && Config.wallpaper.warp
        smooth: true
        wrapMode: ShaderEffectSource.ClampToEdge
        width: root.width
        height: root.height
        visible: false
    }

    // Static reference textures (wallpaper/textures/, committed): 8x8 Bayer
    // threshold matrix and the 64x64 blue-noise (void-and-cluster) stipple.
    // Both NEAREST-sampled (smooth:false) -- these are lookup tables, not
    // photographic content, and bilinear filtering between adjacent
    // threshold texels is exactly what would turn crisp two-colour cells
    // into grey anti-aliased dots.
    Image {
        id: bayer8Image
        source: Qt.resolvedUrl("textures/bayer8.png")
        visible: false
        cache: true
        smooth: false
        mipmap: false
    }
    Image {
        id: noise64Image
        source: Qt.resolvedUrl("textures/noise64.png")
        visible: false
        cache: true
        smooth: false
        mipmap: false
    }

    // ---- low-res reveal trail buffer (feedback), ping-pong at 0.5x res ---
    // Decays its own previous frame (linear "linger" fade) and deposits a
    // capsule-stroke mask from the previous spring-lagged brush position to
    // the current one each frame. `trailShader`'s output is captured by
    // `trailFeedback` (a recursive, live ShaderEffectSource wrapping
    // trailShader itself) and fed back in as `prevFrame` next frame -- the
    // classic QML recursive-feedback trail pattern.
    Item {
        id: trailBuffer
        width: Math.max(1, Math.round(root.width / 2))
        height: Math.max(1, Math.round(root.height / 2))
        visible: false
        layer.enabled: false

        ShaderEffect {
            id: trailShader
            anchors.fill: parent

            property variant prevFrame: trailFeedback
            property point cursorUV: {
                if (root.width <= 0 || root.height <= 0)
                    return Qt.point(-1, -1)
                return Qt.point(root.springX.value / root.width,
                                 root.springY.value / root.height)
            }
            property point prevCursorUV: {
                if (root.width <= 0 || root.height <= 0)
                    return Qt.point(-1, -1)
                return Qt.point(root.prevSpringX / root.width,
                                 root.prevSpringY / root.height)
            }
            // Reveal radius in UV-height-fraction units (trail.frag's
            // segment/capsule maths is aspect-corrected against screen
            // HEIGHT) -- revealRadius is a px setting (default 200, so
            // ~0.185 at 1080p, matching the previous soft-disc size) scaled
            // by presence per the port brief: radius*(0.45+0.55*presence).
            property real radius: (Config.wallpaper.ditherRevealRadius / Math.max(root.height, 1))
                * (0.45 + 0.55 * root.presence)
            property real softness: Config.wallpaper.ditherSoftness
            property real linger: Config.wallpaper.ditherLinger
            property real presence: root.presence
            property real dt: frameAnim.frameTime > 0 ? frameAnim.frameTime : 0.016
            property real time: root.shaderTime
            property size resolution: Qt.size(trailBuffer.width, trailBuffer.height)

            fragmentShader: Qt.resolvedUrl("../shaders/trail.frag.qsb")
        }

        ShaderEffectSource {
            id: trailFeedback
            sourceItem: trailShader
            hideSource: true
            recursive: true
            live: root.isActive && (root.trailActive || root.waveOn)
            smooth: true
            wrapMode: ShaderEffectSource.ClampToEdge
            width: trailBuffer.width
            height: trailBuffer.height
        }
    }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("../shaders/dither.frag.qsb")

        // Unwarped source (binding=1) -- the dither CELL GRID always samples
        // this regardless of Config.wallpaper.warp, so ordered/diffused
        // cells never ride the warp (see dither.frag's warp-option-(a) note).
        // Without a property literally named `source` pointing at an Item,
        // ShaderEffect never creates the texture binding at all.
        property variant source: wallpaperImage
        // Warped source (binding=6) -- only the reveal's full-colour photo
        // sample uses this. Identical content to `source` when warp is off.
        property variant warpedSource: Config.wallpaper.warp ? warpedImage : wallpaperImage
        // Bound to `sampler2D trailMask` (binding=2) -- the low-res reveal
        // buffer above, bilinear-upsampled by the GPU sampler (smooth:true
        // on trailFeedback) then edge-warped in-shader.
        property variant trailMask: trailFeedback
        property variant cellsTex: cellsTexImage
        property variant bayer8Tex: bayer8Image
        property variant noise64Tex: noise64Image

        // Uniforms
        property real time: root.shaderTime
        // Dither cell pitch in texel space. User-adjustable via
        // wallpaper.ditherDotSize (DitherVeil default: 2px cells).
        property real cellSize: Config.wallpaper.ditherDotSize
        property size resolution: Qt.size(parent.width, parent.height)
        property real waveAmp: 1.6
        property real waveSpeed: 0.5
        property bool waveOn: root.waveOn
        // Levels black point applied before dithering -- see
        // shaders/dither.frag. Suppresses the faint JPEG-grain/ambient-
        // shadow luminance in nominally-black source regions so they
        // dither to flat ink instead of a visible dot grid.
        property real blackPoint: Config.wallpaper.ditherBlackPoint
        // Theme-derived (or explicit hex override) ink/paper -- see
        // root.themeInk/themePaper above. Deliberately NOT the flat
        // hardcoded black/near-white the pre-DitherVeil ordered-dither-only
        // shader used, so the wallpaper reads as part of this shell's own
        // palette instead of a fixed originkit.dev reference swatch.
        property vector3d inkColor: Qt.vector3d(
            root.ditherInkColor.r, root.ditherInkColor.g, root.ditherInkColor.b)
        property vector3d paperColor: Qt.vector3d(
            root.ditherPaperColor.r, root.ditherPaperColor.g, root.ditherPaperColor.b)

        property real patternMode: root.patternModeValue
        property real paletteMode: root.paletteModeValue
        property real levels: Config.wallpaper.ditherLevels
        property real contrast: Config.wallpaper.ditherContrast
        property real brightness: Config.wallpaper.ditherBrightness
        property bool cellsValid: root.cellsValid
        property real reverseMask: Config.wallpaper.ditherReverse ? 1.0 : 0.0
        property real rim: Config.wallpaper.ditherRim
        property vector3d rimColor: Qt.vector3d(
            root.ditherRimColorValue.r, root.ditherRimColorValue.g, root.ditherRimColorValue.b)
        property real introT: root.introT

        property vector4d burst0: Qt.vector4d(
            root.burstX[0], root.burstY[0], root.burstStart[0], root.burstReach[0])
        property vector4d burst1: Qt.vector4d(
            root.burstX[1], root.burstY[1], root.burstStart[1], root.burstReach[1])
        property vector4d burst2: Qt.vector4d(
            root.burstX[2], root.burstY[2], root.burstStart[2], root.burstReach[2])
        property vector4d burst3: Qt.vector4d(
            root.burstX[3], root.burstY[3], root.burstStart[3], root.burstReach[3])
    }
}
