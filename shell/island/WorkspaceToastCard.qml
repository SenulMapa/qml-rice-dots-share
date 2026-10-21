import QtQuick
import "../core"
import "../services"

/**
 * WorkspaceToastCard -- the "Workspace N" pill shown by
 * island/WorkspaceToast.qml. Flat, borderless, calm: no drop shadow, no
 * outline, just a soft translucent fill behind Instrument Serif text.
 *
 * TIMELINE is a fixed 5000ms total, plain duration-based (Behavior/
 * SequentialAnimation), not a MotionValue spring -- this is a scripted OSD
 * reveal with an exact runtime the spec calls out (5s), not a
 * physically-interrupted gesture, so core/MotionValue.qml's continuity
 * guarantee buys nothing here and a duration clip is the right tool (same
 * reasoning as the lyric line swap's NumberAnimation in
 * island/IslandRestItem.qml).
 *
 *   [[ 0 .. inMs ]      fade+rise in, Easing.OutCubic
 *    [inMs .. inMs+holdMs]   hold, fully visible
 *    [inMs+holdMs .. total]  fade out, Easing.InOutCubic ]
 *
 * finished() fires once, at the end of the fade-out, so the owning Loader
 * can unload (destroy) this item rather than just hiding it.
 */
Item {
    id: root

    required property int workspaceId
    signal finished()

    readonly property int inMs: 450
    readonly property int holdMs: 3550
    readonly property int outMs: 1000
    // inMs + holdMs + outMs === 5000, the spec's exact total.

    readonly property real riseDistance: Theme.u(0.28)

    // Ink: a 300x52 black pill (showcase .s-ws) with the workspace number in
    // serif and one dot per workspace, the current one a fillOn capsule.
    implicitWidth: Config.appearance.ink
        ? Math.round(300 * DisplayScale.primary) : label.implicitWidth + Theme.u(1.1)
    implicitHeight: Config.appearance.ink
        ? Math.round(52 * DisplayScale.primary) : label.implicitHeight + Theme.u(0.6)
    readonly property var inkDots: HyprlandService.workspaces
        .filter(ws => (ws?.id ?? 0) > 0)
        .sort((a, b) => a.id - b.id)

    property real revealProgress: 0   // 0 = hidden/risen, 1 = fully shown
    opacity: revealProgress
    y: (1 - revealProgress) * root.riseDistance

    Rectangle {
        visible: !Config.appearance.ink
        anchors.fill: parent
        radius: height / 2
        color: Theme.surfaceContainer
        opacity: 0.92
    }

    Rectangle {
        visible: Config.appearance.ink
        anchors.fill: parent
        radius: height / 2
        color: Theme.ink
        border.width: 1
        border.color: Theme.inkRim
    }

    Text {
        visible: Config.appearance.ink
        anchors.left: parent.left
        anchors.leftMargin: Math.round(22 * DisplayScale.primary)
        anchors.verticalCenter: parent.verticalCenter
        text: root.workspaceId
        color: Theme.t1
        font.family: Theme.fontSerif
        font.pixelSize: Math.round(28 * DisplayScale.primary)
    }

    Row {
        visible: Config.appearance.ink
        anchors.right: parent.right
        anchors.rightMargin: Math.round(24 * DisplayScale.primary)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Repeater {
            model: root.inkDots
            delegate: Rectangle {
                id: dot
                required property var modelData
                readonly property bool current: modelData.id === HyprlandService.activeWorkspaceId
                readonly property bool occupied: HyprlandService.occupiedWorkspaces
                    .some(w => w.id === modelData.id)
                width: current ? 22 : 6
                height: 6
                radius: 3
                color: current ? Theme.fillOn : (occupied ? Theme.t2 : Theme.t3)
                Behavior on width { NumberAnimation { duration: Theme.microMs; easing.type: Easing.OutCubic } }
            }
        }
    }

    Text {
        id: label
        visible: !Config.appearance.ink
        anchors.centerIn: parent
        text: "Workspace " + root.workspaceId
        color: AdaptiveColor.glassText
        font.family: Config.appearance.displayFontFamily
        font.pixelSize: Theme.u(0.42)
    }

    SequentialAnimation {
        id: timeline
        NumberAnimation {
            target: root; property: "revealProgress"
            from: 0; to: 1
            duration: root.inMs
            easing.type: Easing.OutCubic
        }
        PauseAnimation { duration: root.holdMs }
        NumberAnimation {
            target: root; property: "revealProgress"
            from: 1; to: 0
            duration: root.outMs
            easing.type: Easing.InOutCubic
        }
        onFinished: root.finished()
    }

    /** Restarts the whole 5s timeline from 0 -- reopening the launcher while
     *  the toast is still up must restart cleanly, not stack or jump. */
    function restart(): void {
        timeline.stop()
        root.revealProgress = 0
        timeline.start()
    }

    Component.onCompleted: timeline.start()
}
