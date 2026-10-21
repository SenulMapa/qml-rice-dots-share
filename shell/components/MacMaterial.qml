import QtQuick
import QtQuick.Shapes

/**
 * MacMaterial -- macOS Sequoia dark-mode floating material, shared by the
 * dock label, dock/desktop context menus and (later) any non-island popup.
 *
 * A translucent dark fill over Hyprland's layer blur (the layer's namespace
 * needs a blur rule in hypr/hyprland/glass.lua; keep fill alpha above that
 * rule's ignore_alpha), a 1px light rim, a faint top sheen and a soft large
 * shadow drawn outside the box (it never affects layout).
 */
Item {
    id: root

    property real radius: 10
    property color fill: Qt.rgba(0.17, 0.17, 0.18, 0.72)
    property color rim: Qt.rgba(1, 1, 1, 0.12)
    property real sheen: 0.07
    property bool shadowOn: true
    property real shadowSpread: 22
    property real shadowOpacity: 0.45
    property real shadowYOffset: 8

    MacShadow {
        visible: root.shadowOn
        anchors.fill: parent
        radius: root.radius
        spread: root.shadowSpread
        shadowOpacity: root.shadowOpacity
        yOffset: root.shadowYOffset
    }

    Squircle {
        id: body
        anchors.fill: parent
        radius: root.radius
        color: root.fill
        borderWidth: 1
        borderColor: root.rim
        Squircle {
            id: sheenLayer
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, root.radius - 1)
            color: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: sheenLayer.height
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, root.sheen) }
                GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
    }
}
