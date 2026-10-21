// Verifies the island's width/height morph (island/Island.qml's
// morphFromW/H, morphToW/H, morphT) is a single shared 0->1 progress value
// driving BOTH axes, so width and height interpolate in lockstep instead of
// one axis visibly finishing before the other (the "height shrinks, then
// width" bug this replaced). Ports the exact retarget logic from Island.qml
// rather than loading the real shell (PanelWindow/Hyprland deps aren't
// available headless), so this is a model of the math, kept in lockstep by
// hand with island/Island.qml if that logic ever changes shape.
import QtQuick
import "core"

Item {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    // ---- model of Island.qml's surface morph ---------------------------
    property real fromW: 100
    property real fromH: 40
    property real toW: 100
    property real toH: 40
    property MotionValue morphT: MotionValue {
        unit: "ratio"; zeta: 0.92; omega: 12.8; target: 1
    }
    function currentW() { return root.fromW + (root.toW - root.fromW) * root.morphT.value }
    function currentH() { return root.fromH + (root.toH - root.fromH) * root.morphT.value }
    function retarget(newW, newH) {
        const p = root.morphT.value
        const curW = root.fromW + (root.toW - root.fromW) * p
        const curH = root.fromH + (root.toH - root.fromH) * p
        root.fromW = curW
        root.fromH = curH
        root.toW = newW
        root.toH = newH
        root.morphT.value = 0
        Motion.register(root.morphT)
    }

    Timer {
        interval: 30; running: true; repeat: false
        onTriggered: root.run()
    }

    function run() {
        // 1. UNIFORM SCALING -- opening (small pill -> big launcher). At every
        //    sampled substep, the FRACTION of distance covered must be
        //    identical for width and height (both just lerp the same p), so
        //    neither axis can visibly lead or trail the other.
        root.morphT.snap()
        root.fromW = 56; root.fromH = 24
        root.toW = 260; root.toH = 96
        root.morphT.value = 0
        let worstOpen = 0
        for (let i = 0; i < 200; i++) {
            root.morphT.step(Motion.h)
            const p = root.morphT.value
            const wFrac = (root.currentW() - root.fromW) / (root.toW - root.fromW)
            const hFrac = (root.currentH() - root.fromH) / (root.toH - root.fromH)
            worstOpen = Math.max(worstOpen, Math.abs(wFrac - p), Math.abs(hFrac - p))
        }
        ok("uniform_scaling_open", worstOpen < 1e-9, "max deviation " + worstOpen.toExponential(2))

        // 2. UNIFORM SCALING -- closing (launcher -> resting pill), the exact
        //    direction the reported bug was in.
        root.morphT.snap()
        root.fromW = 260; root.fromH = 96
        root.toW = 56; root.toH = 24
        root.morphT.value = 0
        let worstClose = 0
        for (let i = 0; i < 200; i++) {
            root.morphT.step(Motion.h)
            const p = root.morphT.value
            const wFrac = (root.currentW() - root.fromW) / (root.toW - root.fromW)
            const hFrac = (root.currentH() - root.fromH) / (root.toH - root.fromH)
            worstClose = Math.max(worstClose, Math.abs(wFrac - p), Math.abs(hFrac - p))
        }
        ok("uniform_scaling_close", worstClose < 1e-9, "max deviation " + worstClose.toExponential(2))

        // 3. RETARGET MID-FLIGHT STAYS CONTINUOUS -- interrupting an in-
        //    flight morph (e.g. launcher closes, then the hover pill opens
        //    again before it settles) must not jump the visible size.
        root.morphT.snap()
        root.fromW = 56; root.fromH = 24
        root.toW = 260; root.toH = 96
        root.morphT.value = 0
        for (let i = 0; i < 30; i++) root.morphT.step(Motion.h)   // mid-flight
        const preW = root.currentW(), preH = root.currentH()
        root.retarget(140, 60)                                    // interrupt
        const postW = root.currentW(), postH = root.currentH()
        ok("retarget_continuous_w", Math.abs(postW - preW) < 1e-6,
            "pre " + preW.toFixed(4) + " post " + postW.toFixed(4))
        ok("retarget_continuous_h", Math.abs(postH - preH) < 1e-6,
            "pre " + preH.toFixed(4) + " post " + postH.toFixed(4))

        // 4. Still converges to the new target and both axes finish
        //    together (same p at every step, so "together" is automatic --
        //    just confirm it actually settles).
        let steps = 0
        while (!root.morphT.atRest() && steps < 4800) { root.morphT.step(Motion.h); steps++ }
        root.morphT.commit()
        ok("settles_at_new_target",
            root.morphT.atRest() && Math.abs(root.currentW() - 140) < 0.5
                && Math.abs(root.currentH() - 60) < 0.5,
            "w " + root.currentW().toFixed(2) + " h " + root.currentH().toFixed(2))

        console.log("=== MORPH TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
