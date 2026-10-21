import QtQuick
import "../core"

/**
 * SharedClock -- the single clock instance of the ink shared-element layer
 * (island/SharedElements.qml). Centred on the placeholder's centre; the text
 * renders at its largest size (15/600) and is scaled per state, so the
 * rest clock (13) is scale 13/15 with no relayout.
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

    // Fixed box: the text is centred inside it, so a minute-rollover never
    // moves the centre.
    readonly property real boxW: 96
    readonly property real boxH: 20

    MotionValue { id: cxMV; omega: root.omega; zeta: root.zeta; unit: "px" }
    MotionValue { id: cyMV; omega: root.omega; zeta: root.zeta; unit: "px" }
    MotionValue { id: tsMV; omega: root.omega; zeta: root.zeta; unit: "ratio"; value: 1; target: 1 }

    x: cxMV.value + (root.parent ? root.parent.width / 2 : 0) - root.boxW / 2
    y: cyMV.value - root.boxH / 2 + root.lift
    width: root.boxW
    height: root.boxH
    opacity: root.presence
    transformOrigin: Item.Center
    scale: tsMV.value * root.shrink

    Text {
        anchors.fill: parent
        text: ShellState.time
        color: Theme.t1
        font.family: Theme.fontUi
        font.pixelSize: 15
        font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    function _jump(mv, v) {
        mv.value = v
        mv.velocity = 0
        mv.target = v
    }

    // (cx, cy) is the centre in overlay coordinates; ts is the text scale.
    function aimAt(cx, cy, ts) {
        if (!root.shown) {
            _jump(cxMV, cx); _jump(cyMV, cy); _jump(tsMV, ts)
            root.shown = true
        }
        cxMV.target = cx
        cyMV.target = cy
        tsMV.target = ts
        if (!root.carried) { _jump(cxMV, cx); _jump(cyMV, cy); _jump(tsMV, ts) }
    }

    function fadeOut() {
        root.shown = false
    }
}
