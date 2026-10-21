pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import "../core"

/**
 * LockSurface -- the per-screen lock UI. Hosted inside a
 * Quickshell.Wayland.WlSessionLockSurface by lock/LockScreen.qml (real,
 * not wired up yet) or a plain FloatingWindow by preview-lock.qml
 * (preview). Owns no PAM/session state itself: everything it does is
 * driven by `context` (lock/LockContext.qml), which is shared across
 * every screen's surface so a password typed on one monitor authenticates
 * for all of them at once.
 *
 * Sequence on context.state:
 *   locked        -- quote diffuses in once, on first show.
 *   failed        -- pill shakes, then context.acknowledgeFailure() -> locked.
 *   unlocking     -- (a) quote diffuses OUT, then (b)+(c) run together:
 *                    the fill breaks into steppers revealing the desktop
 *                    while the SAME pill Rectangle shrinks/travels/recolors
 *                    into the dormant island's exact geometry. Only once
 *                    BOTH finish does context.finishUnlockAnimation() run.
 *
 * The island-pill target geometry is read-only from Config.island / Theme
 * -- this file never writes either.
 */
Item {
    id: root

    required property QtObject context

    // Test-only visibility hook (test-lock.qml): lets a headless test assert
    // the pill actually rendered without needing a real window to query
    // children through.
    readonly property alias pillVisible: pill.visible

    // Every surface grabs keyboard focus for itself, unconditionally, the
    // moment it exists -- this is what item 1 of the bug report actually
    // needs. We do NOT try to guess which monitor is "the focused one" and
    // only arm that one: the compositor hands real key events to whichever
    // surface it considers focused, so every surface must be armed and
    // ready or the one the compositor picks might be the one nobody wired
    // up. _grabFocus() is called on creation, whenever this item becomes
    // visible, and whenever its Window becomes the active window, so a
    // keystroke works with zero prior mouse movement no matter which
    // monitor the compositor gave focus to.
    focus: true

    readonly property var quotes: [
        "Welcome back. The world kept spinning; so did you.",
        "Still here. Still yours.",
        "Nothing urgent happened while you were gone.",
        "Same desk, same you, one password later.",
        "Good to see you again.",
        "The screen missed you more than it should admit.",
        "Pick up right where you left off.",
        "You made it back. That's the hard part.",
        "Quiet while you were away. It's yours again now.",
        "One more day, one more login.",
        "Everything's exactly where you left it.",
        "Back at it. No rush."
    ]
    readonly property string quote:
        root.quotes[Math.floor(Math.random() * root.quotes.length)]

    // ---- dormant island-pill target geometry (READ-ONLY) -----------------
    readonly property int islandTargetWidth: Math.max(
        Config.island.dormantWidth, Config.island.restMinimumWidth)
    readonly property int islandTargetHeight: Config.island.dormantHeight
    readonly property int islandTargetRadius: Theme.radiusFor(root.islandTargetHeight)
    readonly property int islandTargetTopMargin: Config.island.topMargin

    // ---- rest-state (locked/failed) pill geometry -------------------------
    readonly property int pillRestWidth: 240
    readonly property int pillRestHeight: 52
    readonly property int pillRestRadius: root.pillRestHeight / 2

    // Both the steppers' break and the pill's flight must land before the
    // real unlock is allowed to happen -- see _onPartDone().
    property int _partsRemaining: 2

    // Solid fill for every state EXCEPT `unlocking` -- once the break
    // starts, the Steppers below (same fillColor, so there is no seam) is
    // the only thing covering the screen, so its peeling columns are what
    // actually reveals whatever sits behind this surface.
    Rectangle {
        id: background
        anchors.fill: parent
        color: Theme.surface
        visible: root.context.state === root.context.locked
            || root.context.state === root.context.authenticating
            || root.context.state === root.context.failed
    }

    DiffusionText {
        id: quoteText
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * 0.38)
        text: root.quote
        textColor: Theme.surfaceText
        pixelSize: 22
        fontFamily: Config.appearance.fontFamily
        visible: root.context.state !== root.context.unlocked
    }

    Rectangle {
        id: pill
        width: root.pillRestWidth
        height: root.pillRestHeight
        radius: root.pillRestRadius
        color: Theme.surfaceContainerHigh
        x: Math.round((root.width - width) / 2)
        y: quoteText.y + quoteText.height + Theme.space5
        // Visible on EVERY surface unconditionally (item 2): the shared
        // buffer this shows is the same on every monitor, so there is no
        // "wrong" screen to hide it on -- hiding it anywhere is exactly the
        // "no input field" bug this fixes.
        visible: root.context.state !== root.context.unlocked
        transform: Translate { id: shakeT; x: 0 }

        Row {
            anchors.centerIn: parent
            spacing: Theme.space2
            Repeater {
                model: Math.min(root.context.currentText.length, 20)
                delegate: Rectangle {
                    width: 8; height: 8; radius: 4
                    color: Theme.surfaceText
                }
            }

            // Empty-buffer placeholder/caret so the pill visibly reads as
            // an input field even before the first keystroke lands.
            Rectangle {
                id: caret
                visible: root.context.currentText.length === 0
                width: 2; height: 18
                color: Theme.surfaceText

                SequentialAnimation on opacity {
                    running: caret.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 0; duration: 500 }
                    NumberAnimation { to: 1; duration: 500 }
                }
            }
        }
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shakeT; property: "x"; to: -10; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 10; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 8; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 60 }
        onFinished: root.context.acknowledgeFailure()
    }

    Steppers {
        id: steppers
        anchors.fill: parent
        fillColor: Theme.surface
        visible: root.context.state === root.context.unlocking
        onBreakFinished: root._onPartDone()
    }

    // Reuses the SAME `pill` Rectangle for the fly-to-island-geometry step
    // instead of a second element -- it shrinks/moves/recolors in place and
    // simply BECOMES the resting clock pill, so there is nothing to
    // cross-fade or hand off once the real island takes over at the same
    // spot. Duration matches the steppers' total settle time (920ms travel
    // + 5 x 68ms stagger = 1260ms) so both parts of the reveal land
    // together, using the same stepper easing for visual cohesion.
    ParallelAnimation {
        id: pillFlyAnim
        NumberAnimation {
            target: pill; property: "x"
            to: Math.round((root.width - root.islandTargetWidth) / 2)
            duration: 1260; easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
        }
        NumberAnimation {
            target: pill; property: "y"
            to: root.islandTargetTopMargin
            duration: 1260; easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
        }
        NumberAnimation {
            target: pill; property: "width"
            to: root.islandTargetWidth
            duration: 1260; easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
        }
        NumberAnimation {
            target: pill; property: "height"
            to: root.islandTargetHeight
            duration: 1260; easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
        }
        NumberAnimation {
            target: pill; property: "radius"
            to: root.islandTargetRadius
            duration: 1260; easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.76, 0, 0.24, 1, 1, 1]
        }
        ColorAnimation {
            target: pill; property: "color"
            to: Theme.islandSurface
            duration: 1260
        }
        onFinished: root._onPartDone()
    }

    function _onPartDone(): void {
        root._partsRemaining -= 1
        if (root._partsRemaining <= 0)
            root.context.finishUnlockAnimation()
    }

    function _beginUnlockSequence(): void {
        root._partsRemaining = 2
        quoteText.direction = "out"
        quoteText.animating = true
    }

    Connections {
        target: quoteText
        function onAnimationFinished() {
            if (root.context.state === root.context.unlocking) {
                steppers.play()
                pillFlyAnim.start()
            }
        }
    }

    Connections {
        target: root.context
        function onStateChanged() {
            const s = root.context.state
            if (s === root.context.failed) {
                shakeAnim.restart()
            } else if (s === root.context.unlocking) {
                root._beginUnlockSequence()
            }
        }
    }

    // ---- keyboard input (item 1) ------------------------------------------
    // Feeds ONE shared buffer (context.currentText) from whichever surface
    // the compositor actually delivers key events to -- see the `focus:
    // true` comment above for why every surface is armed rather than just
    // one "focused" guess.
    Keys.onPressed: event => root._handleKeyEvent(event)

    function _handleKeyEvent(event): void {
        // Only take input while there is something to type into -- not
        // mid-auth-attempt, not while the unlock choreography is playing.
        if (root.context.state !== root.context.locked
                && root.context.state !== root.context.failed) {
            event.accepted = true
            return
        }

        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.context.submit(root.context.currentText)
        } else if (event.key === Qt.Key_Escape) {
            root.context.currentText = ""
        } else if (event.key === Qt.Key_Backspace) {
            root.context.currentText = root.context.currentText.slice(0, -1)
        } else if (event.text && event.text.length > 0 && event.text >= " ") {
            // Plain printable character -- ignore control characters (empty
            // or non-printable event.text) rather than appending garbage.
            root.context.currentText += event.text
        }
        event.accepted = true
    }

    // Grabs keyboard focus unconditionally: on creation, whenever this
    // surface becomes visible, and whenever its Window becomes the active
    // window. No pointer-enter, no "focused" guess -- see the `focus: true`
    // comment above.
    function _grabFocus(): void {
        root.forceActiveFocus()
    }

    onVisibleChanged: if (root.visible) root._grabFocus()

    Connections {
        target: root.Window.window
        function onActiveChanged() {
            if (root.Window.window && root.Window.window.active)
                root._grabFocus()
        }
    }

    Component.onCompleted: {
        quoteText.direction = "in"
        quoteText.animating = true
        root._grabFocus()
    }
}
