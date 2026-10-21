// Component test for WaveTrack. The case that matters most: disabling an
// ANCESTOR must stop the animation, because island surfaces hide with
// enabled:false + opacity:0 rather than visible:false.
import QtQuick
import Quickshell
import "components"
ShellRoot {
    id: root
    property var log: []
    property real p0: 0
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }
    PanelWindow {
        anchors { top: true; left: true }
        implicitWidth: 200
        implicitHeight: 24
        exclusiveZone: 0
        color: "transparent"
        Item {
            id: host
            anchors.fill: parent
            WaveTrack { id: w; y: 9; width: 180; height: 6; value: 0.5; playing: true }
        }
    }
    SequentialAnimation {
        running: true
        PauseAnimation { duration: 400 }
        ScriptAction { script: {
            root.ok("animates_when_playing_and_on_screen", w.animating, "animating=" + w.animating)
            root.p0 = w.phase
        } }
        PauseAnimation { duration: 300 }
        ScriptAction { script: {
            root.ok("wave_actually_travels", Math.abs(w.phase - root.p0) > 0.5,
                "phase " + root.p0.toFixed(2) + " -> " + w.phase.toFixed(2))
            host.enabled = false
        } }
        PauseAnimation { duration: 120 }
        ScriptAction { script: { root.p0 = w.phase } }
        PauseAnimation { duration: 300 }
        ScriptAction { script: {
            root.ok("disabled_ancestor_stops_animation", !w.animating, "animating=" + w.animating)
            root.ok("disabled_ancestor_freezes_phase", Math.abs(w.phase - root.p0) < 0.01,
                "phase " + root.p0.toFixed(3) + " -> " + w.phase.toFixed(3))
            host.enabled = true
            w.playing = false
        } }
        PauseAnimation { duration: 500 }
        ScriptAction { script: {
            root.ok("pause_stops_animation", !w.animating, "animating=" + w.animating)
            root.ok("pause_flattens_wave", w.amplitude < 0.05, "amplitude=" + w.amplitude.toFixed(3))
            w.active = false
            w.playing = true
        } }
        PauseAnimation { duration: 100 }
        ScriptAction { script: {
            root.ok("active_false_blocks_animation", !w.animating, "animating=" + w.animating)
            root.ok("path_built", w.wavePath.length > 40 && w.wavePath.indexOf(" Q ") > 0,
                w.wavePath.length + " chars")
            console.log("=== WAVETRACK TEST ===")
            for (const line of root.log) console.log(line)
            const failed = root.log.filter(l => l.indexOf("FAIL") === 0).length
            console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
            Qt.exit(failed === 0 ? 0 : 1)
        } }
    }
}
