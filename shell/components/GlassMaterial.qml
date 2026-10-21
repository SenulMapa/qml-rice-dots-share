import QtQuick
import "../core"
import "../services"

/**
 * GlassMaterial -- the one glass surface for every non-blob panel/control
 * (shaders/glass-material.frag; spec 2026-10-06-glass-redesign-design.md).
 *
 * Fill a control or panel with it and put content on top:
 *
 *   Item {
 *       GlassMaterial { anchors.fill: parent; radius: height / 2 }
 *       Text { ... color: AdaptiveColor.glassText }
 *   }
 *
 * It never paints an opaque or dark base: the tint is near-clear (alpha
 * ~0.24) and Hyprland blurs the real backdrop behind it (the layer needs the
 * glass layer rule). The shadow is drawn outside this item's bounds, so it
 * does not affect layout.
 *
 * `active` turns it into an "on" control: an opaque fill from AdaptiveColor
 * (a lighter, brighter shade of the wallpaper accent), animated by the
 * caller's Behavior if wanted.
 */
Item {
    id: root

    property real radius: 18
    property color tint: AdaptiveColor.glassTint
    property real tintAlpha: 0.24
    property real rim: 0.55
    property real rimWidth: 6
    property real outline: 0.5
    property real outlineWidth: 1.4
    property real shadow: 0.14
    property real shadowSpread: 18
    property bool active: false
    property color activeColor: AdaptiveColor.activeFill
    // Ink (Config.appearance.ink): no glass. A flat opaque fill instead.
    // `inkFill` is the resting colour; `active` paints Theme.fillOn.
    property color inkFill: Theme.inkRaised

    readonly property real _pad: Math.ceil(shadowSpread + 2)

    Squircle {
        visible: Config.appearance.ink
        anchors.fill: parent
        radius: root.radius
        color: root.active ? Theme.fillOn : root.inkFill
        Behavior on color { ColorAnimation { duration: Theme.microMs } }
    }

    ShaderEffect {
        visible: !Config.appearance.ink
        x: -root._pad; y: -root._pad
        width: root.width + 2 * root._pad
        height: root.height + 2 * root._pad
        fragmentShader: Qt.resolvedUrl("../shaders/glass-material.frag.qsb")

        property size size: Qt.size(width, height)
        property real pad: root._pad
        property real radius: root.radius
        property color tint: root.active
            ? Qt.rgba(root.activeColor.r, root.activeColor.g, root.activeColor.b, 1)
            : Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.tintAlpha)
        property real rim: root.active ? root.rim * 0.6 : root.rim
        property real rimWidth: root.rimWidth
        property real outline: root.outline
        property real outlineWidth: root.outlineWidth
        property real shadow: root.shadow
        property real shadowSpread: root.shadowSpread
    }
}
