import QtQuick

/**
 * TahoeGlass -- a macOS 26 "Tahoe" liquid-glass surface (shaders/tahoe-glass.frag).
 *
 * The item is the glass shape itself. The shader overflows it by `_pad` px on
 * every side so the drop shadow can fall outside the shape, like GlassMaterial.
 * Put content on top as usual.
 *
 *   Item {
 *       TahoeGlass { anchors.fill: parent; radius: 26 }
 *   }
 *
 * It paints a light white body (never a dark fill). The blur is the
 * compositor's job: the layer needs a blur rule (hypr/hyprland/glass.lua).
 * Reusable for menus, OSDs and notification banners: every look value is a
 * property, so a caller only overrides what differs.
 */
Item {
    id: root

    property real radius: 18
    property real tintAlpha: 0.12      // white body alpha
    property real rimTop: 0.55         // specular rim on the edge facing the light
    property real rimSide: 0.15        // specular rim on sides and bottom
    property real innerGlow: 0.08      // inner glow at the edge, fades over ~6 px
    property real lightAngle: -Math.PI / 2   // direction toward the light; default from above
    property real shadowAlpha: 0.25    // black drop shadow peak
    property real shadowBlur: 24       // shadow falloff, px
    property real shadowY: 6           // shadow y offset, px

    readonly property real _pad: Math.ceil(shadowBlur + Math.abs(shadowY) + 2)

    ShaderEffect {
        x: -root._pad; y: -root._pad
        width: root.width + 2 * root._pad
        height: root.height + 2 * root._pad
        fragmentShader: Qt.resolvedUrl("../shaders/tahoe-glass.frag.qsb")

        property size size: Qt.size(width, height)
        property real pad: root._pad
        property real radius: root.radius
        property real tintAlpha: root.tintAlpha
        property real rimTop: root.rimTop
        property real rimSide: root.rimSide
        property real innerGlow: root.innerGlow
        property real lightAngle: root.lightAngle
        property real shadowAlpha: root.shadowAlpha
        property real shadowBlur: root.shadowBlur
        property real shadowY: root.shadowY
    }
}
