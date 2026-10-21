import QtQuick
import "../core"
import "../services"

/**
 * LevelTrack -- a filled bar tracking a 0..1 value. The fill is spring-
 * driven (core/MotionValue.qml), not a duration Animation: a value that
 * updates again mid-tween (a live CPU/memory reading, easily once a
 * second) retargets the same spring instead of restarting a clip, so a
 * fast-changing metric never looks like it's stepping.
 */
Item {
    id: root

    property real value: 0
    // Glass redesign: level fills are the glass text colour (white on dark
    // glass), like the control centre's sliders, not an accent.
    property color accent: AdaptiveColor.glassText
    // Overridable so island/IslandOSD.qml can use the Phase A
    // Theme.surfaceContainerHigh track colour without changing the default
    // for this component's other callers (Dashboard/Battery/SystemMetric).
    property color trackColor: Qt.alpha(AdaptiveColor.glassTextDim, 0.16)

    implicitHeight: 6

    MotionValue {
        id: fill
        unit: "ratio"
        omega: Motion.omegaDefault
        zeta: Motion.zetaDefault
        target: Math.max(0, Math.min(1, root.value))
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.trackColor
    }

    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, fill.value))
        height: parent.height
        radius: height / 2
        color: root.accent

        Behavior on color { ColorAnimation { duration: Animations.fast } }
    }
}
