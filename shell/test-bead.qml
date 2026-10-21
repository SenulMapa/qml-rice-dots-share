// Component test for components/Bead.qml. A 1x1 transparent PanelWindow
// supplies the same real render loop production has (see
// test-motion-live.qml) -- Bead's geometry is entirely derived from live
// MotionValue springs driven by core/Motion.qml's FrameAnimation, so this
// exercises the real clock rather than hand-stepping.
//
// Checks: first show appears in place (no fly-in from 0,0), a long hop
// (>= flightThreshold) takes the arc path, a short hop (< flightThreshold)
// does not, form changes morph (debugOpacity fades through an "off" leg)
// rather than pop, everything settles back to debugBusy === false, and
// once settled the shared Motion clock actually stops (nothing ticks at
// rest).
import QtQuick
import Quickshell
import "components"
import "core"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    function near(a, b, tol) { return Math.abs(a - b) <= tol }

    PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 1; implicitHeight: 1
        exclusiveZone: 0
        color: "transparent"
    }

    // ---- first-show probe: target set at declaration, never moved. ----
    Bead {
        id: firstShow
        form: "dot"
        target: Qt.point(120, 40)
    }

    // ---- long-hop probe: starts at rest, then a >=30px (flightThreshold) move. ----
    Bead {
        id: longHop
        form: "dot"
        target: Qt.point(0, 0)
    }

    // ---- short-hop probe: starts at rest, then a small move. ----
    Bead {
        id: shortHop
        form: "dot"
        target: Qt.point(0, 0)
    }

    // ---- form-morph probe. ----
    Bead {
        id: morpher
        form: "dot"
        target: Qt.point(0, 0)
    }

    // t=0ms, deferred past construction: first paint must already be in
    // place -- no spring activity, position already at target.
    Timer {
        interval: 0; running: true; repeat: false
        onTriggered: {
            root.ok("first_show_in_place",
                root.near(firstShow.debugPos.x, 120, 0.5) && root.near(firstShow.debugPos.y, 40, 0.5),
                "" + firstShow.debugPos.x + "," + firstShow.debugPos.y)
            root.ok("first_show_not_busy", !firstShow.debugBusy, "" + firstShow.debugBusy)

            // Kick off the hop probes.
            longHop.target = Qt.point(200, 0)      // 200px >= threshold -> arc
            shortHop.target = Qt.point(12, 0)      // 12px < threshold -> straight
        }
    }

    // t=40ms: both hops should be mid-flight now.
    Timer {
        interval: 40; running: true; repeat: false
        onTriggered: {
            root.ok("long_hop_is_arc", longHop.debugIsArc, "" + longHop.debugIsArc)
            root.ok("short_hop_not_arc", !shortHop.debugIsArc, "" + shortHop.debugIsArc)
            root.ok("long_hop_moving", longHop.debugBusy, "" + longHop.debugBusy)
            root.ok("short_hop_moving", shortHop.debugBusy, "" + shortHop.debugBusy)

            // Form morph: dot -> off -> ring, sampled below.
            morpher.form = "off"
        }
    }

    // t=90ms: mid-morph into "off" -- should be fading, not popped straight
    // to invisible, and still busy (springs mid-flight).
    Timer {
        interval: 90; running: true; repeat: false
        onTriggered: {
            root.ok("morph_off_fading",
                morpher.debugOpacity > 0.01 && morpher.debugOpacity < 0.99,
                "" + morpher.debugOpacity)
            morpher.form = "ring"
        }
    }

    // t=900ms: everything given ample real time to settle.
    Timer {
        interval: 900; running: true; repeat: false
        onTriggered: {
            root.ok("long_hop_settled_at_target",
                root.near(longHop.debugPos.x, 200, 0.5) && root.near(longHop.debugPos.y, 0, 0.5),
                "" + longHop.debugPos.x + "," + longHop.debugPos.y)
            root.ok("short_hop_settled_at_target",
                root.near(shortHop.debugPos.x, 12, 0.5) && root.near(shortHop.debugPos.y, 0, 0.5),
                "" + shortHop.debugPos.x + "," + shortHop.debugPos.y)
            root.ok("long_hop_not_busy_at_rest", !longHop.debugBusy, "" + longHop.debugBusy)
            root.ok("short_hop_not_busy_at_rest", !shortHop.debugBusy, "" + shortHop.debugBusy)
            root.ok("morpher_settled_visible_ring",
                root.near(morpher.debugOpacity, 1, 0.02), "" + morpher.debugOpacity)
            root.ok("morpher_not_busy_at_rest", !morpher.debugBusy, "" + morpher.debugBusy)
            root.ok("nothing_ticks_at_rest",
                Motion.activeCount === 0 && !Motion.clock.running,
                "activeCount=" + Motion.activeCount + " clockRunning=" + Motion.clock.running)

            console.log("=== BEAD TEST ===")
            for (const line of root.log) console.log(line)
            const failed = root.log.filter(l => l.startsWith("FAIL")).length
            console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
            Qt.quit()
        }
    }
}
