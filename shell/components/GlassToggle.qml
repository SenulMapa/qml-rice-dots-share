import QtQuick
import "../core"
import "../services"

/**
 * GlassToggle -- a round quick toggle for glass panels (glass redesign
 * Phase 3). Off: clear glass, glass-text glyph. On: an opaque
 * AdaptiveColor.activeFill disc (a lighter, brighter shade of the
 * wallpaper accent) that blooms out from the centre, glyph switching to
 * the computed on-fill colour and to the filled Material Symbols variant.
 * Optional label underneath in small type.
 *
 * Right-click / long-press emits `secondary` (open the detail page).
 */
Item {
    id: root

    property bool on: false
    property string icon: ""          // Material Symbols Rounded name (glass)
    property string iconName: ""      // Lucide name, drawn by Icon when ink is on
    property string label: ""
    // Ink: a 56px circle (showcase dashboard), sized here so callers keep
    // their explicit size when ink is off.
    property real size: Config.appearance.ink ? 56 : 52
    signal activated()
    signal secondary()

    implicitWidth: Math.max(size, labelText.implicitWidth)
    implicitHeight: size + (label.length > 0 ? labelText.implicitHeight + 6 : 0)

    Item {
        id: disc
        width: root.size; height: root.size
        anchors.horizontalCenter: parent.horizontalCenter
        scale: area.pressed ? 0.92 : (area.containsMouse ? 1.04 : 1)
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        GlassMaterial {
            anchors.fill: parent
            radius: width / 2
            shadow: 0.07
            shadowSpread: 10
            rimWidth: 5
            tintAlpha: area.containsMouse ? 0.32 : 0.24
            inkFill: area.containsMouse ? Theme.inkRaised2 : Theme.inkRaised
        }

        Rectangle {
            id: bloom
            anchors.fill: parent
            radius: width / 2
            color: Config.appearance.ink ? Theme.fillOn : AdaptiveColor.activeFill
            opacity: root.on ? 1 : 0
            scale: root.on ? 1 : 0.55
            Behavior on opacity { NumberAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        }

        Icon {
            anchors.centerIn: parent
            visible: Config.appearance.ink && root.iconName.length > 0
            name: root.iconName
            size: 22
            color: root.on ? Theme.glyphOn : Theme.t1
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        Text {
            anchors.centerIn: parent
            visible: !(Config.appearance.ink && root.iconName.length > 0)
            text: root.icon
            font.family: "Material Symbols Rounded"
            font.pixelSize: Config.appearance.ink ? 18 : Math.round(root.size * 0.46)
            font.variableAxes: ({ "FILL": root.on ? 1 : 0 })
            color: Config.appearance.ink
                ? (root.on ? Theme.glyphOn : Theme.t1)
                : (root.on ? AdaptiveColor.activeFillText : AdaptiveColor.glassText)
            Behavior on color { ColorAnimation { duration: 180 } }
        }
    }

    Text {
        id: labelText
        anchors.top: disc.bottom
        anchors.topMargin: Config.appearance.ink ? 8 : 6
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.label.length > 0
        text: root.label
        font.family: Theme.fontUi
        font.pixelSize: Config.appearance.ink ? 12 : 11
        font.weight: Font.Medium
        color: Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim
    }

    MouseArea {
        id: area
        anchors.fill: disc
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        pressAndHoldInterval: 450
        onClicked: mouse => mouse.button === Qt.RightButton ? root.secondary() : root.activated()
        onPressAndHold: root.secondary()
    }
}
