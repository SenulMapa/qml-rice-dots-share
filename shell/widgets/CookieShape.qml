// DEPRECATED: Old widget system. Use desktop/ instead
import QtQuick
import QtQuick.Shapes

/**
 * CookieShape -- a Material-3-style "cookie"/scallop blob: r(theta) =
 * R*(1 + amplitude*cos(sides*theta)), rasterised once into an SVG path
 * string and handed to a single static ShapePath. No Canvas, no per-frame
 * repaint, no morph animation library (unlike end4-ii's shapes/ port,
 * which recomputes a bezier morph every frame via Canvas.requestPaint --
 * too expensive for the UHD 620/10W idle budget this shell targets).
 * `_svgPath` only recomputes when width/height/sides/amplitude actually
 * change, which for a static desktop widget is essentially never after
 * layout settles.
 */
Shape {
    id: root

    required property int sides
    property real amplitude: 0.14
    property color fillColor: "white"
    property color strokeColor: "transparent"
    property real strokeWidth: 0

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        fillColor: root.fillColor
        strokeColor: root.strokeColor
        strokeWidth: root.strokeWidth
        PathSvg { path: root._svgPath }
    }

    readonly property string _svgPath: root.buildPath(
        root.sides, root.amplitude, root.width, root.height)

    function buildPath(n: int, amp: real, w: real, h: real): string {
        if (w <= 0 || h <= 0 || n < 3)
            return ""
        const cx = w / 2, cy = h / 2
        const R = Math.min(w, h) / 2 * 0.98
        const steps = Math.max(72, n * 12)
        const parts = []
        for (let i = 0; i <= steps; i++) {
            const t = (i / steps) * Math.PI * 2
            const r = R * (1 + amp * Math.cos(n * t))
            const x = cx + r * Math.cos(t)
            const y = cy + r * Math.sin(t)
            parts.push((i === 0 ? "M" : "L") + x.toFixed(2) + "," + y.toFixed(2))
        }
        parts.push("Z")
        return parts.join(" ")
    }
}
