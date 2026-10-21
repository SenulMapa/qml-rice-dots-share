import QtQuick
import "../components"
import "../core"

/**
 * TahoeSurface -- the Tahoe ("mac") material wrapper every mac surface sits
 * on. Body and rim are components/TahoeGlass.qml (shaders/tahoe-glass.frag),
 * with the values from MacTokens section 4. Children are drawn on top.
 *
 *   PanelWindow {
 *       WlrLayershell.namespace: surface.layerNamespace
 *       TahoeSurface { id: surface; kind: "banner"; anchors.fill: parent; radius: MacTokens.s(MacTokens.bannerRadius) }
 *   }
 *
 * Layer namespace: `qml-rice:mac-<kind>`. hypr/hyprland/glass.lua blurs the
 * whole `^qml-rice:mac-.*$` family, so a new kind needs no compositor change.
 */
Item {
    id: root

    // Names the layer: `kind` "banner" gives namespace "qml-rice:mac-banner".
    property string kind: "surface"
    readonly property string layerNamespace: "qml-rice:mac-" + kind

    property real radius: MacTokens.s(MacTokens.spotlightRadius)
    property real tintAlpha: MacTokens.surfaceTintAlpha
    // With the compositor glass plugin, QML draws no rim, glow or shadow: each
    // of these would add alpha outside the body and get frosted as a halo.
    property real rimTop: MacTokens.compositorGlass ? 0 : MacTokens.surfaceRimTop
    property real rimSide: MacTokens.compositorGlass ? 0 : MacTokens.surfaceRimSide
    property real innerGlow: MacTokens.compositorGlass ? 0 : MacTokens.surfaceInnerGlow
    property real shadowAlpha: MacTokens.compositorGlass ? 0 : MacTokens.surfaceShadowAlpha
    property real shadowBlur: MacTokens.compositorGlass ? 0 : MacTokens.s(MacTokens.surfaceShadowBlur)
    property real shadowY: MacTokens.compositorGlass ? 0 : MacTokens.s(MacTokens.surfaceShadowY)
    // Optional tint over the glass body (modules, widgets). Transparent by default.
    property color fill: "transparent"

    // Content goes on top of the glass.
    default property alias content: contents.data

    // Ink mode: opaque ink and a hairline rim, no glass (see MacTokens.ink).
    Squircle {
        anchors.fill: parent
        visible: MacTokens.ink
        radius: root.radius
        color: Theme.ink
        borderWidth: 1
        borderColor: Theme.inkRim
    }

    TahoeGlass {
        visible: !MacTokens.ink
        anchors.fill: parent
        radius: root.radius
        tintAlpha: root.tintAlpha
        rimTop: root.rimTop
        rimSide: root.rimSide
        innerGlow: root.innerGlow
        shadowAlpha: root.shadowAlpha
        shadowBlur: root.shadowBlur
        shadowY: root.shadowY
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.fill
        // The light fills belong to the glass look; ink surfaces stay ink.
        visible: !MacTokens.ink && root.fill.a > 0
    }

    Item {
        id: contents
        anchors.fill: parent
    }
}
