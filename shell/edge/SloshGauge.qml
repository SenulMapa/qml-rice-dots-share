import QtQuick
import "../core"
import "../services"

/**
 * SloshGauge -- a liquid-in-a-tank volume readout. Port of React Bits'
 * "SloshGauge": a damped-spring liquid column with a wall bounce at each
 * end and a velocity-driven surface tilt, all evaluated with a fixed
 * substep so the physics is deterministic regardless of frame rate (see
 * the header comment on the integrator below for the exact recurrence --
 * it's checked against a Python re-implementation in
 * /tmp/edge-volume/integrator_check.py during development, see HANDOVER).
 *
 * Drawn entirely in one Canvas (tank + liquid + tilt + tick marks) --
 * deliberately not QtQuick.Shapes/MultiEffect, matching this shell's
 * existing gauges (components/RingGauge.qml) and its measured GPU-cost
 * discipline (visualizer/EdgeVisualizer.qml's header comment). The
 * readout text is a genuinely separate pair of Text items: one drawn
 * normally, one clipped to the liquid's current pixel height, so the
 * percentage's colour flips at the exact instant the surface crosses it.
 */
Item {
    id: root

    // ---- public API ------------------------------------------------
    property real level: 0            // target fill, 0..100 (== "L")
    property bool muted: false
    // Which screen edge this gauge is docked to -- decides which side the
    // tick marks sit on (always the side facing AWAY from that edge).
    property string dockEdge: "left"

    property real viscosity: 0.15
    property real tilt: 0.45
    property real splash: 0.42

    // The panel behind this gauge (edge/EdgePanelShape.qml) IS the tank now
    // -- no separate background fill, or it reads as a box inside a box
    // (owner feedback). The liquid just fills an inset rounded area instead.
    property real inset: Theme.u(0.15)

    // Matches edge/EdgePanelShape.qml's own geometry (same outer radius,
    // same independently-clamping-to-0 edge fillets), just inset and
    // clipped via Canvas 2D instead of a second Shape -- a GPU mask
    // (QtQuick.Effects MultiEffect maskSource) was tried first and dropped:
    // it did not reliably clip in this shell's actual render pipeline, and
    // this header's own "not QtQuick.Shapes/MultiEffect" rule was right
    // for exactly this reason. Canvas clip() with a hand-built path (same
    // angle math as EdgePanelShape, ported to ctx.arc) is what every other
    // gauge in this file already uses.
    property real cornerRadius: Theme.u(0.45)
    property real topFillet: cornerRadius
    property real bottomFillet: cornerRadius

    implicitWidth: Theme.u(1.6)
    implicitHeight: Theme.u(4.2)

    readonly property color tankColor: Theme.surfaceContainer
    readonly property color liquidColor: root.muted
        ? Qt.alpha(AdaptiveColor.glassTextDim, 0.55) : AdaptiveColor.activeFill
    readonly property color textOnTank: AdaptiveColor.glassText
    readonly property color textOnLiquid: root.muted ? AdaptiveColor.glassText : AdaptiveColor.activeFillText

    // ---- physics constants, derived from viscosity (ported verbatim) --
    readonly property real _k: 1224 - 1044 * root.viscosity
    readonly property real _zeta: 0.26 - 0.17 * root.viscosity
    readonly property real _c: 2 * root._zeta * Math.sqrt(root._k)
    readonly property real _H: 1 / 120

    // ---- integrator state -------------------------------------------
    // Plain values, NOT bindings to level/height: they're the physics
    // state, only ever advanced by FrameAnimation's substep loop below
    // (initial snapshot taken once in Component.onCompleted). If these
    // were left as `property real _x: root.level`-style default bindings,
    // a `level` change arriving before the first substep ever ran would
    // silently drag _x along with it (QML re-evaluating the binding) and
    // the "jump" would never actually integrate from the old value.
    // (4 Oct 2026, perf pass) `level` can exceed 100 (volumePercent hits
    // 128%) or go below 0, but the integrator clamps _x to [0,100], so
    // comparing against raw `level` meant atRest never became true and the
    // FrameAnimation ticked at 60fps forever. Physics targets the clamped
    // value; the text readout still shows the real `level`.
    readonly property real _target: Math.max(0, Math.min(100, root.level))
    property real _x: 0               // current animated fill, 0..100
    property real _v: 0               // velocity
    property real _accum: 0           // leftover substep time
    // Current liquid top in LOCAL pixels (0 = top of tank), updated once
    // per substep batch -- drives both the canvas paint and the readout
    // clip below.
    property real _topY: 0

    // Liquid top mapped across the INSET inner area (inset..height-inset),
    // not the full height -- the tank background is gone (the panel behind
    // is the tank now), but the liquid still needs to sit inside the same
    // inset margin the panel reserves for it. Purely a rendering-space
    // remap; the integrator above (_x/_v) is untouched.
    function _topYFor(x) {
        const innerH = Math.max(0, root.height - 2 * root.inset)
        return root.inset + innerH * (1 - x / 100)
    }

    Component.onCompleted: {
        _x = root._target
        _v = 0
        _accum = 0
        _topY = root._topYFor(_x)
    }

    readonly property bool atRest:
        Math.abs(root._target - root._x) < 0.05 && Math.abs(root._v) < 2

    // Only steps while genuinely unsettled -- matches Motion's own
    // "sleep at rest" discipline (core/Motion.qml header comment).
    FrameAnimation {
        id: frame
        running: !root.atRest
        onTriggered: {
            let dt = Math.min(0.05, frameTime > 0 ? frameTime : root._H)
            root._accum += dt
            // Fixed-step accumulator: always advance in exact H-second
            // substeps regardless of the host frame rate, so the same
            // sequence of substeps runs whether this is a 60Hz laptop
            // panel or a 240Hz desktop monitor.
            while (root._accum >= root._H) {
                root._accum -= root._H
                let v = root._v
                let x = root._x
                v = v * Math.exp(-root._c * root._H) + root._k * (root._target - x) * root._H
                x += v * root._H
                if (x < 0) {
                    x = 0
                    v = -v * root.splash
                } else if (x > 100) {
                    x = 100
                    v = -v * root.splash
                }
                root._x = x
                root._v = v
            }
            if (root.atRest) {
                root._x = root._target
                root._v = 0
                root._accum = 0
            }
            root._topY = root._topYFor(root._x)
            canvas.requestPaint()
        }
    }

    // level/geometry can change while at rest (e.g. a fresh scroll while
    // the gauge was parked) -- atRest recomputes reactively from _x/level,
    // which flips `running` back on automatically; this just keeps the
    // paint honest the instant those change without waiting a frame.
    onLevelChanged: canvas.requestPaint()
    onMutedChanged: canvas.requestPaint()
    onWidthChanged: { root._topY = root._topYFor(root._x); canvas.requestPaint() }
    onHeightChanged: { root._topY = root._topYFor(root._x); canvas.requestPaint() }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        antialiasing: true

        // Canvas never auto-paints on first show -- without this, a grab
        // taken before the FrameAnimation's first tick (e.g. this
        // component's very first frame) sees a blank canvas even though
        // _x/_topY already hold correct initial values.
        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = root.width
            const h = root.height
            const inset = root.inset
            const iw = w - 2 * inset
            const ih = h - 2 * inset
            const r = Math.max(0, root.cornerRadius - inset)
            const rTop = Math.max(0, root.topFillet - inset)
            const rBottom = Math.max(0, root.bottomFillet - inset)
            if (w <= 0 || h <= 0 || iw <= 0 || ih <= 0)
                return

            // No background fill here -- the panel behind (EdgePanelShape)
            // IS the tank now (owner feedback: no box inside a box). Only
            // clip the liquid to the inset inner area, in the SAME flared
            // shape as the panel (flush-edge + concave fillets), so the
            // liquid never spills past the panel's own silhouette.
            ctx.save()
            _edgeFlarePath(ctx, inset, inset, iw, ih, root.dockEdge, r, rTop, rBottom)
            ctx.clip()

            // Surface lean from velocity: th in DEGREES, clamped to ±30,
            // then converted to a pixel rise/fall over half the inner width.
            const thDeg = Math.max(-30, Math.min(30, root.tilt * root._v * 0.07))
            const lean = Math.tan(thDeg * Math.PI / 180) * (iw / 2)
            const topY = root._topY
            const leftY = topY + lean
            const rightY = topY - lean

            ctx.beginPath()
            ctx.moveTo(inset, inset + ih)
            ctx.lineTo(inset, leftY)
            ctx.lineTo(inset + iw, rightY)
            ctx.lineTo(inset + iw, inset + ih)
            ctx.closePath()
            ctx.fillStyle = root.liquidColor
            ctx.fill()

            ctx.restore()

            // Tick marks on the side facing AWAY from the docked edge --
            // docked left => ticks on the right (interior) side, and vice
            // versa. Four evenly spaced marks, not touching the corners.
            const tickOnRight = root.dockEdge === "left"
            const tickLen = Theme.u(0.16)
            const tickInset = Theme.u(0.07)
            ctx.strokeStyle = Qt.alpha(root.textOnTank, 0.35)
            ctx.lineWidth = Math.max(1, Theme.u(0.02))
            for (let i = 1; i <= 4; i++) {
                const ty = inset + ih * (i / 5)
                const tx = tickOnRight ? (inset + iw) - tickInset - tickLen : inset + tickInset
                ctx.beginPath()
                ctx.moveTo(tx, ty)
                ctx.lineTo(tx + tickLen, ty)
                ctx.stroke()
            }
        }

        // Same contour as edge/EdgePanelShape.qml -- flush against the
        // `dockEdge` side, concave fillets (radius rTop/rBottom) where it
        // meets that edge, convex corners (radius r) on the far side. `dir`/
        // `edgeX` are the mirror; every arc's angles are computed the same
        // atan2 way EdgePanelShape uses (dx = dir*(k-ck) IS the real x
        // delta, since px() is affine in k with slope `dir`), so this stays
        // a straight port rather than a second hand-derived geometry.
        function _edgeFlarePath(ctx, x, y, w, h, dockEdge, r, rTop, rBottom) {
            const dir = dockEdge === "left" ? 1 : -1
            const edgeX = dockEdge === "left" ? x : x + w
            function px(k) { return edgeX + dir * k }
            function ang(dx, dy) { return Math.atan2(dy, dx) }
            function sweep(a0, a1) {
                let d = a1 - a0
                while (d > Math.PI) d -= 2 * Math.PI
                while (d <= -Math.PI) d += 2 * Math.PI
                return d
            }
            function arcTo(cx, cy, radius, a0, a1) {
                const s = sweep(a0, a1)
                ctx.arc(cx, cy, radius, a0, a0 + s, s < 0)
            }

            r = Math.max(0.01, Math.min(r, w, h / 2))
            rTop = Math.max(0.01, Math.min(rTop, w, h / 2))
            rBottom = Math.max(0.01, Math.min(rBottom, w, h / 2))

            ctx.beginPath()
            ctx.moveTo(px(w - r), y)
            ctx.lineTo(px(rTop), y)
            arcTo(px(0), y, rTop,
                ang(dir * rTop, 0), ang(0, rTop))
            ctx.lineTo(px(0), y + h - rBottom)
            arcTo(px(0), y + h, rBottom,
                ang(0, -rBottom), ang(dir * rBottom, 0))
            ctx.lineTo(px(w - r), y + h)
            arcTo(px(w - r), y + h - r, r,
                ang(0, r), ang(dir * r, 0))
            ctx.lineTo(px(w), y + r)
            arcTo(px(w - r), y + r, r,
                ang(dir * r, 0), ang(0, -r))
            ctx.closePath()
        }
    }

    readonly property string _readoutText: root.muted ? "MUTE" : Math.round(root.level) + "%"

    Text {
        id: readoutBase
        y: root.height - Theme.u(0.95)
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        text: root._readoutText
        color: root.textOnTank
        font.family: Config.appearance.monoFontFamily
        font.pixelSize: Theme.u(0.34)
        font.weight: Font.DemiBold
    }

    // Clipped to exactly the liquid's current pixel extent -- the second
    // copy of the SAME text, in the contrast colour, only visible where the
    // liquid actually covers it. This is the "colour flips at the surface"
    // effect, not a gradient or an opacity trick.
    Item {
        id: liquidClip
        x: 0
        y: root._topY
        width: root.width
        height: Math.max(0, (root.height - root.inset) - root._topY)
        clip: true

        Text {
            // Same on-screen position as readoutBase, expressed relative
            // to liquidClip's own (moving) origin -- explicit maths, no
            // anchors, since this one genuinely moves every substep.
            y: readoutBase.y - liquidClip.y
            width: root.width
            horizontalAlignment: Text.AlignHCenter
            text: root._readoutText
            color: root.textOnLiquid
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: Theme.u(0.34)
            font.weight: Font.DemiBold
        }
    }
}
