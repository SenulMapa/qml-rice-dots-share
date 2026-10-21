import QtQuick
import "../core"

/**
 * Reveal -- staggered fade-in wrapper for expanded-island content.
 *
 * Wraps one piece of content (its default property) and drives ONLY that
 * content's opacity and a Translate transform -- never `y`/anchors, so the
 * layout that positions this wrapper (a Layout cell, an anchor, whatever)
 * still owns real geometry. The wrapper itself reports the content's own
 * implicit size so it drops into a Layout exactly like the content would
 * have on its own.
 *
 * Contract:
 *  - `token` is bumped by the host (island/IslandExpanded.qml) on open or
 *    on a page change, and ONLY then -- never on a data update (a CPU
 *    percentage, a clock tick). Bumping it replays the entrance.
 *  - `order` is this element's position in the current page's stagger
 *    sequence. Delay is `min(order, 7) * 35ms` -- capped at 8 steps so a
 *    long list (the weekly forecast, a big quick-strip) doesn't push its
 *    last elements absurdly late.
 *  - `exiting` is set true by the host when the whole expanded view is
 *    closing. All Reveals fade out together in 120ms, no stagger, and an
 *    exit always wins over a pending/in-flight entrance.
 *  - `Config.appearance.reducedMotion` collapses everything to an instant
 *    opacity flip -- no stagger, no translate.
 */
Item {
    id: root

    property int token: 0
    property int order: 0
    property bool exiting: false

    default property alias content: contentHolder.data

    implicitWidth: contentHolder.implicitWidth
    implicitHeight: contentHolder.implicitHeight

    // Not readonly: defaults to the real setting, but overridable at
    // instantiation -- the same seam panels/PolkitPage.qml uses for its
    // `controller` property, so test-reveal.qml can exercise this path
    // without writing to the user's real settings file.
    property bool reducedMotion: Config.appearance.reducedMotion
    readonly property int staggerDelay: reducedMotion ? 0
        : Math.min(root.order, 7) * 35

    // Testability seams for test-reveal.qml only -- there is no other
    // externally-visible way to inspect the private opacity/translate
    // state or which phase is currently running.
    readonly property alias debugOpacity: contentHolder.opacity
    readonly property alias debugRiseY: rise.y
    readonly property alias debugEntranceDelayRunning: entranceDelay.running
    readonly property alias debugEntranceRunning: entranceOpacity.running
    readonly property alias debugExitRunning: exitOpacity.running

    Item {
        id: contentHolder
        anchors.fill: parent
        opacity: 0
        transform: Translate { id: rise; y: root.reducedMotion ? 0 : 8 }
    }

    function playEnter(): void {
        entranceDelay.stop()
        entranceOpacity.stop()
        entranceRise.stop()
        exitOpacity.stop()
        if (root.reducedMotion) {
            contentHolder.opacity = 1
            rise.y = 0
            return
        }
        contentHolder.opacity = 0
        rise.y = 8
        entranceDelay.interval = root.staggerDelay
        entranceDelay.start()
    }

    function playExit(): void {
        entranceDelay.stop()
        entranceOpacity.stop()
        entranceRise.stop()
        if (root.reducedMotion) {
            contentHolder.opacity = 0
            return
        }
        exitOpacity.restart()
    }

    // Exit always wins: it is set by the host closing the whole island, and
    // must not be delayed or blocked by a stagger that was still in flight.
    // Opening flips `exiting` false AND bumps `token` in the same tick, and
    // the host's onActiveChanged can run before the `exiting` binding
    // re-evaluates -- so onTokenChanged may still read exiting === true and
    // skip. Leaving the exiting state therefore plays the entrance itself;
    // a second playEnter() in the same tick just restarts it harmlessly.
    onExitingChanged: root.exiting ? playExit() : playEnter()
    onTokenChanged: if (!root.exiting) playEnter()

    Component.onCompleted: {
        if (root.exiting) {
            contentHolder.opacity = 0
            rise.y = root.reducedMotion ? 0 : 8
        } else {
            playEnter()
        }
    }

    Timer {
        id: entranceDelay
        repeat: false
        onTriggered: {
            entranceOpacity.restart()
            entranceRise.restart()
        }
    }
    // Opacity finishes (200ms) before the translate (280ms) -- both start
    // together, opacity is just the shorter of the two.
    NumberAnimation {
        id: entranceOpacity
        target: contentHolder
        property: "opacity"
        from: 0; to: 1
        duration: 200
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: entranceRise
        target: rise
        property: "y"
        from: 8; to: 0
        duration: 280
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: exitOpacity
        target: contentHolder
        property: "opacity"
        to: 0
        duration: 120
        easing.type: Easing.OutCubic
    }
}
