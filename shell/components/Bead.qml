import QtQuick
import "../core"
import "../services"

/**
 * Bead -- the shell's selection indicator. Spring-driven travel, not a
 * duration clip: a target that moves mid-flight bends the path instead of
 * restarting it, same continuity contract as core/MotionValue.qml and
 * island/WorkspacePillRow.qml's arc dot (which this generalises to 2D and
 * to more than one shape).
 *
 * Motion architecture credit: the state machine here -- spring-driven
 * travel, an arc flight for long hops vs. a straight glide for short ones,
 * velocity-driven squash-and-stretch, and morphing between named forms --
 * is adapted from Ame (components/Ame.qml) in Ukishima
 * (github.com/amanhex/Ukishima, MIT License, (c) amanhex). Ame is a
 * duration-animated flame-glass bead with canvas rendering; this is a
 * flat, borderless reimplementation on the shell's own MotionValue spring
 * engine -- the feel is borrowed, not the look.
 *
 * Forms: "dot" (small filled circle), "caret" (tall thin capsule), "bar"
 * (short wide capsule), "ring" (a stroked circle, no fill), "off" (hidden).
 * Every form dimension is its own spring, so a form change morphs smoothly
 * instead of popping.
 *
 * Travel: `target` is a point in the parent's coordinate space. Hops
 * shorter than `flightThreshold` glide straight; longer hops fly a
 * quadratic-bezier arc, its control point offset perpendicular to the
 * travel line by ~22% of the distance (arc side latched at flight start so
 * a target crossing the travel line mid-flight doesn't mirror the curve in
 * one frame). A retarget while already moving does NOT restart the flight
 * -- it just bends the live curve toward the new point, and the position
 * springs' own natural overshoot supplies the settle wobble.
 *
 * Rest: every moving part is a MotionValue, so once everything is on
 * target Motion.qml's active-list clock drops this to zero cost -- no
 * Timer, no FrameAnimation, nothing ticks.
 */
Item {
    id: root

    property point target: Qt.point(0, 0)
    property string form: "dot" // dot | caret | bar | ring | off
    property color color: AdaptiveColor.activeFill
    property real dotSize: Theme.u(0.12)

    // Hops shorter than this glide straight; longer hops fly an arc.
    // ~30px at the default Theme.unit (44).
    readonly property real flightThreshold: Theme.u(0.68)

    implicitWidth: dotSize * 3
    implicitHeight: dotSize * 3

    // ---- per-form target geometry -----------------------------------
    readonly property var formDims: ({
        dot:   { w: dotSize,       h: dotSize,       r: dotSize / 2,    ring: 0,               fillA: 1 },
        caret: { w: dotSize * 0.42, h: dotSize * 2.1, r: dotSize * 0.21, ring: 0,               fillA: 1 },
        bar:   { w: dotSize * 2.6,  h: dotSize * 0.55, r: dotSize * 0.275, ring: 0,             fillA: 1 },
        ring:  { w: dotSize * 1.9,  h: dotSize * 1.9, r: dotSize * 0.95, ring: dotSize * 0.22,  fillA: 0 },
        off:   { w: dotSize,       h: dotSize,       r: dotSize / 2,    ring: 0,               fillA: 1 }
    })
    readonly property var dims: root.formDims[root.form] || root.formDims.dot

    // ---- travel: position springs + latched flight geometry ---------
    property MotionValue posX: MotionValue { unit: "px"; omega: 20.0; zeta: 0.86; target: root.target.x }
    property MotionValue posY: MotionValue { unit: "px"; omega: 20.0; zeta: 0.86; target: root.target.y }

    property point flightFrom: Qt.point(0, 0)
    property point _lastTarget: Qt.point(0, 0)
    property bool arcFlip: false
    property bool _ready: false

    Component.onCompleted: {
        _lastTarget = root.target
        flightFrom = root.target
        _ready = true
    }

    // Starts a new flight only when the bead is currently at rest -- a
    // retarget while already moving bends the live curve instead (see
    // flightDist/progAlong below, which are always computed against the
    // CURRENT target, not a frozen one).
    onTargetChanged: {
        if (!_ready)
            return
        const dx = root.target.x - root._lastTarget.x
        const dy = root.target.y - root._lastTarget.y
        if (Math.hypot(dx, dy) > 0.5 && !root.posX.active && !root.posY.active) {
            root.flightFrom = Qt.point(root.posX.value, root.posY.value)
            root.arcFlip = root.target.x > root.flightFrom.x
        }
        root._lastTarget = root.target
    }

    readonly property real flightDx: root.target.x - root.flightFrom.x
    readonly property real flightDy: root.target.y - root.flightFrom.y
    readonly property real flightDist: Math.hypot(root.flightDx, root.flightDy)
    readonly property bool isArc: root.flightDist >= root.flightThreshold

    // Progress of the live position along the from->target line, via
    // vector projection (not raw distance ratio) so a slightly-overshot
    // spring still reports a sane 0..1 for the arc bump.
    readonly property real progAlong: root.flightDist < 0.5 ? 1
        : Math.max(0, Math.min(1,
            ((root.posX.value - root.flightFrom.x) * root.flightDx
                + (root.posY.value - root.flightFrom.y) * root.flightDy)
                / (root.flightDist * root.flightDist)))

    readonly property real arcMag: root.flightDist * 0.22
    readonly property real perpX: root.flightDist > 0.001 ? -root.flightDy / root.flightDist : 0
    readonly property real perpY: root.flightDist > 0.001 ? root.flightDx / root.flightDist : 0
    readonly property real arcSign: root.arcFlip ? -1 : 1
    readonly property real arcBump: root.isArc
        ? root.arcMag * Math.sin(Math.PI * root.progAlong) * root.arcSign : 0

    readonly property real bx: root.posX.value + root.perpX * root.arcBump
    readonly property real by: root.posY.value + root.perpY * root.arcBump

    // ---- velocity-driven squash and stretch --------------------------
    readonly property real speed: Math.hypot(root.posX.velocity, root.posY.velocity)
    readonly property real headingRad: root.speed > 1
        ? Math.atan2(root.posY.velocity, root.posX.velocity) : 0
    readonly property real stretch: Math.min(0.4, root.speed / 640.0)

    // ---- shape springs: every form dimension morphs, never snaps -----
    property MotionValue shapeW: MotionValue { unit: "px"; omega: Motion.omegaEnter; zeta: Motion.zetaEnter; target: root.dims.w }
    property MotionValue shapeH: MotionValue { unit: "px"; omega: Motion.omegaEnter; zeta: Motion.zetaEnter; target: root.dims.h }
    property MotionValue shapeR: MotionValue { unit: "px"; omega: Motion.omegaEnter; zeta: Motion.zetaEnter; target: root.dims.r }
    property MotionValue ringW: MotionValue { unit: "px"; omega: Motion.omegaEnter; zeta: Motion.zetaEnter; target: root.dims.ring }
    property MotionValue fillA: MotionValue { unit: "ratio"; omega: Motion.omegaEnter; zeta: Motion.zetaEnter; target: root.dims.fillA }
    property MotionValue offA: MotionValue { unit: "ratio"; omega: Motion.omegaEnter; zeta: Motion.zetaEnter; target: root.form === "off" ? 0 : 1 }

    // True while any spring is off-target -- a host may use this to show
    // the bead only during travel/morph (WorkspacePillRow) or to leave it
    // always mounted (a persistent tab/list selection indicator).
    readonly property bool moving: root.posX.active || root.posY.active
        || root.shapeW.active || root.shapeH.active || root.shapeR.active
        || root.ringW.active || root.fillA.active || root.offA.active

    // Testability/observability seam -- test-bead.qml only.
    readonly property alias debugBusy: root.moving
    readonly property point debugPos: Qt.point(root.bx, root.by)
    readonly property alias debugIsArc: root.isArc
    readonly property alias debugOpacity: shape.opacity

    // Springs overshoot slightly by design (zetaEnter 0.88) -- clamp the
    // few outputs that feed APIs intolerant of out-of-range input (Qt.alpha
    // warns on a negative alpha; a negative width/radius would just look
    // wrong) rather than fighting the overshoot itself.
    function clamp01(u) { return Math.max(0, Math.min(1, u)); }
    function clampMin0(u) { return Math.max(0, u); }

    Rectangle {
        id: shape
        width: root.clampMin0(root.shapeW.value)
        height: root.clampMin0(root.shapeH.value)
        radius: root.clampMin0(root.shapeR.value)
        x: root.bx - width / 2
        y: root.by - height / 2
        color: Qt.alpha(root.color, root.clamp01(root.fillA.value))
        border.width: root.clampMin0(root.ringW.value)
        border.color: root.color
        opacity: root.clamp01(root.offA.value)
        visible: opacity > 0.003

        transform: [
            Rotation { angle: root.headingRad * 180 / Math.PI; origin.x: shape.width / 2; origin.y: shape.height / 2 },
            Scale { xScale: 1 + root.stretch; yScale: 1 / (1 + root.stretch * 0.6); origin.x: shape.width / 2; origin.y: shape.height / 2 },
            Rotation { angle: -root.headingRad * 180 / Math.PI; origin.x: shape.width / 2; origin.y: shape.height / 2 }
        ]
    }
}
