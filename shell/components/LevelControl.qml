import QtQuick
import "../core"
import "../services"

/**
 * LevelControl - a full-width pill slider (output volume / brightness /
 * fallback microphone volume). No card, no label, no percentage, no
 * chevron: just a track, a fill and an icon that mutes on tap. Dragging
 * and scrolling anywhere else on the pill set the level.
 *
 * The icon hit-test is manual (mirrors ControlTile's split tap target)
 * rather than a second overlapping pointer handler, so there is exactly one
 * source of truth for "was this a mute-tap or a seek-drag".
 */
Item {
    id: root

    property real level: 0
    property string icon: ""
    property string iconName: ""      // Lucide name, drawn by Icon when ink is on
    property bool available: true
    property real previewLevel: level
    property bool dragging: false
    property bool pressedOnIcon: false
    property bool awaitingLevelConfirmation: false
    readonly property real displayedLevel: dragging || awaitingLevelConfirmation
        ? previewLevel
        : Math.max(0, Math.min(1, level))

    signal levelRequested(real level)
    signal actionRequested()

    // Ink: a 44px capsule with the value in Instrument Serif at the right.
    implicitHeight: Config.appearance.ink ? 44 : Theme.u(1.2)
    opacity: available ? 1 : 0.42
    activeFocusOnTab: available

    onLevelChanged: {
        if (!dragging && awaitingLevelConfirmation
                && Math.abs(level - previewLevel) <= 0.015) {
            awaitingLevelConfirmation = false
            levelConfirmationTimeout.stop()
        }
        if (!dragging && !awaitingLevelConfirmation)
            previewLevel = level
    }

    // Apply the level while dragging, not only on release. Throttled
    // (leading edge + one trailing send) so a fast drag doesn't queue a
    // backend write per mouse event on a slow CPU.
    property real lastSentLevel: -1
    property bool livePending: false
    function sendLive(): void {
        if (Math.abs(previewLevel - lastSentLevel) < 0.005)
            return
        if (liveThrottle.running) {
            livePending = true
            return
        }
        lastSentLevel = previewLevel
        levelRequested(previewLevel)
        liveThrottle.start()
    }

    Timer {
        id: liveThrottle
        interval: 40
        onTriggered: {
            if (root.livePending && root.dragging) {
                root.livePending = false
                root.sendLive()
            }
        }
    }

    Timer {
        id: levelConfirmationTimeout
        interval: Config.controlCenter.levelConfirmationTimeout
        onTriggered: root.awaitingLevelConfirmation = false
    }

    // Ink: the serif value sits right of the capsule, outside the track.
    Text {
        id: valueText
        visible: Config.appearance.ink
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.displayedLevel * 100)
        color: Theme.t1
        font.family: Theme.fontSerif
        font.pixelSize: 28
    }

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: Config.appearance.ink ? valueText.left : parent.right
        anchors.rightMargin: Config.appearance.ink ? 12 : 0
        radius: Config.appearance.ink ? height / 2 : Theme.u(0.6)
        color: Config.appearance.ink ? Theme.inkRaised : Theme.surfaceContainerHigh

        Rectangle {
            id: fill
            width: parent.width * root.displayedLevel
            height: parent.height
            radius: parent.radius
            color: Config.appearance.ink ? Theme.fillOn : AdaptiveColor.activeFill

            Behavior on width {
                enabled: !root.dragging
                NumberAnimation { duration: Animations.fast; easing.type: Animations.standardEase }
            }
        }
    }

    // Ink: the glyph rides inside the fill in glyphOn; it turns t1 when
    // the fill is too short to cover it. Icon (Lucide) when iconName is set.
    Item {
        id: iconGlyph
        x: Config.appearance.ink ? 14 : Theme.u(0.44)
        anchors.verticalCenter: parent.verticalCenter
        readonly property bool useLucide: Config.appearance.ink && root.iconName.length > 0
        readonly property color glyphColor: fill.width > iconGlyph.x + iconGlyph.width
            ? Theme.glyphOn : Theme.t1
        width: useLucide ? lucideIcon.width : glyphText.implicitWidth
        height: useLucide ? lucideIcon.height : glyphText.implicitHeight

        Icon {
            id: lucideIcon
            visible: iconGlyph.useLucide
            name: root.iconName
            size: 18
            color: iconGlyph.glyphColor
        }
        Text {
            id: glyphText
            visible: !iconGlyph.useLucide
            text: root.icon
            color: Config.appearance.ink ? iconGlyph.glyphColor : Theme.accentFillText
            font.family: Config.appearance.monoFontFamily
            font.pixelSize: Config.appearance.ink ? 18 : Theme.u(0.4)
        }
    }

    MouseArea {
        id: interaction
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: Config.appearance.ink ? track.right : parent.right
        enabled: root.available
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: false

        function withinIcon(px, py): bool {
            return px >= iconGlyph.x - Theme.u(0.16)
                && px <= iconGlyph.x + iconGlyph.width + Theme.u(0.16)
        }
        function updatePreview(mx): void {
            root.previewLevel = Math.max(0, Math.min(1, mx / width))
            if (root.dragging)
                root.sendLive()
        }

        onPressed: mouse => {
            levelConfirmationTimeout.stop()
            root.awaitingLevelConfirmation = false
            if (withinIcon(mouse.x, mouse.y)) {
                root.pressedOnIcon = true
            } else {
                root.pressedOnIcon = false
                root.lastSentLevel = -1
                root.dragging = true
                updatePreview(mouse.x)
            }
        }
        onPositionChanged: mouse => {
            if (pressed && !root.pressedOnIcon)
                updatePreview(mouse.x)
        }
        onReleased: mouse => {
            if (root.pressedOnIcon) {
                if (withinIcon(mouse.x, mouse.y))
                    root.actionRequested()
            } else if (root.dragging) {
                updatePreview(mouse.x)
                root.awaitingLevelConfirmation = true
                root.dragging = false
                levelConfirmationTimeout.restart()
                root.levelRequested(root.previewLevel)
            }
            root.pressedOnIcon = false
        }
        onCanceled: {
            levelConfirmationTimeout.stop()
            root.dragging = false
            root.pressedOnIcon = false
            root.awaitingLevelConfirmation = false
            root.previewLevel = root.level
        }
        onWheel: wheel => {
            // 2% per notch, matching the hardware volume keys.
            const delta = wheel.angleDelta.y > 0 ? 0.02 : -0.02
            root.levelRequested(Math.max(0, Math.min(1, root.level + delta)))
        }
    }

    Keys.onPressed: event => {
        if (!root.available)
            return
        if (event.key === Qt.Key_Left || event.key === Qt.Key_Down) {
            root.levelRequested(Math.max(0, root.level - 0.02))
            event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Up) {
            root.levelRequested(Math.min(1, root.level + 0.02))
            event.accepted = true
        } else if (event.key === Qt.Key_Space) {
            root.actionRequested()
            event.accepted = true
        }
    }
}
