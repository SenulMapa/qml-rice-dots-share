import QtQuick
import "../core"

Item {
    id: root

    property real from: 0
    property real to: 100
    property real value: 0
    property real stepSize: 1
    property bool available: true
    signal adjusted(real value)

    readonly property real range: Math.max(0.0001, to - from)
    readonly property real position: Math.max(0, Math.min(1,
        (value - from) / range))

    activeFocusOnTab: available
    // Ink (Config.appearance.ink): a capsule filled to the value in fillOn.
    readonly property bool ink: Config.appearance.ink

    implicitHeight: ink ? 36 : 22
    opacity: available ? 1 : 0.38

    Keys.onPressed: event => {
        if (!available)
            return
        if (event.key === Qt.Key_Left)
            adjusted(Math.max(from, value - stepSize))
        else if (event.key === Qt.Key_Right)
            adjusted(Math.min(to, value + stepSize))
        else if (event.key === Qt.Key_Home)
            adjusted(from)
        else if (event.key === Qt.Key_End)
            adjusted(to)
        else
            return
        event.accepted = true
    }

    function valueAt(mouseX: real): real {
        const normalized = Math.max(0, Math.min(1, mouseX / width))
        const raw = from + normalized * range
        return Math.max(from, Math.min(to,
            Math.round(raw / stepSize) * stepSize))
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.ink ? root.height : 3
        radius: height / 2
        color: root.ink ? Theme.inkRaised : Qt.alpha(Theme.outlineVariant, 0.68)

        Rectangle {
            width: root.ink ? Math.max(parent.height, parent.width * root.position)
                : parent.width * root.position
            height: parent.height
            radius: parent.radius
            color: root.ink ? Theme.fillOn : Theme.primary
        }
    }

    Rectangle {
        visible: !root.ink
        width: Math.round(knobSize.value)
        height: width
        radius: width / 2
        x: Math.max(0, Math.min(root.width - width,
            root.width * root.position - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.primary
        border.width: 2
        border.color: Theme.surfaceContainerHigh

        property MotionValue knobSize: MotionValue {
            unit: "px"
            omega: Motion.presetSnappy().omega
            zeta: Motion.presetSnappy().zeta
            target: root.activeFocus ? 15 : 11
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: root.available
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function updateValue(mouseX) {
            root.adjusted(root.valueAt(mouseX))
        }
        onPressed: mouse => {
            root.forceActiveFocus()
            updateValue(mouse.x)
        }
        onPositionChanged: mouse => {
            if (dragArea.pressed)
                updateValue(mouse.x)
        }
    }
}
