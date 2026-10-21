// Component test for services/ScreenRecService.qml's state machine and
// pidfile lifecycle -- NOT actual screen capture. commandOverride swaps
// the real `gpu-screen-recorder` invocation for a harmless `sleep`
// stand-in (see that property's own doc comment), so this exercises the
// real Process/pidfile/SIGINT-stop/orphan-adoption plumbing without ever
// touching the GPU or writing a video file. Real (but read-only/harmless)
// commands DO run here: `hyprctl monitors -j` (query only), `mkdir -p` on
// the real recordings dir, and a real SIGINT to the fake `sleep` process.
//
// sleep does NOT emulate gpu-screen-recorder's graceful "SIGINT -> finalize
// -> exit 0" contract, so this doesn't assert on the post-stop notify
// text -- only on the state transitions and pidfile file-on-disk facts,
// which is the actual scope of this test. The real recorder's SIGINT
// behaviour is proven separately with a real short clip + ffprobe (see the
// verification pass, never run from an automated test file).
import QtQuick
import Quickshell
import Quickshell.Io
import "services"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    function finish() {
        console.log("=== RECORDER TEST ===")
        for (const line of root.log) console.log(line)
        const failed = root.log.filter(l => l.startsWith("FAIL")).length
        console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
        Qt.quit()
    }

    // A file check helper: `test -f <path>` via a throwaway Process,
    // synchronous-ish through a callback since Process itself is async.
    function fileExists(path, cb) {
        const p = Qt.createQmlObject(
            'import Quickshell.Io; Process { command: ["test", "-f", "' + path + '"] }',
            root)
        p.exited.connect((code) => { cb(code === 0); p.destroy() })
        p.running = true
    }
    property var pendingReadCb: null
    function readFile(path, cb) {
        root.pendingReadCb = cb
        pidReader.command = ["sh", "-c", "cat '" + path + "' 2>/dev/null"]
        pidReader.running = true
    }
    Process {
        id: pidReader
        stdout: StdioCollector {
            onStreamFinished: {
                const cb = root.pendingReadCb
                root.pendingReadCb = null
                if (cb) cb((text || "").trim())
            }
        }
    }
    function writeFile(path, contents, cb) {
        const p = Qt.createQmlObject('import Quickshell.Io; Process { }', root)
        p.exited.connect(() => { cb(); p.destroy() })
        p.command = ["sh", "-c", "echo '" + contents + "' > '" + path + "'"]
        p.running = true
    }

    // ---- phase 1: monitor-mode start/stop -------------------------------
    Component.onCompleted: {
        ScreenRecService.commandOverride = ["sleep", "100"]
        root.ok("starts_not_recording", !ScreenRecService.recording, "")
        ScreenRecService.startMonitor()
        root.ok("starting_flag_set", ScreenRecService.starting, "")
        phase1Timer.start()
    }

    Timer {
        id: phase1Timer
        interval: 800 // real hyprctl query + mkdir + process spawn
        running: false; repeat: false
        onTriggered: {
            root.ok("recording_true_after_start", ScreenRecService.recording,
                "" + ScreenRecService.recording)
            root.ok("starting_cleared", !ScreenRecService.starting, "")
            root.ok("output_path_set",
                ScreenRecService.outputPath.startsWith(Quickshell.env("HOME") + "/Videos/Recordings/"),
                ScreenRecService.outputPath)
            root.fileExists(ScreenRecService.pidFilePath, exists => {
                root.ok("pidfile_exists_while_recording", exists, "")
                root.readFile(ScreenRecService.pidFilePath, contents => {
                    root.ok("pidfile_has_a_pid", /^\d+$/.test(contents), "" + contents)
                    elapsedCheck.start()
                })
            })
        }
    }

    Timer {
        id: elapsedCheck
        interval: 1300 // let the 1s elapsed timer tick at least once
        running: false; repeat: false
        onTriggered: {
            root.ok("elapsed_ticks_while_recording", ScreenRecService.elapsed >= 1,
                "" + ScreenRecService.elapsed)
            ScreenRecService.stop()
            stopCheck.start()
        }
    }

    Timer {
        id: stopCheck
        interval: 500
        running: false; repeat: false
        onTriggered: {
            root.ok("recording_false_after_stop", !ScreenRecService.recording, "")
            root.fileExists(ScreenRecService.pidFilePath, exists => {
                root.ok("pidfile_removed_after_stop", !exists, "")
                phase2Region()
            })
        }
    }

    // ---- phase 2: region mode with an explicit region (no slurp) -------
    function phase2Region() {
        ScreenRecService.commandOverride = ["sleep", "100"]
        ScreenRecService.startRegion("100x100+0+0")
        phase2Timer.start()
    }

    Timer {
        id: phase2Timer
        interval: 800
        running: false; repeat: false
        onTriggered: {
            root.ok("region_mode_recording", ScreenRecService.recording, "")
            ScreenRecService.stop()
            phase2StopTimer.start()
        }
    }
    Timer {
        id: phase2StopTimer
        interval: 500
        running: false; repeat: false
        onTriggered: {
            root.ok("region_mode_stopped", !ScreenRecService.recording, "")
            phase3OrphanAlive()
        }
    }

    // ---- phase 3: orphan adoption -- a pidfile pointing at a REAL alive
    // process (a throwaway `sleep`, not gpu-screen-recorder) must be
    // adopted as "recording" when checkForOrphan() re-runs.
    property var orphanProc: null
    function phase3OrphanAlive() {
        const p = Qt.createQmlObject(
            'import Quickshell.Io; Process { command: ["sleep", "100"] }', root)
        root.orphanProc = p
        p.exited.connect(() => {})
        p.running = true
        orphanSpawnTimer.start()
    }
    Timer {
        id: orphanSpawnTimer
        interval: 200
        running: false; repeat: false
        onTriggered: {
            const pid = root.orphanProc.processId
            root.writeFile(ScreenRecService.pidFilePath, "" + pid, () => {
                ScreenRecService.recording = false // simulate a fresh singleton's default
                ScreenRecService.checkForOrphan()
                orphanAliveCheck.start()
            })
        }
    }
    Timer {
        id: orphanAliveCheck
        interval: 500
        running: false; repeat: false
        onTriggered: {
            root.ok("orphan_alive_pid_adopted", ScreenRecService.recording, "")
            root.orphanProc.signal(9) // SIGKILL the throwaway sleep
            root.orphanProc.destroy()
            phase4OrphanDead()
        }
    }

    // ---- phase 4: orphan adoption -- a pidfile pointing at a DEAD pid
    // must be cleaned up (removed), not adopted.
    function phase4OrphanDead() {
        ScreenRecService.recording = false
        // 999999 is not a valid/running pid on any normal system.
        root.writeFile(ScreenRecService.pidFilePath, "999999", () => {
            ScreenRecService.checkForOrphan()
            orphanDeadCheck.start()
        })
    }
    Timer {
        id: orphanDeadCheck
        interval: 500
        running: false; repeat: false
        onTriggered: {
            root.ok("orphan_dead_pid_not_adopted", !ScreenRecService.recording, "")
            root.fileExists(ScreenRecService.pidFilePath, exists => {
                root.ok("orphan_dead_pidfile_cleaned_up", !exists, "")
                root.finish()
            })
        }
    }
}
