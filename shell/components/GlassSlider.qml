import QtQuick
import "../core"
import "../services"

/**
 * GlassSlider -- a thick capsule slider for glass panels (glass redesign
 * Phase 3): glass track, solid white fill, the icon riding inside the fill
 * (dark on white). Drag anywhere, click to jump, scroll for 5% steps.
 * The fill never shrinks below a circle, so the icon always has room.
 *
 * `value` (0..1) is the source of truth from the caller's service; while
 * dragging the slider shows the pointer's value and emits `moved` (the
 * caller writes it back), so a slow service round-trip never makes the
 * fill lag the finger.
 */
Item {
    id: root

    property real value: 0
    property string icon: ""
    property string iconName: ""      // Lucide name, drawn by Icon when ink is on
    property bool available: true
    signal moved(real value)

    implicitHeight: Config.appearance.ink ? 44 : 40

    property bool _dragging: false
    property real _dragValue: 0
    readonly property real _shown: _dragging ? _dragValue : Math.max(0, Math.min(1, value))
    property real _anim: _shown
    Behavior on _anim {
        enabled: !root._dragging
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    opacity: available ? 1 : 0.45

    GlassMaterial {
        anchors.fill: parent
        radius: height / 2
        shadow: 0.06
        shadowSpread: 10
        rimWidth: 5
        tintAlpha: 0.2
    }

    Rectangle {
        id: fill
        height: parent.height
        width: Math.max(height, root._anim * root.width)
        radius: height / 2
        color: Config.appearance.ink ? Theme.fillOn : "white"
        opacity: Config.appearance.ink ? 1 : 0.94
    }

    Icon {
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        visible: Config.appearance.ink && root.iconName.length > 0
        name: root.iconName
        size: 18
        color: Theme.glyphOn
    }

    Text {
        x: Config.appearance.ink ? 16 : Math.round((root.height - width) / 2)
        visible: !(Config.appearance.ink && root.iconName.length > 0)
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        font.family: "Material Symbols Rounded"
        font.pixelSize: Config.appearance.ink ? 18 : Math.round(root.height * 0.5)
        font.variableAxes: ({ "FILL": 1 })
        color: Config.appearance.ink ? Theme.glyphOn : "#1c1c1e"
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.available
        cursorShape: Qt.PointingHandCursor
        function at(x) { return Math.max(0, Math.min(1, x / width)); }
        onPressed: mouse => { root._dragValue = at(mouse.x); root._dragging = true; root.moved(root._dragValue); }
        onPositionChanged: mouse => { if (pressed) { root._dragValue = at(mouse.x); root.moved(root._dragValue); } }
        onReleased: root._dragging = false
        onCanceled: root._dragging = false
        onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
