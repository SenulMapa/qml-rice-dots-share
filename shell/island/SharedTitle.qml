import QtQuick
import "../core"
import "../services"

/**
 * SharedTitle -- the single title + artist instance of the ink shared-element
 * layer (island/SharedElements.qml).
 *
 * Text never changes font size mid-flight. It renders at its LARGEST size
 * (title 20, artist 13) and is scaled down per state with a transform, so
 * glyphs stay crisp and nothing relayouts. The text box has a fixed unscaled
 * width, and the container clips it to the placeholder's visual width.
 */
Item {
    id: root

    readonly property real omega: Motion.presetSmooth().omega
        / Math.max(0.25, Config.appearance.motionScale)
    readonly property real zeta: Motion.presetSmooth().zeta

    // True while a state has a live placeholder for this element.
    property bool shown: false
    // Driven from SharedElements (choreography): opacity 0..1, a small
    // translateY lift while a fresh element is revealed, and the 0.98 scale
    // of an element that is fading out. All three are plain values; there
    // is no animation of their own except the reduced-motion/idle fade.
    property real presence: 0
    property real lift: 0
    property real shrink: 1
    // Present in both the previous and the new state: it morphs, never hides.
    property bool carried: false
    property real snap: 0
    property bool wasShown: false
    // Set by SharedElements while a choreographed transition is in flight.
    property bool busy: false
    Behavior on presence {
        enabled: Config.appearance.ink && (Motion.reduceMotion || !root.busy)
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }
    visible: presence > 0.001

    MotionValue { id: xMV; omega: root.omega; zeta: root.zeta; unit: "px" }
    MotionValue { id: yMV; omega: root.omega; zeta: root.zeta; unit: "px" }
    MotionValue { id: wMV; omega: root.omega; zeta: root.zeta; unit: "px" }
    MotionValue { id: hMV; omega: root.omega; zeta: root.zeta; unit: "px" }
    MotionValue { id: tsMV; omega: root.omega; zeta: root.zeta; unit: "ratio"; value: 1; target: 1 }
    MotionValue { id: ssMV; omega: root.omega; zeta: root.zeta; unit: "ratio"; value: 1; target: 1 }

    x: xMV.value + (root.parent ? root.parent.width / 2 : 0)
    y: yMV.value + root.lift
    width: wMV.value
    height: hMV.value
    opacity: root.presence
    scale: root.shrink
    transformOrigin: Item.Center
    clip: true

    // Largest sizes: title 20/600, artist 13/500.
    Text {
        id: titleText
        x: 0
        y: 0
        width: 300
        text: MediaService.title
        color: Theme.t1
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: Theme.fontUi
        font.pixelSize: 20
        font.weight: Font.DemiBold
        font.letterSpacing: -0.3
        transformOrigin: Item.TopLeft
        scale: tsMV.value
    }

    Text {
        id: artistText
        x: 0
        // The artist sits under the title's VISUAL height, not its layout one.
        y: titleText.implicitHeight * tsMV.value + 2
        width: 300
        text: MediaService.artist
        color: Theme.t2
        elide: Text.ElideRight
        maximumLineCount: 1
        font.family: Theme.fontUi
        font.pixelSize: 13
        font.weight: Font.Medium
        transformOrigin: Item.TopLeft
        scale: ssMV.value
    }

    function _jump(mv, v) {
        mv.value = v
        mv.velocity = 0
        mv.target = v
    }

    // ts: title scale, ss: artist scale (both relative to their largest size).
    function aimAt(px, py, pw, ph, ts, ss) {
        if (!root.shown) {
            _jump(xMV, px); _jump(yMV, py); _jump(wMV, pw); _jump(hMV, ph)
            _jump(tsMV, ts); _jump(ssMV, ss)
            root.shown = true
        }
        xMV.target = px
        yMV.target = py
        wMV.target = pw
        hMV.target = ph
        tsMV.target = ts
        ssMV.target = ss
        if (!root.carried) {
            _jump(xMV, px); _jump(yMV, py); _jump(wMV, pw); _jump(hMV, ph)
            _jump(tsMV, ts); _jump(ssMV, ss)
        }
    }

    function fadeOut() {
        root.shown = false
    }
}
