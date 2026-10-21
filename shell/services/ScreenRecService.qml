pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core"

/**
 * ScreenRecService -- gpu-screen-recorder front end. Monitor mode records
 * the focused output (resolved via `hyprctl monitors -j`, not gpu-screen-
 * recorder's own `-w focused`, which is X11-only per its man page); region
 * mode records an explicit "WxHxX+Y"-shaped `-region` string, normally
 * produced by slurp but ALSO accepted directly from a caller (island/
 * RecordingIndicator.qml's test harness and test-recorder.qml drive this
 * path so nothing here ever has to launch slurp itself, or the real
 * compositor, to be testable).
 *
 * Stop is SIGINT (gpu-screen-recorder's own documented "stop and save"
 * signal -- see `man gpu-screen-recorder.1`'s SIGNALS section), sent
 * directly to the recorder's own pid via Process.signal(), never a shell
 * wrapper -- the recorder is always the direct child so its pid is exactly
 * what Process.processId reports.
 *
 * A pidfile in $XDG_RUNTIME_DIR survives a shell restart: Component.
 * onCompleted checks for one and, if the pid it names is still alive,
 * adopts it as an in-progress recording (best-effort -- elapsed time since
 * a restart can't be recovered, only the fact that IT'S STILL RECORDING
 * can) instead of leaving an orphaned gpu-screen-recorder process forever
 * un-stoppable from the UI.
 */
QtObject {
    id: root

    property bool recording: false
    property real elapsed: 0
    property string outputPath: ""
    property string lastError: ""
    property bool starting: false

    readonly property string recordingsDir: Quickshell.env("HOME") + "/Videos/Recordings"
    readonly property string pidFilePath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qml-rice-screenrec.pid"

    function pad2(n: int): string { return n < 10 ? "0" + n : String(n) }

    function timestampName(): string {
        const d = new Date()
        return "" + d.getFullYear() + pad2(d.getMonth() + 1) + pad2(d.getDate())
            + "-" + pad2(d.getHours()) + pad2(d.getMinutes()) + pad2(d.getSeconds())
    }

    // ---- public entry points ---------------------------------------------

    function toggle(): void {
        if (root.recording || root.starting) root.stop()
        else root.startMonitor()
    }

    function startMonitor(): void {
        if (root.recording || root.starting) return
        root.lastError = ""
        root.starting = true
        monitorQuery.running = true
    }

    // regionArg -- "WxH+X+Y" (gpu-screen-recorder's own -region format).
    // Given: skip slurp entirely, this is the testable/automatable path.
    // Omitted: shell out to slurp interactively (never done by a test).
    function startRegion(regionArg: string): void {
        if (root.recording || root.starting) return
        root.lastError = ""
        root.starting = true
        if (regionArg && regionArg.length > 0) {
            root.beginRecording("region", regionArg)
        } else {
            slurpProcess.running = true
        }
    }

    function stop(): void {
        if (recProcess.running) {
            recProcess.signal(2) // SIGINT -- "stop and save" per gpu-screen-recorder's man page
        } else if (root.recording) {
            // Adopted-orphan case: no live Process object, only the pidfile.
            stopOrphan.running = true
        }
    }

    function status(): string {
        return JSON.stringify({
            recording: root.recording,
            elapsed: Math.floor(root.elapsed),
            outputPath: root.outputPath
        })
    }

    property IpcHandler recorderIpc: IpcHandler {
        target: "recorder"
        function toggle(): void { root.toggle() }
        function start(): void { root.startMonitor() }
        function startRegion(region: string): void { root.startRegion(region) }
        function stop(): void { root.stop() }
        function status(): string { return root.status() }
    }

    // ---- monitor resolution ------------------------------------------

    property Process monitorQuery: Process {
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let name = ""
                try {
                    const monitors = JSON.parse(text)
                    const focused = monitors.find(m => m.focused)
                    name = focused ? focused.name : (monitors[0] ? monitors[0].name : "")
                } catch (e) {
                    name = ""
                }
                if (!name) {
                    root.starting = false
                    root.lastError = "Could not resolve focused monitor"
                    return
                }
                root.beginRecording("monitor", name)
            }
        }
    }

    property Process slurpProcess: Process {
        command: ["slurp"]
        stdout: StdioCollector {
            onStreamFinished: {
                // StdioCollector reports a ZERO-byte stream as null, not
                // "" -- (text || "") guards every one of these reads.
                const region = (text || "").trim()
                if (!region) {
                    root.starting = false
                    return // cancelled (Escape in slurp) -- not an error
                }
                root.beginRecording("region", region)
            }
        }
    }

    // ---- recording lifecycle -------------------------------------------

    function beginRecording(mode: string, target: string): void {
        root.pendingMode = mode
        root.pendingTarget = target
        mkdirProcess.running = true
    }

    property string pendingMode: ""
    property string pendingTarget: ""

    // Testability seam ONLY -- test-recorder.qml sets this to a harmless
    // long-running stand-in (e.g. ["sleep", "100"]) so the state
    // machine/pidfile/SIGINT-stop/orphan-adoption logic below can be
    // exercised for real without ever invoking the actual screen-recorder
    // binary. null (the default) means "build the real gpu-screen-recorder
    // command below" -- inert in the real shell.
    property var commandOverride: null

    property Process mkdirProcess: Process {
        command: ["mkdir", "-p", root.recordingsDir]
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.starting = false
                root.lastError = "Could not create " + root.recordingsDir
                return
            }
            const path = root.recordingsDir + "/" + root.timestampName() + ".mp4"
            root.outputPath = path
            if (root.commandOverride) {
                recProcess.command = root.commandOverride
            } else {
                const args = ["gpu-screen-recorder"]
                if (root.pendingMode === "region") {
                    args.push("-w", "region", "-region", root.pendingTarget)
                } else {
                    args.push("-w", root.pendingTarget)
                }
                args.push("-f", "60", "-c", "mp4", "-o", path)
                recProcess.command = args
            }
            recProcess.running = true
        }
    }

    property Process recProcess: Process {
        stderr: StdioCollector {
            onStreamFinished: {
                const stderrText = (text || "").trim()
                if (stderrText.length > 0)
                    root.lastError = stderrText
            }
        }
        // Sets writePidProcess.command IMPERATIVELY, right here, rather
        // than as a declarative binding on recProcess.processId -- a
        // QVariant read only through string concatenation inside a list
        // property's binding expression does not reliably re-track as a
        // dependency (measured: the bound command kept the "null" it saw
        // at ScreenRecService's own construction, long before any pid
        // existed, and never re-evaluated even after processId changed).
        // A direct imperative read at the moment it's actually needed has
        // no such problem.
        onProcessIdChanged: {
            if (processId) {
                writePidProcess.command = ["sh", "-c",
                    "echo " + processId + " > '" + root.pidFilePath + "'"]
                writePidProcess.running = true
            }
        }
        onRunningChanged: {
            if (running) {
                root.starting = false
                root.recording = true
                root.elapsed = 0
            }
        }
        onExited: exitCode => {
            root.recording = false
            root.starting = false
            const savedPath = root.outputPath
            removePidProcess.running = true
            if (exitCode === 0)
                notifyProcess.command = ["notify-send", "-a", "qml-rice",
                    "Screen recording saved", savedPath]
            else
                notifyProcess.command = ["notify-send", "-a", "qml-rice",
                    "-u", "critical", "Screen recording failed",
                    root.lastError || ("exit code " + exitCode)]
            notifyProcess.running = true
        }
    }

    property Process writePidProcess: Process { }
    property Process removePidProcess: Process {
        command: ["rm", "-f", root.pidFilePath]
    }
    property Process notifyProcess: Process { }

    // ---- elapsed clock: only ticks while actually recording -----------
    property Timer elapsedTimer: Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.elapsed += 1
    }

    // ---- orphan adoption ------------------------------------------------

    property Process orphanCheck: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const pid = (text || "").trim()
                if (!pid) return
                aliveCheck.pidArg = pid
                aliveCheck.running = true
            }
        }
    }
    property Process aliveCheck: Process {
        property string pidArg: ""
        command: pidArg ? ["kill", "-0", pidArg] : ["true"]
        onExited: exitCode => {
            if (exitCode === 0) {
                // Still running -- adopt it: recording is true, but with no
                // outputPath/elapsed history (this shell instance never
                // started it). stop() falls back to the pidfile path since
                // recProcess itself was never populated for this pid.
                root.recording = true
                root.outputPath = "(recording from a previous shell instance)"
            } else {
                removePidProcess.running = true
            }
        }
    }
    property Process stopOrphan: Process {
        command: ["sh", "-c",
            "kill -SIGINT \"$(cat '" + root.pidFilePath + "' 2>/dev/null)\" 2>/dev/null"]
        onExited: {
            root.recording = false
            removePidProcess.running = true
        }
    }

    // Pulled out of Component.onCompleted so test-recorder.qml can re-run
    // it on demand (a pidfile it plants after the singleton already
    // completed once would otherwise never be picked up in the same
    // process -- there's only one shell instance per qs invocation).
    function checkForOrphan(): void {
        orphanCheck.command = ["sh", "-c",
            "cat '" + root.pidFilePath + "' 2>/dev/null"]
        orphanCheck.running = true
    }

    Component.onCompleted: root.checkForOrphan()
}
