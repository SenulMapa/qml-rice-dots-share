import QtQuick
import QtQuick.Shapes

/**
 * Squircle -- a rectangle with Apple-style continuous corners.
 *
 * A plain Rectangle radius is a quarter circle, so curvature jumps from zero
 * to 1/r where the edge meets the corner. Here each corner is a short circular
 * arc flanked by two cubic Béziers that ease the curvature in, using Figma's
 * "corner smoothing" construction (smoothing 0.6 = iOS). The curve renderer
 * draws it with analytic anti-aliasing, so the edge stays crisp at any size.
 *
 * The root is a plain Item (implicit size 0x0, like Rectangle) with the Shape
 * as its first child. A Shape root would take its implicit size from its own
 * path, which is computed from the size: a binding loop under any layout.
 */
Item {
    id: root

    property real radius: 16
    property real smoothing: 0.6
    property color color: "white"   // Rectangle's default
    property color borderColor: "transparent"
    property real borderWidth: 0
    // Optional QtQuick.Shapes gradient (LinearGradient etc.); wins over `color`.
    property ShapeGradient fillGradient: null


    // Figma's getPathParamsForCorner, without its preserveSmoothing option:
    // when the corner would outgrow the shape, smoothing gives way first.
    // A Rectangle draws its border inside its bounds, but a stroke is centred
    // on the path. Trace the outline half a border-width in so they match.
    readonly property real inset: borderWidth > 0 ? borderWidth / 2 : 0
    readonly property real pathWidth: Math.max(0, width - 2 * inset)
    readonly property real pathHeight: Math.max(0, height - 2 * inset)

    readonly property var corner: {
        const maxP = Math.min(pathWidth, pathHeight) / 2
        const r = Math.max(0, Math.min(radius - inset, maxP))
        const s = Math.max(0, Math.min(smoothing, r > 0 ? maxP / r - 1 : 0))
        const p = Math.min((1 + s) * r, maxP)
        const rad = deg => deg * Math.PI / 180
        const arcMeasure = 90 * (1 - s)
        const arc = Math.sin(rad(arcMeasure / 2)) * r * Math.SQRT2
        const alpha = (90 - arcMeasure) / 2
        const p3ToP4 = r * Math.tan(rad(alpha / 2))
        const beta = 45 * s
        const c = p3ToP4 * Math.cos(rad(beta))
        const d = c * Math.tan(rad(beta))
        const b = (p - arc - c - d) / 3
        return { r: r, p: p, arc: arc, a: 2 * b, b: b, c: c, d: d }
    }

    readonly property string svgPath: {
        const k = corner, o = inset, w = pathWidth + o, h = pathHeight + o
        const ab = k.a + k.b, abc = k.a + k.b + k.c, bc = k.b + k.c
        const arcTo = (dx, dy) => `a ${k.r} ${k.r} 0 0 1 ${dx} ${dy}`
        return [
            `M ${w - k.p} ${o}`,
            `c ${k.a} 0 ${ab} 0 ${abc} ${k.d}`, arcTo(k.arc, k.arc),
            `c ${k.d} ${k.c} ${k.d} ${bc} ${k.d} ${abc}`,
            `L ${w} ${h - k.p}`,
            `c 0 ${k.a} 0 ${ab} ${-k.d} ${abc}`, arcTo(-k.arc, k.arc),
            `c ${-k.c} ${k.d} ${-bc} ${k.d} ${-abc} ${k.d}`,
            `L ${o + k.p} ${h}`,
            `c ${-k.a} 0 ${-ab} 0 ${-abc} ${-k.d}`, arcTo(-k.arc, -k.arc),
            `c ${-k.d} ${-k.c} ${-k.d} ${-bc} ${-k.d} ${-abc}`,
            `L ${o} ${o + k.p}`,
            `c 0 ${-k.a} 0 ${-ab} ${k.d} ${-abc}`, arcTo(k.arc, -k.arc),
            `c ${k.c} ${-k.d} ${bc} ${-k.d} ${abc} ${-k.d}`,
            "Z",
        ].join(" ")
    }

    Shape {
        // Explicit size, never anchors.fill: the Shape's own implicit size
        // must not feed back into the root.
        width: root.width
        height: root.height
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            fillGradient: root.fillGradient
            strokeColor: root.borderWidth > 0 ? root.borderColor : "transparent"
            strokeWidth: root.borderWidth
            PathSvg { path: root.svgPath }
        }
    }
}
