import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../core"
import "../services"

/**
 * EdgeVisualizer — a high-resolution cava spectrum drawn as one continuous
 * "rollercoaster track" curve rooted along the bottom edge of the screen.
 * One instance per screen (see shell.qml's Variants), fully click-through.
 *
 * OWN CAVA INSTANCE. Separate from VisualizerService's two existing
 * processes (the 4-bar island meter and VinylDisc's 64-bin ring) -- this
 * wants far more bars (~1 per 6px of screen width) at a higher framerate
 * than either of those needs, and per-screen bar counts differ, so each
 * screen gets its own cava config written to a temp file and its own
 * Process, spawned only while genuinely visible.
 *
 * MIRROR SYMMETRY. cava is only asked for HALF the bars (`halfBars`); the
 * rendered curve mirrors that half left and right around the screen's
 * horizontal centre, so bin 0 (bass) sits at the centre and the highest
 * bin sits at both outer edges. Tried both mirrored and left-to-right raw
 * orderings while iterating -- mirrored reads as a deliberate "track",
 * raw reads like a truncated bar chart with a dead half.
 *
 * SMOOTHING. Each of the 2*halfBars points is smoothed by a hand-rolled
 * critically-damped spring evaluated in one FrameAnimation loop (same
 * closed-form shape as core/MotionValue and components/VinylDisc.qml's
 * `_stepBars`) -- not one MotionValue per point.
 *
 * VISIBILITY. Hidden, and its cava process + frame clock stopped, when:
 * nothing is playing, the setting is off, or this screen's focused
 * workspace has a fullscreen client (matches wallpaper/DitherWallpaper.
 * qml's own per-monitor fullscreen check). Opacity fades via a spring
 * rather than a hard show/hide.
 */
PanelWindow {
    id: root

    required property var screen

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property bool fullscreenOnMonitor:
        monitor?.activeWorkspace?.hasFullscreen ?? false

    readonly property bool settingEnabled: Config.visualizer.edge
    // Measured with music playing, on AC, top 8s CPU samples: qs 45% /
    // cava 15% / Hyprland 12.5% with this edge visualizer on; turning ONLY
    // it off dropped that to qs 31% / cava 10.5% -- its own cava process
    // plus the every-vsync FrameAnimation physics step (clock below) is the
    // single most expensive thing this shell runs. Same pattern as
    // wallpaper/DitherWallpaper.qml's ambient wave (commit dac24f1): gate
    // the whole thing off on battery so neither the process nor the frame
    // clock runs unplugged. `visualizer.edge` still applies normally on AC.
    readonly property bool shouldShow: settingEnabled
        && MediaService.playing && !root.fullscreenOnMonitor
        && !BatteryService.onBattery

    // Match the monitor's own refresh rate (desktop-first, per the owner's
    // "worry about the laptop later" -- a 60Hz cap here would visibly
    // under-sample a 144/240Hz panel's worth of cava data). screen.refresh
    // Rate is QScreen's own reading, the same value hyprctl monitors -j
    // reports as refreshRate; a monitor not yet reporting one (unlikely,
    // but seen transiently on hotplug) falls back to a safe 60.
    readonly property real _screenRefreshRate:
        screen && screen.refreshRate > 0 ? screen.refreshRate : 60
    readonly property int cavaFramerate:
        Math.max(30, Math.min(240, Math.round(root._screenRefreshRate)))

    // ---- bar geometry, scaled to this screen's width --------------------
    // Measured against top -b: a full 1-bar-per-6px density redrawn every
    // vsync frame at 60fps with a 3-pass (fill/rail/stroke) bezier trace
    // cost ~70% of a core per screen -- an order of magnitude over the <3%
    // budget. 1-per-9px plus a 30fps paint throttle (physics still steps
    // every vsync frame, only the Canvas repaint is throttled) brought it
    // back into budget while still reading as a dense, high-res curve, not
    // a coarse bar chart.
    readonly property int halfBars: Math.max(8,
        Math.floor((screen ? screen.width : 1920) / 14 / 2))
    readonly property int pointCount: halfBars * 2

    anchors { bottom: true; left: true; right: true }
    implicitHeight: Math.max(1,
        Math.round((screen ? screen.height : 1080) * Config.visualizer.edgeHeight))
    color: "transparent"

    WlrLayershell.namespace: "qml-rice:edge-visualizer"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0

    // Fully click-through -- an empty region claims no input at all.
    mask: Region {}

    visible: opacityMotion.value > 0.003 || root.shouldShow

    MotionValue {
        id: opacityMotion
        target: root.shouldShow ? 1.0 : 0.0
        omega: 6.0
        zeta: 1.0
        unit: "ratio"
    }

    // ---- per-screen cava config, written once per bar-count/refresh-rate
    // change (a rate baked into the filename regenerates the config if the
    // monitor's reported refresh rate ever changes, e.g. VRR or a mode
    // switch) --------------------------------------------------------------
    readonly property string _configPath:
        "/tmp/qml-rice-edge-cava-" + (screen ? screen.name : "default")
            + "-" + root.halfBars + "-" + root.cavaFramerate + ".conf"

    FileView {
        id: cavaConfig
        path: root._configPath
        blockLoading: true
        blockWrites: true
        printErrors: false
        Component.onCompleted: setText(
            "[general]\n"
            + "bars = " + root.halfBars + "\n"
            + "framerate = " + root.cavaFramerate + "\n"
            + "autosens = 1\n"
            + "lower_cutoff_freq = 50\n"
            + "higher_cutoff_freq = 10000\n"
            + "\n[input]\n"
            + "method = pipewire\n"
            + "source = auto\n"
            + "\n[output]\n"
            + "method = raw\n"
            + "raw_target = /dev/stdout\n"
            + "data_format = ascii\n"
            + "ascii_max_range = 1000\n"
            + "channels = mono\n"
            + "mono_option = average\n"
            + "\n[smoothing]\n"
            + "noise_reduction = 0\n"
            + "monstercat = 0\n")
    }

    property var _rawBins: []
    Component.onCompleted: {
        const z = []
        for (let i = 0; i < root.halfBars; i++) z.push(0)
        root._rawBins = z
        const v = [], vel = []
        for (let i = 0; i < root.pointCount; i++) { v.push(0); vel.push(0) }
        root._val = v
        root._vel = vel
    }

    Process {
        id: cavaProcess
        command: ["cava", "-p", root._configPath]
        running: root.shouldShow

        stdout: SplitParser {
            onRead: data => root._parseFrame(data)
        }

        onRunningChanged: {
            if (!cavaProcess.running) {
                const z = []
                for (let i = 0; i < root.halfBars; i++) z.push(0)
                root._rawBins = z
            }
        }
    }

    function _parseFrame(line: string): void {
        const parts = line.split(";").filter(p => p.length > 0)
        if (parts.length < root.halfBars)
            return
        const next = []
        for (let i = 0; i < root.halfBars; i++) {
            const raw = Number(parts[i])
            const clamped = Number.isFinite(raw)
                ? Math.max(0, Math.min(1, raw / 1000)) : 0
            next.push(Math.sqrt(clamped))
        }
        root._rawBins = next
    }

    // ---- per-point critically-damped smoothing (one loop, no MotionValues)
    property var _val: []
    property var _vel: []
    readonly property real _pointOmega: 16.0

    function _stepPoints(dt: real): void {
        const bins = root._rawBins
        const half = root.halfBars
        const vals = root._val
        const vels = root._vel
        const w = root._pointOmega
        const e = Math.exp(-w * dt)
        for (let i = 0; i < root.pointCount; i++) {
            const binIndex = i < half ? (half - 1 - i) : (i - half)
            const target = bins[binIndex] || 0
            const y0 = (vals[i] || 0) - target
            const v0 = vels[i] || 0
            const B = v0 + w * y0
            const y = e * (y0 + B * dt)
            const v = e * (v0 - w * B * dt)
            vals[i] = target + y
            vels[i] = v
        }
    }

    // Physics steps every vsync frame (smoothing stays correct regardless
    // of dt), but the Canvas repaint below is throttled to ~30fps -- see
    // the CPU note on `halfBars` above, this was the other half of getting
    // a 3-pass bezier trace back under budget without visibly stepping.
    property int _paintDivider: 0
    FrameAnimation {
        id: clock
        running: root.shouldShow || opacityMotion.active
        onTriggered: {
            const dt = Math.min(0.05, frameTime)
            root._stepPoints(dt)
            root._paintDivider = (root._paintDivider + 1) % 4
            if (root._paintDivider === 0)
                canvas.requestPaint()
        }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: false
        renderStrategy: Canvas.Cooperative
        opacity: opacityMotion.value

        // Cached per paint-size/colour -- createLinearGradient is not free,
        // and the gradient itself only ever depends on height + the accent
        // colour, never on the per-frame bar values.
        property var _cachedGradient: null
        property real _cachedGradientHeight: -1
        property color _cachedGradientColor: "transparent"

        Connections {
            target: Theme
            function onPrimaryChanged(): void { canvas.requestPaint() }
        }
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height
            const n = root._val.length
            if (n < 2) return
            const amplitude = h * 0.85
            const pts = []
            for (let i = 0; i < n; i++) {
                const x = (i / (n - 1)) * w
                const v = Math.max(0, Math.min(1, root._val[i] || 0))
                pts.push({ x: x, y: h - v * amplitude })
            }

            function tracePath() {
                ctx.moveTo(pts[0].x, pts[0].y)
                for (let i = 0; i < pts.length - 1; i++) {
                    const p0 = pts[i === 0 ? 0 : i - 1]
                    const p1 = pts[i]
                    const p2 = pts[i + 1]
                    const p3 = pts[i + 2 < pts.length ? i + 2 : pts.length - 1]
                    const cp1x = p1.x + (p2.x - p0.x) / 6
                    const cp1y = p1.y + (p2.y - p0.y) / 6
                    const cp2x = p2.x - (p3.x - p1.x) / 6
                    const cp2y = p2.y - (p3.y - p1.y) / 6
                    ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y)
                }
            }

            const c = Theme.primary
            if (canvas._cachedGradient === null || canvas._cachedGradientHeight !== h
                    || canvas._cachedGradientColor !== c) {
                const grad = ctx.createLinearGradient(0, 0, 0, h)
                grad.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0.32))
                grad.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0.0))
                canvas._cachedGradient = grad
                canvas._cachedGradientHeight = h
                canvas._cachedGradientColor = c
            }

            // Gradient fill under the main curve (one pass).
            ctx.beginPath()
            tracePath()
            ctx.lineTo(w, h)
            ctx.lineTo(0, h)
            ctx.closePath()
            ctx.fillStyle = canvas._cachedGradient
            ctx.fill()

            // Crisp main track (second and only other pass -- the faint
            // parallel "rail" was tried as a third pass and cut: measured
            // cost outweighed the visual gain once the fill was already
            // reading as depth).
            ctx.beginPath()
            tracePath()
            ctx.strokeStyle = Theme.primary
            ctx.lineWidth = 2
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.stroke()
        }
    }
}
