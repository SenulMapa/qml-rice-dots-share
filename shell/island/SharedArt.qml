import QtQuick
import Quickshell.Widgets
import "../core"
import "../services"

/**
 * SharedArt -- the single album-art instance of the ink shared-element layer
 * (island/SharedElements.qml). Morphs between the rects its placeholders
 * report. Only x/y/w/h/radius and opacity/scale are animated; the image is
 * never relaid out.
 */
Item {
    id: root

    // Same smooth body spring Island.qml uses for bodyW/bodyH.
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
    MotionValue { id: rMV; omega: root.omega; zeta: root.zeta; unit: "px" }

    // x is held in centre-relative coordinates (see SharedElements) so a
    // widening body never drags the element sideways.
    x: xMV.value + (root.parent ? root.parent.width / 2 : 0)
    y: yMV.value + root.lift
    width: wMV.value
    height: hMV.value
    opacity: root.presence
    scale: root.shrink
    transformOrigin: Item.Center

    ClippingRectangle {
        anchors.fill: parent
        radius: rMV.value
        color: Theme.inkRaised

        Image {
            anchors.fill: parent
            source: MediaService.artwork
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: status === Image.Ready
        }
    }

    // Snap a MotionValue to v with no travel (used when the art appears
    // from nothing, so it fades in at its target instead of flying there).
    function _jump(mv, v) {
        mv.value = v
        mv.velocity = 0
        mv.target = v
    }

    // Morph onto a placeholder rect in overlay coordinates.
    function aimAt(px, py, pw, ph, pr) {
        if (!root.shown) {
            _jump(xMV, px); _jump(yMV, py); _jump(wMV, pw); _jump(hMV, ph); _jump(rMV, pr)
            root.shown = true
        }
        xMV.target = px
        yMV.target = py
        wMV.target = pw
        hMV.target = ph
        rMV.target = pr
        // A fresh element sits exactly on its placeholder; only a carried
        // one springs from its current rect.
        if (!root.carried) {
            _jump(xMV, px); _jump(yMV, py); _jump(wMV, pw); _jump(hMV, ph); _jump(rMV, pr)
        }
    }

    // No live placeholder in the active state: shrink and fade where it is.
    function fadeOut() {
        root.shown = false
    }
}
