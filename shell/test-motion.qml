// Tests the closed-form damped-oscillator MotionValue/Motion
// (docs/superpowers/specs/2026-09-23-blob-rebuild-design.md section 2).
import QtQuick
import "core"

Item {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    MotionValue { id: a; unit: "px"; omega: 18; zeta: 0.92 }
    MotionValue { id: b; unit: "ratio"; omega: 22; zeta: 0.88 }

    // A tiny-step explicit-Euler numeric reference integrator, independent
    // of MotionValue's own closed-form code, used to cross-check it. dt is
    // small enough (1e-5s) that its own integration error is negligible
    // against the tolerances used below.
    function numericReference(y0, v0, omega, zeta, t) {
        const dt = 0.00001
        let y = y0, v = v0
        let elapsed = 0
        while (elapsed < t) {
            const step = Math.min(dt, t - elapsed)
            const acc = -omega * omega * y - 2 * zeta * omega * v
            v += acc * step
            y += v * step
            elapsed += step
        }
        return { y: y, v: v }
    }

    Timer {
        interval: 60; running: true; repeat: false
        onTriggered: root.phase1()
    }

    function phase1() {
        // 1. CONTINUITY ACROSS RETARGET -- the single most important check.
        //    Retargeting mid-flight must carry over BOTH the current
        //    position and the current velocity into the new solution; the
        //    always-true invariant (not "it overshoots") is that neither is
        //    discarded at the instant of retarget.
        a.snap(); a.value = 0; a.target = 400
        for (let i = 0; i < 40; i++) a.step(Motion.h)     // mid-flight
        const x0 = a.value, v0 = a.velocity
        a.target = 0                                      // retarget, no step between
        ok("continuity_position", Math.abs(a.value - x0) < 1e-9, "x " + x0.toFixed(4))
        ok("continuity_velocity", Math.abs(a.velocity - v0) < 1e-9, "v " + v0.toFixed(4))
        ok("velocity_was_nonzero", Math.abs(v0) > 1.0, "v " + v0.toFixed(2))

        // 2. FRAME-RATE INDEPENDENCE. Closed-form is exact, so summing to
        //    the same elapsed time via different step counts/sizes must
        //    agree far more tightly than an Euler integrator ever could.
        function run(dtMs, steps) {
            const m = Qt.createQmlObject('import QtQuick; import "core"; MotionValue { unit:"px"; omega:18; zeta:0.92 }', root)
            m.snap(); m.value = 0; m.target = 400
            for (let i = 0; i < steps; i++) m.step(dtMs / 1000.0)
            const v = m.value; m.destroy(); return v
        }
        const at60 = run(16.667, 30)   // ~0.5s
        const at120 = run(8.333, 60)   // ~0.5s
        ok("framerate_independent", Math.abs(at60 - at120) < 0.01,
           "60Hz " + at60.toFixed(4) + "  120Hz " + at120.toFixed(4))

        // 3. STABILITY AT STIFFNESS -- the exact regime where Qt's
        //    SpringAnimation was measured to diverge (156% overshoot,
        //    negative zeta at spring:160).
        const s = Qt.createQmlObject('import QtQuick; import "core"; MotionValue { unit:"px"; omega:60; zeta:0.9 }', root)
        s.snap(); s.value = 0; s.target = 100
        let peak = 0
        for (let i = 0; i < 2400; i++) { s.step(Motion.h); if (s.value > peak) peak = s.value }
        const overshootPct = (peak - 100)
        ok("stiff_spring_stable", isFinite(peak) && overshootPct < 5 && peak > 95,
           "peak " + peak.toFixed(2) + " (overshoot " + overshootPct.toFixed(2) + "%)")
        s.destroy()

        // 4. OVERSHOOT MATCHES THEORY: exp(-zeta*pi/sqrt(1-zeta^2))
        const p = Qt.createQmlObject('import QtQuick; import "core"; MotionValue { unit:"px"; omega:18; zeta:0.5 }', root)
        p.snap(); p.value = 0; p.target = 100
        let pk = 0
        for (let i = 0; i < 2400; i++) { p.step(Motion.h); if (p.value > pk) pk = p.value }
        const predicted = 100 * (1 + Math.exp(-0.5 * Math.PI / Math.sqrt(1 - 0.25)))
        ok("overshoot_matches_theory", Math.abs(pk - predicted) < 2.0,
           "measured " + pk.toFixed(2) + "  predicted " + predicted.toFixed(2))
        p.destroy()

        // 5. REST + SLEEP: it must actually stop, and deregister.
        a.snap(); a.value = 0; a.target = 50
        let steps = 0
        while (!a.atRest() && steps < 4800) { a.step(Motion.h); steps++ }
        a.commit()
        ok("reaches_rest", a.atRest(), "after " + (steps / 240).toFixed(2) + "s")
        ok("deregisters_at_rest", !a.active && Motion.activeCount === 0,
           "activeCount " + Motion.activeCount)

        // 6. PER-UNIT EPSILONS are actually different.
        ok("per_unit_epsilons", a.restSpeed === 1.0 && b.restSpeed === 0.01,
           "px " + a.restSpeed + "  ratio " + b.restSpeed)

        // 7. NUMERIC REFERENCE CROSS-CHECK, all three damping regimes.
        //    Compares MotionValue.step() (closed form) directly against an
        //    independent tiny-step Euler integrator over the same y0/v0.
        const cases = [
            { omega: 18, zeta: 0.5, label: "underdamped" },
            { omega: 18, zeta: 1.0, label: "critical" },
            { omega: 18, zeta: 1.8, label: "overdamped" }
        ]
        for (const c of cases) {
            const m = Qt.createQmlObject(
                'import QtQuick; import "core"; MotionValue { unit:"px" }', root)
            m.omega = c.omega; m.zeta = c.zeta
            m.snap(); m.value = -37; m.target = 0   // y0 = -37, v0 = 0
            const t = 0.35
            m.step(t)
            const ref = root.numericReference(-37, 0, c.omega, c.zeta, t)
            const closedY = m.value  // target is 0, so value == y
            const closedV = m.velocity
            ok("numeric_ref_" + c.label + "_position",
                Math.abs(closedY - ref.y) < 0.05,
                "closed " + closedY.toFixed(4) + "  numeric " + ref.y.toFixed(4))
            ok("numeric_ref_" + c.label + "_velocity",
                Math.abs(closedV - ref.v) < 0.5,
                "closed " + closedV.toFixed(4) + "  numeric " + ref.v.toFixed(4))
            m.destroy()
        }

        // 8. RETARGET PRESERVES VELOCITY THROUGH A SIGN FLIP -- retarget
        //    while moving toward the OLD target, immediately after
        //    retargeting to a new one, the closed-form basis (x0,v0,t0) must
        //    still report the pre-retarget velocity at t=0.
        const rv = Qt.createQmlObject('import QtQuick; import "core"; MotionValue { unit:"px"; omega:20; zeta:0.7 }', root)
        rv.snap(); rv.value = 0; rv.target = 100
        rv.step(0.05)
        const preV = rv.velocity
        rv.target = -50
        ok("retarget_velocity_sign_flip_preserved",
            Math.abs(rv.velocity - preV) < 1e-9, "v " + rv.velocity.toFixed(4))
        rv.destroy()

        // 9. ASYMMETRIC PRESET LOCKS DIRECTION AT RETARGET, NOT PER FRAME --
        //    reproduces the "vibration" bug: omega/zeta bound directly to
        //    `target >= value` re-evaluate every frame as value moves, and
        //    can flip mid-flight (eg. underdamped overshoot ringing back
        //    through the target), silently rewriting the ODE out from under
        //    its own (x0,v0,t0) basis. omegaEnter/omegaExit must be chosen
        //    ONCE, at the retarget, and stay fixed for that whole leg even
        //    as value crosses target during an underdamped overshoot.
        const asym = Qt.createQmlObject(
            'import QtQuick; import "core"; MotionValue { unit:"px"; ' +
            'omegaEnter: 30; zetaEnter: 0.5; omegaExit: 10; zetaExit: 1.0 }',
            root)
        asym.snap(); asym.value = 0; asym.target = 100  // entering: omega 30, zeta 0.5 (underdamped -> overshoots)
        ok("asymmetric_locks_enter_params", asym.omega === 30 && asym.zeta === 0.5,
            "omega " + asym.omega + " zeta " + asym.zeta)
        let overshot = false
        let flips = 0
        let lastOmega = asym.omega
        for (let i = 0; i < 2000 && asym.active; i++) {
            asym.step(Motion.h)
            if (asym.value > asym.target) overshot = true
            if (asym.omega !== lastOmega) { flips++; lastOmega = asym.omega }
        }
        ok("asymmetric_overshoots_as_expected", overshot, "underdamped enter should overshoot 100")
        ok("asymmetric_params_never_flip_mid_flight", flips === 0,
            "omega changed " + flips + " times while running toward one target")
        asym.destroy()

        console.log("=== MOTION TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
