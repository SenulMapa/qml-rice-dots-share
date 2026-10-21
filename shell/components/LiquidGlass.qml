pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects

/**
 * LiquidGlass -- renders its children's silhouette as frosted glass over
 * `backgroundItem` (shaders/liquid-glass.frag): a blurred, brightened view of
 * what is behind it, with a thin refracting, light-catching rim.
 *
 *   LiquidGlass {
 *       backgroundItem: wallpaper      // must NOT contain this item
 *       width: 700; height: 260
 *       Text { anchors.centerIn: parent; text: "24:00"; color: "white" }
 *   }
 *
 * Children are only a mask: draw them opaque white, their colour is ignored.
 * Leave a few px of padding around them inside this item so the rim's height
 * map is not clipped.
 *
 * The background is captured as a sourceRect crop of backgroundItem at this
 * item's position, so the two must share a coordinate space that does not
 * move independently (true for a full-screen surface). backgroundItem must not
 * be an ancestor of this item -- the glass would sample itself.
 */
Item {
    id: root

    required property Item backgroundItem

    default property alias shapeData: shapeLayer.data

    property real frostRadius: 48   // background blur, px (MultiEffect blurMax)
    property real saturation: 0.35  // frosted layer saturation boost
    property real milk: 0.22        // lift toward white
    property real strength: 10      // rim bend, px
    property real edgeRadius: 6     // rim height-map blur, px
    property real rimWidth: 0.4
    property real rim: 0.85
    property color tint: Qt.rgba(1, 1, 1, 0)
    property real outline: 0         // lit edge line, 0..1 (replaces flat borders)
    property real outlineWidth: 1.6  // px
    // Set for pills/circles (the shape is a rounded rect of this radius) so
    // the outline is drawn from an exact SDF; -1 = arbitrary shape, no line.
    property real shapeRadius: -1
    // Where the light comes from (screen space, y down). The 3D clock turns
    // this against its tilt so the highlight slides across the glass.
    property vector2d lightDir: Qt.vector2d(-0.55, -0.85)

    // Read x/y/size (and the background's size, which changes whenever the
    // screen does and so moves every parent) so the crop follows layout;
    // mapToItem itself is not a reactive dependency.
    readonly property rect _crop: {
        void [root.x, root.y, root.width, root.height, root.parent,
              root.backgroundItem.width, root.backgroundItem.height];
        const p = root.mapToItem(root.backgroundItem, 0, 0);
        return Qt.rect(p.x, p.y, root.width, root.height);
    }

    ShaderEffectSource {
        id: bgSource
        visible: false
        sourceItem: root.backgroundItem
        sourceRect: root._crop
        live: true
        hideSource: false
    }

    MultiEffect {
        id: frostFx
        width: root.width
        height: root.height
        source: bgSource
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: Math.round(root.frostRadius)
        saturation: root.saturation
    }

    ShaderEffectSource {
        id: frostSource
        visible: false
        sourceItem: frostFx
        hideSource: true
        live: true
    }

    Item {
        id: shapeLayer
        width: root.width
        height: root.height
    }

    ShaderEffectSource {
        id: sharpSource
        visible: false
        sourceItem: shapeLayer
        hideSource: true
        live: true
    }

    MultiEffect {
        id: softShape
        width: root.width
        height: root.height
        source: sharpSource
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: Math.round(root.edgeRadius)
    }

    ShaderEffectSource {
        id: softSource
        visible: false
        sourceItem: softShape
        hideSource: true
        live: true
    }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl("../shaders/liquid-glass.frag.qsb")

        property vector2d texel: Qt.vector2d(1 / Math.max(1, root.width), 1 / Math.max(1, root.height))
        property real strength: root.strength
        property real milk: root.milk
        property real rim: root.rim
        property real rimWidth: root.rimWidth
        property color tint: root.tint
        property real outline: root.outline
        property real lineWidth: root.outlineWidth
        property real radius: root.shapeRadius
        property vector2d lightDir: root.lightDir

        property variant source: bgSource
        property variant frosted: frostSource
        property variant sharp: sharpSource
        property variant soft: softSource
    }
}
