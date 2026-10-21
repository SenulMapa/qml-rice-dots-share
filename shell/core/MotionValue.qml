import QtQuick
import "."

/**
 * MotionValue — one spring-driven scalar, closed-form damped oscillator.
 *
 * USE IT AS A LEAF SIGNAL. This is the load-bearing rule of the whole motion
 * layer:
 *
 *     MotionValue { id: w; target: open ? 700 : 185 }
 *     Rectangle { width: w.value }          // GOOD -- leaf property
 *
 * and never:
 *
 *     Rectangle { width: w.value }          // BAD if children then bind to
 *     Text { width: parent.width - 28 }     // parent.width, Layout.fillWidth,
 *                                           // or anchors.fill during motion
 *
 * CANCELLATION IS NOT RESTART. Assigning `target` mid-flight retargets from
 * the CURRENT value and velocity at the CURRENT frame time -- x0, v0, t0 are
 * re-captured on every retarget, so an interrupted animation carries its
 * momentum into the new solution. That single property is what a
 * duration-based clip can never do, because it has no velocity to carry.
 *
 * CLOSED FORM. x(t) solves m*x'' + c*x' + k*(x-target) = 0 analytically for
 * all three damping regimes (under/critically/over-damped), evaluated at
 * whatever t the shared Motion clock is at. No fixed-step accumulator, no
 * per-substep error accumulation: the position and velocity at any t are
 * exact, so two callers evaluating at the same t always agree exactly,
 * regardless of how many frames it took either of them to get there.
 */
QtObject {
    id: mv

    property real target: 0
    property real value: 0
    property real velocity: 0

    property real omega: Motion.omegaDefault
    property real zeta: Motion.zetaDefault
    property real mass: 1.0

    /**
     * Optional ASYMMETRIC preset (enter vs exit omega/zeta), e.g. a
     * slightly underdamped "growing" spring and a critically-damped
     * "shrinking" one. When omegaEnter is set (non-NaN) the direction
     * (entering = target >= value) is decided EXACTLY ONCE, at the
     * moment of retarget (onTargetChanged, before _rebase()), and
     * omega/zeta are set from it for the rest of that leg of travel.
     *
     * THIS IS LOAD-BEARING. The anti-pattern this replaces --
     * `zeta: target >= value ? Motion.zetaEnter : Motion.zetaExit`
     * declared directly on omega/zeta -- re-evaluates every frame
     * because `value` is reassigned every frame by evaluate(). Near an
     * overshoot crossing (underdamped enter ringing back through the
     * target) or simply while approaching asymptotically, that
     * comparison can flip frame-to-frame, which silently rewrites
     * omega/zeta out from under a closed-form solution whose (x0, v0,
     * t0) basis was captured under the OLD omega/zeta -- the position/
     * velocity at the next frame is no longer a continuous function of
     * the previous one, which reads as literal vibration. Locking the
     * choice at retarget time keeps one consistent ODE for the whole
     * leg, same as any other omega/zeta the caller sets directly.
     */
    property real omegaEnter: NaN
    property real zetaEnter: NaN
    property real omegaExit: NaN
    property real zetaExit: NaN
    readonly property bool _asymmetric: !isNaN(omegaEnter)

    /**
     * Rest thresholds are PER UNIT (see historical note: a shared restSpeed
     * of 0.01 meant "at rest when moving slower than one pixel per 100
     * seconds", so nothing ever reached rest and the frame clock never
     * slept).
     *   px    : 0.1px is below one device pixel; 1px/s needs a full second to
     *           move a single pixel.
     *   ratio : scale and opacity live in 0..1, so they need 100x finer.
     */
    property string unit: "px"
    readonly property real restDelta: unit === "ratio" ? 0.001 : 0.1
    readonly property real restSpeed: unit === "ratio" ? 0.01 : 1.0

    property bool active: false

    /**
     * When true the value SNAPS to target instead of springing -- the
     * Behavior `enabled: false` escape hatch for targets already being
     * interpolated frame-by-frame by their owner.
     */
    property bool immediate: false
    onImmediateChanged: if (immediate) snap()

    // ---- closed-form solution state ------------------------------------
    // Captured at every retarget/snap: the solution is always evaluated
    // relative to this basis, i.e. y(t) = x(t0+t) - target, y(0) = x0-target,
    // y'(0) = v0.
    property real _t0: 0
    property real _x0: 0
    property real _v0: 0

    // Seed from the initial target. Without this, value starts at 0 and every
    // MotionValue animates in from nothing at launch.
    Component.onCompleted: snap()

    // A MotionValue still mid-flight when its owner is torn down must drop
    // out of Motion's registry here, or Motion.tick()'s registry holds a
    // dangling reference and evaluating it throws every frame forever.
    Component.onDestruction: if (active) Motion.unregister(mv)

    onTargetChanged: {
        if (Motion.reduceMotion || immediate) { snap(); return }
        if (_asymmetric) {
            const entering = target >= value
            omega = entering ? omegaEnter : omegaExit
            zeta = entering ? zetaEnter : zetaExit
        }
        _rebase()
        if (!atRest()) kick()
    }

    // Re-capture the basis (x0, v0, t0) from the CURRENT value/velocity/now,
    // without changing value or velocity. Called on every retarget so the
    // closed-form solution continues from exactly where the old one was.
    function _rebase() {
        _t0 = Motion.now
        _x0 = value
        _v0 = velocity
    }

    function kick() {
        if (Motion.reduceMotion || immediate) { snap(); return }
        if (!active) {
            active = true
            Motion.register(mv)
        }
    }

    function atRest() {
        return Math.abs(target - value) < restDelta && Math.abs(velocity) < restSpeed
    }

    /** Jump with no motion; used for first paint and for reduced motion. */
    function snap() {
        value = target
        velocity = 0
        _t0 = Motion.now
        _x0 = value
        _v0 = 0
        if (active) { active = false; Motion.unregister(mv) }
    }

    /**
     * Evaluate the closed-form solution at absolute time `nowSeconds` and
     * commit value/velocity. Called by Motion.tick() once per frame for
     * every registered (active) MotionValue.
     */
    function evaluate(nowSeconds) {
        const t = nowSeconds - _t0
        const r = _solve2(_x0 - target, _v0, t)
        value = target + r.y
        velocity = r.v
        if (atRest()) snap()
    }

    /**
     * Advance by exactly `h` seconds using the CURRENT value/velocity as the
     * initial condition (not the retarget-time basis) -- exact, not an Euler
     * approximation, so a loop of N calls with total time T gives the same
     * end state as one call with t=T, up to floating-point rounding. This is
     * the manual-stepping entry point (tests, anything wanting to drive a
     * MotionValue by hand outside Motion.tick()/evaluate()); it tolerates
     * `value`/`velocity` having been written to directly between calls,
     * which evaluate()'s persisted (_x0, _v0, _t0) basis does not.
     */
    function step(h) {
        const y0 = value - target
        const r = _solve2(y0, velocity, h)
        value = target + r.y
        velocity = r.v
        if (active) _rebase()
        if (atRest()) { if (active) { active = false; Motion.unregister(mv) } }
    }

    /** Called after Motion.tick() finishes a frame; parks at-rest values. */
    function commit() {
        if (atRest()) snap()
    }

    /**
     * Closed-form solution of y'' + 2*zeta*omega*y' + omega^2*y = 0
     * (relative to target, mass folded into omega/zeta as m*omega^2=k,
     * m*2*zeta*omega=c) with y(0)=y0, y'(0)=v0, evaluated at t. Returns
     * {y, v}. Pure function of its arguments -- no dependency on `mv`'s
     * persisted basis, so both step() (current value/velocity as IC) and
     * evaluate() (the retarget-time basis) can share it.
     */
    function _solve2(y0, v0, t) {
        if (t <= 0) return { y: y0, v: v0 }

        const w = omega
        const z = zeta

        if (w <= 0) return { y: y0, v: v0 }

        if (z < 1.0 - 1e-9) {
            // Underdamped.
            const wd = w * Math.sqrt(1 - z * z)
            const e = Math.exp(-z * w * t)
            const c = Math.cos(wd * t)
            const s = Math.sin(wd * t)
            const B = (v0 + z * w * y0) / wd
            const y = e * (y0 * c + B * s)
            const term2 = -z * w * B - y0 * wd
            const v = e * (v0 * c + term2 * s)
            return { y: y, v: v }
        } else if (z > 1.0 + 1e-9) {
            // Overdamped.
            const wd2 = w * Math.sqrt(z * z - 1)
            const r1 = -z * w + wd2
            const r2 = -z * w - wd2
            const C1 = (v0 - r2 * y0) / (r1 - r2)
            const C2 = y0 - C1
            const e1 = Math.exp(r1 * t)
            const e2 = Math.exp(r2 * t)
            const y = C1 * e1 + C2 * e2
            const v = C1 * r1 * e1 + C2 * r2 * e2
            return { y: y, v: v }
        } else {
            // Critically damped (zeta == 1, within tolerance).
            const e = Math.exp(-w * t)
            const B = v0 + w * y0
            const y = e * (y0 + B * t)
            const v = e * (v0 - w * B * t)
            return { y: y, v: v }
        }
    }
}
