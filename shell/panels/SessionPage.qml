import QtQuick
import QtQuick.Layouts
import "../core"
import "../components"
import "../services"

/**
 * SessionPage -- a single row of square tiles, one per available session
 * action. No bento: unarmed tiles carry no fill and no border at rest, only
 * a glyph and a label (owner, 13 Sep 15:41: "get rid of the borders and the
 * card backgrounds ... keeping the layout but not making them look like
 * bentos"). The old modal confirmation overlay is gone -- Hibernate/Log out/
 * Restart/Shut down arm IN PLACE instead: first press fills the tile
 * Theme.error and swaps its label to "Confirm"; a second press within the
 * ArmState window fires the action through the existing SessionService path.
 * Lock and Suspend never arm, they fire immediately.
 *
 * Only AVAILABLE actions render as tiles -- island/IslandController.qml's
 * `sessionPageWidth` sizes the page to exactly that count from the same
 * SessionService flags, so the two can never disagree.
 */
FocusScope {
    id: root

    property int focusedIndex: 0
    property ArmState armState: ArmState { }

    // Press-and-hold confirm for the arming tiles (Hibernate/Log out/Restart/
    // Shut down). holdingKey is the action under the pointer mid-hold and
    // drives the hint line; holdFired is the one-shot guard so a completed
    // hold can never fire twice. Both reset when the page closes.
    property string holdingKey: ""
    property bool holdFired: false
    readonly property var holdVerbs: ({
        hibernate: "hibernate", logout: "log out",
        reboot: "restart", shutdown: "shut down"
    })
    readonly property real holdHintSlot: Theme.u(0.5)

    readonly property var actions: [
        {
            action: "lock", title: "Lock", icon: "󰌾",
            available: SessionService.lockAvailable, confirmation: false
        },
        {
            action: "suspend", title: "Suspend", icon: "󰒲",
            available: SessionService.suspendAvailable, confirmation: false
        },
        {
            action: "hibernate", title: "Hibernate", icon: "󰤄",
            available: SessionService.hibernateAvailable, confirmation: true
        },
        {
            action: "logout", title: "Log out", icon: "󰍃",
            available: SessionService.logoutAvailable, confirmation: true
        },
        {
            action: "reboot", title: "Restart", icon: "󰜉",
            available: SessionService.rebootAvailable, confirmation: true
        },
        {
            action: "shutdown", title: "Shut down", icon: "󰐥",
            available: SessionService.shutdownAvailable, confirmation: true
        }
    ]

    readonly property var availableActions: actions.filter(entry => entry.available)

    signal dismissRequested()

    // Called by island/IslandExpanded.qml's closeTransientUi() on Escape,
    // exactly like the old modal confirmation did -- only the MEANING
    // changed: this now disarms an armed tile instead of closing a dialog.
    // Returning true means "consumed"; the caller stops there instead of
    // closing the whole page, so the very next Escape (nothing armed) falls
    // through and closes it.
    function cancelConfirmation(): bool {
        if (!armState.hasArmed)
            return false
        armState.disarm()
        return true
    }

    function activate(index: int): void {
        if (holdFired || index < 0 || index >= availableActions.length
                || SessionService.executing)
            return
        const entry = availableActions[index]
        focusedIndex = index
        const fired = armState.press(entry.action, entry.confirmation)
        if (!fired)
            return
        if (SessionService.schedule(entry.action))
            dismissRequested()
        else
            armState.disarm()
    }

    // A tile's hold reached 700ms. Fires through the same SessionService path
    // as a confirmed second press. Returns false when nothing was scheduled,
    // so the caller can spring the ring back.
    function holdFire(index: int): bool {
        if (holdFired || index < 0 || index >= availableActions.length
                || SessionService.executing)
            return false
        const entry = availableActions[index]
        holdFired = true
        armState.disarm()
        if (SessionService.schedule(entry.action)) {
            dismissRequested()
            return true
        }
        holdFired = false
        return false
    }

    function moveFocus(delta: int): void {
        if (availableActions.length === 0)
            return
        focusedIndex = (focusedIndex + delta + availableActions.length)
            % availableActions.length
    }

    onVisibleChanged: {
        holdFired = false
        holdingKey = ""
        if (visible) {
            armState.disarm()
            const lockIndex = availableActions.findIndex(
                entry => entry.action === "lock")
            focusedIndex = Math.max(0, lockIndex)
            SessionService.refresh()
            Qt.callLater(() => root.forceActiveFocus())
        }
    }

    // ArmState owns no QML Timer itself (see components/ArmState.qml) --
    // this is the tick that expires an armed tile after 3000ms of silence.
    Timer {
        interval: 150
        repeat: true
        running: root.armState.hasArmed
        onTriggered: root.armState.checkExpiry()
    }

    // Preview IPC (services/PreviewService.qml, QMLRICE_PREVIEW=1 only):
    // visual-only arming through ArmState.arm(), which can never fire/
    // execute a real session action.
    Connections {
        target: PreviewService
        enabled: PreviewService.enabled
        function onSessionArmRequested(): void {
            root.armState.arm(PreviewService.armedAction)
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Left) {
            moveFocus(-1)
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            moveFocus(1)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            activate(focusedIndex)
            event.accepted = true
        }
        // Escape is deliberately NOT handled here -- see cancelConfirmation().
    }

    // Hint under the discs: names the pending confirm while a tile is armed
    // or being held. Fades rather than toggling so the row never reflows.
    Text {
        id: holdHint
        readonly property string hintKey: root.holdingKey.length > 0
            ? root.holdingKey : root.armState.armedKey
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.u(0.1)
        text: "Press again or hold to " + (root.holdVerbs[hintKey] || "confirm")
        opacity: hintKey.length > 0 ? 1 : 0
        color: Config.appearance.ink ? Theme.t2 : AdaptiveColor.glassTextDim
        font.family: Theme.fontUi
        font.pixelSize: 11
        font.weight: Font.Medium
        Behavior on opacity { NumberAnimation { duration: Animations.fast } }
    }

    Item {
        id: tilesWrap
        anchors.fill: parent

        RowLayout {
            id: tilesRow
            anchors.fill: parent
            anchors.margins: Theme.u(0.22)
            anchors.bottomMargin: Theme.u(0.22) + root.holdHintSlot
            spacing: Theme.u(0.22)

            Repeater {
                id: tilesRepeater
                model: root.availableActions

                // Glass redesign: a round glass button per action with its
                // label beneath (same language as the control centre's
                // toggles). Keyboard focus = the computed light activeFill;
                // armed (press again to confirm) = solid error red.
                Item {
                id: tile
                required property var modelData
                required property int index
                readonly property bool armed: root.armState.isArmed(modelData.action)
                readonly property bool focused: index === root.focusedIndex
                readonly property string symbol: ({
                    lock: "lock", suspend: "bedtime", hibernate: "mode_standby",
                    logout: "logout", reboot: "restart_alt", shutdown: "power_settings_new"
                })[modelData.action] || "power_settings_new"

                // Ink: Lucide icon for each action (hibernate shares the moon).
                readonly property string lucideName: ({
                    lock: "lock", suspend: "moon", hibernate: "moon",
                    logout: "log-out", reboot: "rotate-ccw", shutdown: "power"
                })[modelData.action] || "power"

                // Single handle back to the page (keeps the delegate to one
                // outer reference).
                readonly property var page: root
                // Press-and-hold: only the arming tiles hold; Lock/Suspend
                // stay a plain click. holdProgress 0..1 over 700ms.
                readonly property bool holdable: modelData.confirmation
                readonly property color holdColor: Config.appearance.ink ? "#ff453a" : Theme.error
                property real holdProgress: 0
                property bool pressCancelled: false
                property bool holdCompleted: false

                function beginPress(): void {
                    pressCancelled = false
                    holdCompleted = false
                    if (!holdable || SessionService.executing)
                        return
                    returnAnim.stop()
                    page.holdingKey = modelData.action
                    holdAnim.restart()
                }
                // Released: an early release is a normal click (first press
                // arms, a second fires); a completed or cancelled hold is not.
                function endPress(): void {
                    holdAnim.stop()
                    if (page.holdingKey === modelData.action)
                        page.holdingKey = ""
                    springBack()
                    if (!holdCompleted && !pressCancelled)
                        page.activate(index)
                }
                // Pointer left the tile mid-press: the hold dies and the
                // eventual release does nothing.
                function cancelHold(): void {
                    pressCancelled = true
                    if (page.holdingKey === modelData.action)
                        page.holdingKey = ""
                    springBack()
                }
                function springBack(): void {
                    holdAnim.stop()
                    if (holdProgress > 0)
                        returnAnim.restart()
                }
                function resetHold(): void {
                    holdAnim.stop()
                    returnAnim.stop()
                    holdProgress = 0
                    holdCompleted = false
                    pressCancelled = true
                }

                NumberAnimation {
                    id: holdAnim
                    target: tile
                    property: "holdProgress"
                    from: 0
                    to: 1
                    duration: 700
                    easing.type: Easing.Linear
                    onFinished: {
                        tile.holdCompleted = true
                        if (!tile.page.holdFire(tile.index))
                            tile.springBack()
                        tile.page.holdingKey = ""
                    }
                }
                NumberAnimation {
                    id: returnAnim
                    target: tile
                    property: "holdProgress"
                    to: 0
                    duration: 200
                    easing.type: Easing.OutCubic
                }
                // Page closed mid-hold (Escape, or the action fired): reset.
                Connections {
                    target: tile.page
                    function onVisibleChanged(): void {
                        if (!tile.page.visible)
                            tile.resetHold()
                    }
                }

                Layout.fillWidth: true
                Layout.fillHeight: true

                Item {
                    id: disc
                    width: Math.min(Config.appearance.ink ? 64 : 58, tile.width - 8); height: width
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(0, (tile.height - height - label.implicitHeight - 8) / 2)
                    scale: tileMouse.pressed ? 0.92 : (tileHover.hovered ? 1.05 : 1)
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    // Shut down's ring: a 3px track, turning error red while armed.
                    Rectangle {
                        visible: Config.appearance.ink && tile.modelData.action === "shutdown"
                        anchors.fill: parent
                        anchors.margins: -5
                        radius: width / 2
                        color: "transparent"
                        border.width: 3
                        border.color: tile.armed ? Theme.error : Qt.rgba(1, 1, 1, 0.08)
                    }
                    GlassMaterial {
                        anchors.fill: parent
                        radius: width / 2
                        shadow: 0.07
                        shadowSpread: 10
                        rimWidth: 5
                        tintAlpha: tileHover.hovered ? 0.32 : 0.24
                        // Ink: focus is the opaque fillOn disc, armed is solid error red.
                        active: Config.appearance.ink ? (tile.focused && !tile.armed) : (tile.focused || tile.armed)
                        activeColor: tile.armed ? Theme.error : AdaptiveColor.activeFill
                        inkFill: tile.armed ? Theme.error : Theme.inkRaised
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: Config.appearance.ink
                        name: tile.lucideName
                        size: 22
                        color: tile.armed ? Theme.foregroundFor(Theme.error)
                            : tile.focused ? Theme.glyphOn : Theme.t1
                        Behavior on color { ColorAnimation { duration: Animations.fast } }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !Config.appearance.ink
                        text: tile.symbol
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: Config.appearance.ink ? 22 : 26
                        font.variableAxes: ({ "FILL": tile.focused || tile.armed ? 1 : 0 })
                        color: Config.appearance.ink
                            ? (tile.armed ? Theme.foregroundFor(Theme.error)
                                : tile.focused ? Theme.glyphOn : Theme.t1)
                            : tile.armed ? Theme.foregroundFor(Theme.error)
                            : tile.focused ? AdaptiveColor.activeFillText : AdaptiveColor.glassText
                        Behavior on color { ColorAnimation { duration: Animations.fast } }
                    }
                }
                // Hold ring: sweeps clockwise from 12 o'clock as the hold
                // progresses. Sits 5px outside the disc, like the shutdown track.
                Canvas {
                    id: holdRing
                    anchors.fill: disc
                    anchors.margins: -5
                    visible: tile.holdable && tile.holdProgress > 0
                    readonly property real sweep: tile.holdProgress
                    onSweepChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        if (sweep <= 0)
                            return
                        ctx.lineWidth = 3
                        ctx.strokeStyle = tile.holdColor
                        ctx.beginPath()
                        ctx.arc(width / 2, height / 2, width / 2 - 1.5,
                            -Math.PI / 2, -Math.PI / 2 + sweep * 2 * Math.PI, false)
                        ctx.stroke()
                    }
                }

                Text {
                    id: label
                    anchors.top: disc.bottom
                    anchors.topMargin: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: tile.armed ? "Confirm" : tile.modelData.title
                    color: Config.appearance.ink
                        ? (tile.armed || tile.focused ? Theme.t1 : Theme.t2)
                        : tile.armed || tile.focused ? AdaptiveColor.glassText : AdaptiveColor.glassTextDim
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }

                HoverHandler { id: tileHover }
                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onPressed: tile.beginPress()
                    onReleased: tile.endPress()
                    onCanceled: tile.cancelHold()
                    onContainsMouseChanged: {
                        if (!containsMouse && pressed)
                            tile.cancelHold()
                    }
                }
            }
        }
        }

    }
}
