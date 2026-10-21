import QtQuick
import "../core"

/**
 * SharedElements -- ink-mode shared element layer. One instance each of
 * SharedArt, SharedTitle and SharedClock lives here, so an item that appears
 * in two island states morphs between them instead of cross-fading.
 *
 * Parent must be the island's content layer (the pill's coordinate space and
 * rounded clip). island/Island.qml does that wiring.
 *
 * CHOREOGRAPHY (all of it hangs off island/Choreography.qml, whose p is the
 * body's morph progress 0..1 computed from the live bodyW/bodyH; 120ms
 * fade-outs use the same Motion clock; no timers of their own)
 *
 * Coordinates. Hosts are centred in the body, so a placeholder's position
 * RELATIVE TO THE BODY CENTRE does not change while the body grows. Targets
 * are therefore stored centre-relative and each element adds width/2 per
 * frame. The old absolute targets moved with the growing body, and the
 * springs chasing them slid in from outside the left edge ~350ms late.
 *
 * OPEN rest -> dashboard (p is the body spring, ~0.45s response):
 *   f0   p=0. Choreography flips curKey. The dashboard host opacity is
 *        enterT(0)=0 (it was drawn at final layout in frame 1 before), the
 *        content layer is reparented under a rounded ClippingRectangle that
 *        has the body's w/h/radius. Clock (rest only) is not in the new
 *        state: it fades out over 120ms from its snapshot. Art/title were
 *        not shown: fresh, presence=enterT=0, jumped onto the placeholder.
 *   ~f10 p~0.55: content and art/title start rising 6px->0 with opacity
 *        smoothstep(0.55,0.9,p); they are at their TARGET rects the whole
 *        time and are clipped to the blob.
 *   ~f20 p~0.9: fully revealed. p latches 1 at 0.999, clipActive drops, the
 *        content layer returns to the plain parent, Motion goes idle.
 *
 * PAGE -> PAGE (dashboard -> media): the expanded host fades 1->0 and
 *   scales to 0.98 in the first 120ms (7 frames) while the body is held
 *   only if shrinking; the media host reveals with smoothstep(0.55,0.9,p).
 *   Art and title exist in both states: carried=true, so they are never
 *   hidden; their x/y/w/h/radius spring from where they are on screen to
 *   the media placeholder (168px, r22) on the body spring. Radius comes
 *   from SharePoint.shareRadius (dashboard 12, media 22, hover w/2).
 *
 * CLOSE dashboard -> rest: content, art and title fade out and scale to
 *   0.98 over the first 120ms. The body target is HELD for 0.75*120ms =
 *   90ms (Choreography.holding), so by the time it moves they are ~94%
 *   gone instead of the old 50% shrunk-at-120ms. The rest host and the
 *   rest clock fade in with smoothstep(0.6,0.95,p), at their final rects;
 *   nothing is revealed by clipping. Satellites close first (Island.qml).
 *
 * Reduced motion: no morph choreography; presence is a 150ms crossfade and
 * the springs snap.
 *
 * Gated: visible and retargeting only under Config.appearance.ink.
 */
Item {
    id: root

    anchors.fill: parent
    visible: Config.appearance.ink

    // The Choreography instance (island/Island.qml).
    property var choreo: null
    readonly property string stateKey: root.choreo ? root.choreo.curKey : ""
    // Every SharePoint across all states (Island.qml collects them).
    property var placeholders: []

    readonly property bool busy: root.choreo ? root.choreo.animating : false

    SharedArt {
        id: art
        busy: root.busy
        presence: root.presenceOf(art)
        lift: root.liftOf(art)
        shrink: root.shrinkOf(art)
    }
    SharedTitle {
        id: title
        busy: root.busy
        presence: root.presenceOf(title)
        lift: root.liftOf(title)
        shrink: root.shrinkOf(title)
    }
    SharedClock {
        id: clock
        busy: root.busy
        presence: root.presenceOf(clock)
        lift: root.liftOf(clock)
        shrink: root.shrinkOf(clock)
    }

    function presenceOf(el): real {
        const c = root.choreo
        if (!c || !Config.appearance.ink) return 0
        if (c.reduced) return el.shown ? 1 : 0
        if (el.shown)
            return el.carried ? el.snap + (1 - el.snap) * c.enterT : c.enterT
        return el.snap * (1 - c.leaveFade)
    }
    function liftOf(el): real {
        const c = root.choreo
        return c && c.active && el.shown && !el.carried ? 6 * (1 - c.enterT) : 0
    }
    function shrinkOf(el): real {
        const c = root.choreo
        return c && c.active && !el.shown ? 1 - 0.02 * c.leaveFade : 1
    }

    function _find(kind) {
        for (let i = 0; i < root.placeholders.length; i++) {
            const ph = root.placeholders[i]
            if (ph && ph.shareKind === kind
                && root.choreo && ph.shareState === root.choreo.curKey
                && ph.shareLive && ph.measure)
                return ph
        }
        return null
    }

    // Centre-relative rect of a placeholder's measured item.
    function _rectOf(item) {
        const p = item.mapToItem(root, 0, 0)
        return { x: p.x - root.width / 2, y: p.y, w: item.width, h: item.height }
    }

    function retarget() {
        if (!Config.appearance.ink || !root.visible) return

        const a = _find("art")
        if (a) {
            const r = _rectOf(a.measure)
            art.aimAt(r.x, r.y, r.w, r.h, a.shareRadius < 0 ? r.w / 2 : a.shareRadius)
        } else {
            art.fadeOut()
        }

        const t = _find("title")
        if (t) {
            const r = _rectOf(t.measure)
            title.aimAt(r.x, r.y, r.w, r.h, t.shareScale, t.shareSubScale)
        } else {
            title.fadeOut()
        }

        const c = _find("clock")
        if (c) {
            const r = _rectOf(c.measure)
            clock.aimAt(r.x + r.w / 2, r.y + r.h / 2, c.shareScale)
        } else {
            clock.fadeOut()
        }
    }

    // Snapshot before the choreography installs the new state, then decide
    // per element whether it is carried (visible before AND placeholder in
    // the new state) and retarget at once, so a missing element starts its
    // fade on this very tick.
    property int _settle: 0
    Connections {
        target: root.choreo
        ignoreUnknownSignals: true
        function onAboutToChange(): void {
            for (const el of [art, title, clock]) {
                el.wasShown = el.shown
                el.snap = el.presence
            }
        }
        function onTransitioned(): void {
            for (const el of [art, title, clock])
                el.carried = el.wasShown && el.snap > 0.01
            root._settle = 45
            settleTimer.restart()
            root.retarget()
        }
        // The pill can change size WITHOUT a state change (lyrics start or
        // stop and the rest pill widens by the lyric band), which moves the
        // clock slot. Re-aim on every body resize, or the shared clock stays
        // parked at the old centre, on top of the lyric line.
        function onBodyWChanged(): void { root.retarget() }
        function onBodyHChanged(): void { root.retarget() }
    }

    // The rest clock slides from centre to the right slot as lyrics fade in
    // (IslandRestItem's lyricT), independently of any state change, so follow
    // the measured item itself as well.
    Connections {
        target: { const c = root._find("clock"); return c ? c.measure : null }
        ignoreUnknownSignals: true
        function onXChanged(): void { root.retarget() }
        function onWidthChanged(): void { root.retarget() }
    }
    onPlaceholdersChanged: root.retarget()
    Component.onCompleted: root.retarget()

    // Page reveals animate with NumberAnimations, which do not tick Motion,
    // so rects are re-read for a short window after a state change.
    Timer {
        id: settleTimer
        interval: 16
        repeat: true
        onTriggered: {
            root.retarget()
            root._settle--
            if (root._settle <= 0) stop()
        }
    }

    // Motion ticks only while a MotionValue is in flight (Motion.activeCount
    // > 0), so this costs nothing at rest.
    Connections {
        target: Motion
        function onNowChanged(): void {
            if (Motion.activeCount > 0) root.retarget()
        }
    }
}
