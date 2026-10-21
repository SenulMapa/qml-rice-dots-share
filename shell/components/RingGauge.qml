import QtQuick
import "../core"
import "../services"

/**
 * RingGauge -- a stroked circular progress ring for a 0..1 value. No fill,
 * no card behind it (matches the shell's no-bento rule); it's a data glyph,
 * not a container. The sweep is spring-driven (core/MotionValue.qml), so a
 * metric that updates again mid-tween (CPU/memory polling once a second)
 * retargets smoothly instead of snapping or restarting a clip.
 */
Item {
    id: root

    property real value: 0
    property color accent: AdaptiveColor.activeFill
    property color trackColor: Qt.alpha(AdaptiveColor.glassTextDim, 0.16)
    property real thickness: Theme.u(0.07)

    implicitWidth: Theme.u(0.8)
    implicitHeight: Theme.u(0.8)

    MotionValue {
        id: sweep
        unit: "ratio"
        omega: Motion.omegaDefault
        zeta: Motion.zetaDefault
        target: Math.max(0, Math.min(1, root.value))
        onValueChanged: canvas.requestPaint()
    }
    onAccentChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = root.thickness
            const cx = width / 2
            const cy = height / 2
            const r = Math.min(width, height) / 2 - w / 2
            if (r <= 0)
                return

            ctx.lineCap = "round"
            ctx.lineWidth = w

            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.strokeStyle = root.trackColor
            ctx.stroke()

            const sweptAngle = sweep.value * Math.PI * 2
            if (sweptAngle > 0.001) {
                ctx.beginPath()
                ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + sweptAngle)
                ctx.strokeStyle = root.accent
                ctx.stroke()
            }
        }
    }
}
