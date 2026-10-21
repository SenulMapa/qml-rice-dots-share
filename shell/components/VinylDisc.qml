import QtQuick
import Quickshell.Widgets
import "../core"
import "../services"

/**
 * VinylDisc — the dashboard Now Playing centrepiece: a dark grooved vinyl
 * disc (shaders/vinyl.frag) with the album art as its centre label
 * (~55% of diameter), a 64-bar cava spectrum ring around it, both driven
 * by spring physics on ANGULAR VELOCITY (not angle) so play/pause reads as
 * spin-up/spin-down instead of a start/stop snap.
 *
 * Angle is accumulated in a FrameAnimation from the spring's own `value`
 * (rad/s), so the spring only ever governs speed -- position is a plain
 * time integral of it, which is what makes "eases to a stop, not a snap"
 * true: velocity relaxes to 0 smoothly, and the accumulator simply stops
 * advancing once it gets there.
 *
 * Ring bars are drawn on ONE Canvas (not 64 animated Items) and smoothed
 * with a hand-rolled critically-damped spring per bar per frame, evaluated
 * in the same FrameAnimation -- see `_springStep`, the same closed-form
 * shape as core/MotionValue's critically-damped branch, just inlined for
 * an array instead of instantiating 64 MotionValue objects.
 */
Item {
    id: root

    property bool playing: false
    property url artworkSource: ""
    readonly property bool artworkReady: art.status === Image.Ready
        && artworkSource.toString().length > 0
    // Whether the card housing this disc is genuinely on screen -- gates
    // both the frame clock and the cava spectrum process registration,
    // same rule as the old panels/DashboardMediaCard.qml ring used.
    property bool onScreen: true

    // The ring lives OUTSIDE the disc's rim (a gap, then bars radiating
    // further out) -- not drawn over the vinyl's own surface. `diameter` is
    // this item's full bounding box; the disc itself is sized down to leave
    // room for the ring's gap + max bar length on every side.
    readonly property real diameter: Math.min(width, height)
    readonly property real ringGap: Theme.u(0.06)
    readonly property real barMinLen: Theme.u(0.05)
    readonly property real barMaxLen: Theme.u(0.3)
    readonly property real barWidth: Math.max(1.2, Theme.u(0.05))
    readonly property real discDiameter: Math.max(0,
        diameter - 2 * (ringGap + barMaxLen))
    readonly property real labelDiameter: discDiameter * 0.55

    // ---- angular velocity springs (rad/s) -------------------------------
    // BPM-synced: disc does one revolution per 8 beats, ring one revolution
    // per 32 beats (4x slower than the disc) and spins the opposite way so
    // the two layers still read as independent, not one rigid assembly.
    // At 120 BPM that's disc 15rpm / 0.25 rev/s, ring 3.75rpm -- both far
    // calmer than the old fixed 33.33rpm turntable rate, which read as
    // "always spinning too fast" regardless of the actual song. When
    // TempoService has no confident reading (track just started, no clear
    // beat, or nothing playing) fall back to fixed defaults: 10rpm disc,
    // 2.5rpm ring -- still a ratio of 4, still calm.
    readonly property real _beatsPerDiscRev: 8
    readonly property real _beatsPerRingRev: 32
    readonly property real _fallbackDiscRpm: 10
    readonly property real _fallbackRingRpm: 2.5
    readonly property real _bpm: TempoService.available ? TempoService.smoothedBpm : 0
    // rev/s = bpm / 60 / beatsPerRev; rad/s = rev/s * 2*pi
    readonly property real discRate: TempoService.available
        ? (_bpm / 60 / _beatsPerDiscRev) * 2 * Math.PI
        : (_fallbackDiscRpm / 60) * 2 * Math.PI
    readonly property real ringRate: TempoService.available
        ? -(_bpm / 60 / _beatsPerRingRev) * 2 * Math.PI
        : -(_fallbackRingRpm / 60) * 2 * Math.PI

    readonly property bool spinning: root.playing && root.onScreen

    MotionValue {
        id: discVelocity
        target: root.spinning ? root.discRate : 0
        omega: 5.5
        zeta: 1.0
        unit: "px"
    }
    MotionValue {
        id: ringVelocity
        target: root.spinning ? root.ringRate : 0
        omega: 4.0
        zeta: 1.0
        unit: "px"
    }

    property real discAngle: 0
    property real ringAngle: 0

    // Runs while playing, AND for a little while after (spin-down settle)
    // -- but never against a collapsed/off-screen card.
    FrameAnimation {
        id: clock
        running: root.onScreen
            && (root.playing || discVelocity.active || ringVelocity.active
                || VisualizerService.spectrumAvailable)
        onTriggered: {
            const dt = Math.min(0.05, frameTime)
            root.discAngle = (root.discAngle + discVelocity.value * dt) % (2 * Math.PI)
            root.ringAngle = (root.ringAngle + ringVelocity.value * dt) % (2 * Math.PI)
            root._stepBars(dt)
            ringCanvas.requestPaint()
        }
    }

    onOnScreenChanged: {
        VisualizerService.setSpectrumVisible("vinyl-disc", root.onScreen)
        if (root.onScreen) ringCanvas.requestPaint()
    }
    Component.onDestruction: VisualizerService.setSpectrumVisible("vinyl-disc", false)

    // ---- per-bar critically-damped smoothing ----------------------------
    // Same closed-form shape as MotionValue's zeta==1 branch, inlined over
    // a plain array so this stays one FrameAnimation driving all 64 bars
    // instead of 64 registered springs.
    property var _barValue: []
    property var _barVelocity: []
    readonly property real _barOmega: 14.0

    Component.onCompleted: {
        VisualizerService.setSpectrumVisible("vinyl-disc", root.onScreen)
        const v = [], vel = []
        for (let i = 0; i < VisualizerService.spectrumBarCount; i++) { v.push(0); vel.push(0) }
        root._barValue = v
        root._barVelocity = vel
    }

    function _stepBars(dt) {
        const n = VisualizerService.spectrumBarCount
        const spectrum = VisualizerService.spectrum
        const w = root._barOmega
        const e = Math.exp(-w * dt)
        const vals = root._barValue
        const vels = root._barVelocity
        for (let i = 0; i < n; i++) {
            const target = spectrum[i] || 0
            const y0 = (vals[i] || 0) - target
            const v0 = vels[i] || 0
            const B = v0 + w * y0
            const y = e * (y0 + B * dt)
            const v = e * (v0 - w * B * dt)
            vals[i] = target + y
            vels[i] = v
        }
    }

    // ---- disc -------------------------------------------------------------
    ShaderEffect {
        id: discShader
        anchors.centerIn: parent
        width: root.discDiameter
        height: root.discDiameter
        fragmentShader: Qt.resolvedUrl("../shaders/vinyl.frag.qsb")

        property real spinAngle: root.discAngle
        property real grooveDensity: 90.0
        property vector3d vinylColor: Qt.vector3d(0.09, 0.09, 0.10)
        property vector3d highlightColor: Qt.vector3d(0.55, 0.53, 0.62)
    }

    // ---- spectrum ring -----------------------------------------------------
    Canvas {
        id: ringCanvas
        anchors.centerIn: parent
        width: root.diameter
        height: root.diameter
        antialiasing: true
        renderStrategy: Canvas.Cooperative

        // Always present, at a calm minimal-baseline radius when idle --
        // never popping in/out with playback, per the brief ("ring bars
        // rest at a minimal baseline" while paused). The whole VinylDisc is
        // already hidden by its caller when there is no player at all.
        opacity: 1

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        // Canvas.onPaint is an imperative callback, not a reactive binding --
        // reading AdaptiveColor.activeFill inside it does NOT make the canvas repaint
        // when the token changes later (eg. the wallpaper-driven palette
        // finishing its async load after this item's first, idle-state
        // paint). Repaint explicitly whenever the stroke colour can change.
        Connections {
            target: Theme
            function onPrimaryChanged(): void { ringCanvas.requestPaint() }
        }
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cx = width / 2, cy = height / 2
            const n = VisualizerService.spectrumBarCount
            // Just outside the disc's own rim, not over its surface.
            const radiusIn = root.discDiameter / 2 + root.ringGap
            ctx.save()
            ctx.translate(cx, cy)
            ctx.rotate(root.ringAngle)
            ctx.lineCap = "round"
            // Same accent token the progress bar (WaveTrack fill) uses, so
            // the ring doesn't introduce a second, unrelated accent colour.
            ctx.strokeStyle = AdaptiveColor.activeFill
            ctx.lineWidth = root.barWidth
            for (let i = 0; i < n; i++) {
                const level = Math.max(0, Math.min(1, root._barValue[i] || 0))
                const len = root.barMinLen + (root.barMaxLen - root.barMinLen) * level
                const angle = (i / n) * 2 * Math.PI - Math.PI / 2
                const cos = Math.cos(angle), sin = Math.sin(angle)
                const x0 = radiusIn * cos, y0 = radiusIn * sin
                const x1 = (radiusIn + len) * cos, y1 = (radiusIn + len) * sin
                ctx.beginPath()
                ctx.moveTo(x0, y0)
                ctx.lineTo(x1, y1)
                ctx.stroke()
            }
            ctx.restore()
        }
    }

    // ---- album art label ----------------------------------------------------
    ClippingRectangle {
        id: label
        anchors.centerIn: parent
        width: root.labelDiameter
        height: root.labelDiameter
        radius: width / 2
        color: Theme.surfaceContainerHigh
        rotation: root.discAngle * 180 / Math.PI

        Image {
            id: art
            anchors.fill: parent
            source: root.artworkSource
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            visible: root.artworkReady
        }

        Text {
            anchors.centerIn: parent
            visible: !root.artworkReady
            text: root.artworkSource.toString().length > 0 ? "󰝚" : "󰎆"
            color: AdaptiveColor.activeFill
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: root.labelDiameter * 0.32
        }

        // A small centre spindle hole -- reads as a real record, not a
        // painted circle.
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(3, root.labelDiameter * 0.045)
            height: width
            radius: width / 2
            color: Theme.surfaceContainer
        }
    }
}
