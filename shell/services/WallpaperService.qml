pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "../core"

// Sole owner of the serialized awww lifecycle and wallpaper/palette transaction.
QtObject {
    id: root

    property var wallpapers: []
    property string currentWallpaper: ""
    // The still frame to actually bind into an Image/MultiEffect source: the
    // extracted frame when currentWallpaper is a video, otherwise the same
    // path. Nothing that renders a QML Image should ever bind directly to
    // currentWallpaper -- an mp4 there is an "Unsupported image format"
    // decode error, not a picture.
    property string currentStillPath: ""
    readonly property string currentStill: currentStillPath || currentWallpaper
    property bool videoTranscoding: false
    // Same extension test the discovery process already applies per-item
    // (see discoveryProcess below) -- kept in sync manually since this is a
    // single string, not a list entry.
    function isAnimatedPath(path: string): bool {
        return !!(path && path.match(/\.(mp4|webm|mkv|mov|gif)$/i))
    }

    readonly property bool currentWallpaperIsVideo:
        !!(currentWallpaper && currentWallpaper.match(/\.(mp4|webm|mkv|mov)$/i))

    readonly property bool currentIsAnimated:
        isAnimatedPath(currentWallpaper)
    // True once wallpaperctl.sh has confirmed the video backend (gslapper, or
    // mpvpaper as fallback) is actually running for the current wallpaper
    // (the MPVPAPER=started token, kept for either backend), false once it's stopped
    // or the wallpaper switches to a still/GIF. Distinct from
    // currentWallpaperIsVideo because a video wallpaper can be mid-transcode
    // (still frame showing) with nothing playing yet.
    property bool videoPlaying: false

    // ---- Video pause policy -----------------------------------------------
    // Pause video playback per-screen whenever nothing would be gained from
    // decode. With gslapper this is an IPC pause/resume of the resident process
    // (one shared pipeline: it pauses once EVERY output is paused, and keeps
    // its RAM/VRAM); with the mpvpaper fallback the process is terminated
    // (freeing ~250 MB RAM and ~140 MB VRAM) and restarts from the start on
    // return. The awww still frame shows underneath either way. Triggers when that output's active workspace
    // is covered by a fullscreen client, the screen is locked, or we're on battery
    // and the owner hasn't opted into burning battery on ambient video
    // (wallpaper.videoOnBattery).

    property var videoPausedOutputs: ({})
    property var videoPauseRequested: ({})

    readonly property bool lockActive:
        !!(LockService.lockScreen && LockService.lockScreen.locked)

    readonly property string videoPauseSignature: {
        if (!currentWallpaperIsVideo || !videoPlaying)
            return ""
        const monitors = HyprlandService.connectedMonitors
        if (!monitors || monitors.length === 0)
            return ""
        const desired = {}
        for (const monitor of monitors) {
            const monitorName = monitor?.name
            if (!monitorName) continue
            const shouldPause = lockActive
                || !!(monitor?.activeWorkspace?.hasFullscreen)
                || (BatteryService.onBattery && !Config.wallpaper.videoOnBattery)
            desired[monitorName] = shouldPause
        }
        return Object.entries(desired)
            .sort((a, b) => a[0].localeCompare(b[0]))
            .map(([name, paused]) => name + "=" + (paused ? "1" : "0"))
            .join(",")
    }

    onVideoPauseSignatureChanged: videoPauseDebounce.restart()

    // Debounced: fullscreen/lock/battery state can flap several times in a
    // row (e.g. a window briefly passing through a fullscreen transition),
    // and each pause/resume round-trip is a helper-script spawn plus an IPC
    // socket write (or a process respawn on mpvpaper) -- not worth doing on
    // every intermediate signal.
    property Timer videoPauseDebounce: Timer {
        interval: 400
        onTriggered: root.applyVideoPauseState()
    }

    function applyVideoPauseState(): void {
        if (!currentWallpaperIsVideo || !videoPlaying || busy)
            return

        // Compute desired pause state per monitor
        const monitors = HyprlandService.connectedMonitors
        if (!monitors || monitors.length === 0)
            return

        const desired = {}
        for (const monitor of monitors) {
            const monitorName = monitor?.name
            if (!monitorName) continue
            const shouldPause = lockActive
                || !!(monitor?.activeWorkspace?.hasFullscreen)
                || (BatteryService.onBattery && !Config.wallpaper.videoOnBattery)
            desired[monitorName] = shouldPause
        }

        // Find outputs that need state changes
        const changes = []
        const requested = {}
        for (const [name, desiredState] of Object.entries(desired)) {
            const currentState = videoPausedOutputs[name]
            if (currentState !== desiredState) {
                changes.push(name + "=" + (desiredState ? "1" : "0"))
                requested[name] = desiredState
            }
        }

        if (changes.length === 0)
            return

        // Remembered so finishOperation() records the state we ASKED for --
        // recording anything else makes the next tick resend the same stop forever.
        videoPauseRequested = requested

        // Issue single command with all changes
        const cmd = [helperPath, "set-video-pause"].concat(changes)
        beginOperation("pausevideo", cmd)
    }
    property string pendingWallpaper: ""
    property string pendingScheme: ""
    property string candidateWallpaper: ""
    property string candidateToken: ""
    property string candidateStatus: ""
    property bool candidateReady: false
    property string pendingMonitorName: ""
    property bool directApplyPending: false
    property bool loading: false
    property bool applying: false
    property bool backendAvailable: false
    property string backendKind: "awww"
    property string backendState: "starting"
    property string backendDetail: "Checking awww…"
    property string operationState: "idle"
    property string operationKind: ""
    property string operationOutput: ""
    property string operationError: ""
    property string errorMessage: ""
    property bool cancelAfterExit: false
    property bool paletteAvailable: Theme.generatedAvailable
    property bool videoBackendAvailable: true  // gslapper/mpvpaper availability

    readonly property string helperPath:
        Quickshell.shellDir + "/scripts/wallpaperctl.sh"
    readonly property string homeDirectory: Quickshell.env("HOME")
    readonly property var searchPaths: Config.wallpaper.directories.map(path =>
        path.startsWith("/") ? path : homeDirectory + "/" + path)
    readonly property string currentName: displayName(currentWallpaper)
    readonly property bool busy: operationProcess.running
    readonly property string statusLabel: errorMessage
        || (backendState !== "ready" ? backendDetail
        : videoTranscoding ? "Optimising video…"
        : candidateReady ? "Candidate palette prepared — Apply to update the shell"
        : currentWallpaper ? currentName : "No wallpaper selected")

    signal wallpaperApplied(string path, bool paletteUpdated)

    function displayName(path: string): string {
        const name = path.substring(path.lastIndexOf("/") + 1)
            .replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ")
        return name.replace(/\b\w/g, character => character.toUpperCase())
    }

    function imageSource(path: string): string {
        return path ? "file://" + path.split("/").map(encodeURIComponent)
            .join("/") : ""
    }

    function filterWallpapers(query: string): var {
        const normalized = query.trim().toLowerCase()
        return !normalized ? wallpapers : wallpapers.filter(item =>
            item.name.toLowerCase().includes(normalized)
                || item.path.toLowerCase().includes(normalized))
    }

    function setTarget(target: string): bool {
        return SettingsStore.setWallpaperTarget(target)
    }

    function setGalleryColumns(columns: int): bool {
        return SettingsStore.setWallpaperGalleryColumns(columns)
    }

    function setRefreshOnOpen(enabled: bool): void {
        SettingsStore.setWallpaperRefreshOnOpen(enabled)
    }

    function setTransition(transition: string): bool {
        return SettingsStore.setWallpaperTransition(transition)
    }

    function setTransitionDuration(duration: real): bool {
        return SettingsStore.setWallpaperTransitionDuration(duration)
    }

    function resetPreferences(): void {
        SettingsStore.resetWallpaper()
    }

    function beginOperation(kind: string, command: var): bool {
        if (operationProcess.running)
            return false
        operationKind = kind
        operationOutput = ""
        operationError = ""
        operationProcess.command = command
        operationProcess.running = true
        return true
    }

    function refresh(): void {
        if (discoveryProcess.running)
            return
        loading = true
        discoveryProcess.command = [helperPath, "list"].concat(searchPaths)
        discoveryProcess.running = true
    }

    function bootstrap(manual: bool): void {
        if (busy || applying)
            return
        backendState = manual ? "recovering" : "starting"
        backendAvailable = false
        backendDetail = manual ? "Retrying the shell's awww renderer…"
            : "Starting the shell's awww renderer…"
        errorMessage = ""
        beginOperation("bootstrap", [helperPath, "bootstrap",
            manual ? "manual" : "auto"])
    }

    function retry(): void {
        bootstrap(true)
    }

    function selectCandidate(path: string): bool {
        if (busy || applying || !wallpapers.some(item => item.path === path))
            return false
        candidateReady = false
        candidateWallpaper = path
        candidateToken = String(Date.now()) + "-" + Math.random()
        candidateStatus = "Generating local palette…"
        errorMessage = ""
        operationState = "previewing"
        return beginOperation("candidate", [helperPath, "candidate", path,
            Config.wallpaper.scheme, candidateToken])
    }

    // A gallery choice is a commit request, not a UI preview. The helper still
    // prepares an isolated candidate first, so palette validation and the
    // atomic renderer/palette transaction retain their rollback boundary.
    function applyWallpaper(path: string, monitorName: string): bool {
        if (busy || applying || !wallpapers.some(item => item.path === path))
            return false
        const names = outputNames(monitorName)
        if (!names) {
            errorMessage = "No live display available"
            return false
        }
        candidateReady = false
        candidateWallpaper = path
        candidateToken = String(Date.now()) + "-apply-" + Math.random()
        candidateStatus = "Preparing wallpaper transaction…"
        pendingWallpaper = path
        pendingMonitorName = monitorName
        directApplyPending = true
        errorMessage = ""
        operationState = "preparing"
        return beginOperation("directCandidate", [helperPath, "candidate", path,
            Config.wallpaper.scheme, candidateToken])
    }

    function clearCandidateState(): void {
        candidateWallpaper = ""
        candidateToken = ""
        candidateReady = false
        candidateStatus = ""
    }

    function cancelCandidate(): void {
        if (applying)
            return
        clearCandidateState()
        operationState = "idle"
        if (busy) {
            cancelAfterExit = true
            operationProcess.running = false
            return
        }
        beginOperation("cancel", [helperPath, "cancel-candidate"])
    }

    function outputNames(monitorName: string): string {
        return Config.wallpaper.target === "all"
            ? HyprlandService.connectedMonitors.map(monitor => monitor.name)
                .filter(Boolean).join(",") : monitorName
    }

    function applyCandidate(monitorName: string): bool {
        if (!candidateReady || !backendAvailable || busy || applying)
            return false
        const names = outputNames(monitorName)
        if (!names) {
            errorMessage = "No live display available"
            return false
        }
        applying = true
        operationState = "applying"
        pendingWallpaper = candidateWallpaper
        errorMessage = ""
        return beginOperation("apply", [helperPath, "apply",
            candidateWallpaper, Config.wallpaper.scheme,
            Config.wallpaper.target, names, Config.wallpaper.transition,
            String(Config.wallpaper.transitionDuration),
            Config.appearance.reducedMotion ? "true" : "false",
            candidateToken])
    }

    function changeScheme(scheme: string): void {
        if (scheme === Config.wallpaper.scheme || busy || applying
                || !currentWallpaper)
            return
        pendingScheme = scheme
        candidateWallpaper = currentWallpaper
        candidateToken = String(Date.now()) + "-scheme"
        candidateReady = false
        candidateStatus = "Generating local palette…"
        errorMessage = ""
        operationState = "changingScheme"
        beginOperation("schemeCandidate", [helperPath, "candidate",
            currentWallpaper, scheme, candidateToken])
    }

    function parseStatus(text: string): void {
        for (const line of text.split("\n")) {
            if (line.startsWith("CURRENT=")) {
                currentWallpaper = line.substring(8)
                if (!currentWallpaperIsVideo) {
                    // Switched to a still/GIF: nothing is decoding anymore,
                    // so any pause/resume policy state is stale.
                    videoPlaying = false
                    videoPausedOutputs = {}
                }
                continue
            }
            if (line.startsWith("STILL=")) {
                const still = line.substring(6)
                if (still)
                    currentStillPath = still
                continue
            }
            if (line.startsWith("MPVPAPER=")) {
                const status = line.substring(9)
                if (status === "unavailable")
                    videoBackendAvailable = false
                else if (status === "started") {
                    videoTranscoding = false
                    transcodeTimer.running = false
                    videoPlaying = true
                    videoPausedOutputs = {}
                    if (backendState === "ready")
                        backendDetail = "awww renderer ready"
                    videoPauseDebounce.restart()
                }
                continue
            }
            if (line.startsWith("TRANSCODE=")) {
                const status = line.substring(10)
                if (status === "started" || status === "running") {
                    videoTranscoding = true
                    if (backendState === "ready")
                        backendDetail = "Optimising video…"
                    transcodeTimer.running = true
                }
                continue
            }
            if (!line.startsWith("STATE="))
                continue
            backendState = line.substring(6)
            backendAvailable = backendState === "ready"
            if (backendState === "ready")
                backendDetail = "awww renderer ready"
            else if (backendState === "recovering")
                backendDetail = "Recovering the shell's awww renderer…"
            else if (backendState === "missing")
                backendDetail = "awww is required for wallpapers (sudo pacman -S awww)"
            else if (backendState === "conflict")
                backendDetail = "Another wallpaper renderer is active; stop or reconfigure it first"
            else if (backendState === "exhausted")
                backendDetail = "Automatic awww recovery paused after three attempts — Retry manually"
            else
                backendDetail = "awww is unavailable; Retry to check again"
        }
    }

    function stopVideo(): void {
        if (!busy && !applying)
            beginOperation("stopvideo", [helperPath, "stop-video"])
    }

    function requestHealthProbe(): void {
        if (!busy && !applying)
            beginOperation("probe", [helperPath, "probe"])
    }

    function finishOperation(exitCode: int): void {
        const kind = operationKind
        const output = operationOutput
        const detail = operationError.trim()
        parseStatus(output)
        operationKind = ""

        if (cancelAfterExit) {
            cancelAfterExit = false
            pendingScheme = ""
            errorMessage = ""
            Qt.callLater(() => beginOperation("cancel",
                [helperPath, "cancel-candidate"]))
            return
        }

        if (kind === "bootstrap") {
            if (exitCode !== 0) {
                backendAvailable = false
                if (backendState === "starting" || backendState === "recovering")
                    backendState = "unavailable"
                errorMessage = detail || backendDetail
            } else {
                backendState = "ready"
                backendAvailable = true
                backendDetail = "awww renderer ready"
                errorMessage = ""
            }
            operationState = "idle"
            return
        }

        if (kind === "probe") {
            if (backendState === "ready") {
                backendAvailable = true
                return
            }
            backendAvailable = false
            // Honour manageOnStartup here too. Gating only the call in
            // shell.qml was not enough: this retry path re-entered bootstrap
            // on its own and started awww anyway, which is how a daemon ended
            // up owning the desktop background after the gate was added.
            // A flag that one code path can route around is not a gate.
            if (Config.wallpaper.manageOnStartup
                    && backendState !== "missing" && backendState !== "conflict"
                    && backendState !== "exhausted")
                Qt.callLater(() => bootstrap(false))
            return
        }

        if (kind === "candidate" || kind === "directCandidate"
                || kind === "schemeCandidate") {
            if (exitCode !== 0) {
                candidateReady = false
                candidateStatus = "Palette preparation failed"
                errorMessage = detail || "Palette generation failed"
                pendingScheme = ""
                pendingWallpaper = ""
                pendingMonitorName = ""
                directApplyPending = false
                clearCandidateState()
                operationState = "idle"
                return
            }
            candidateReady = true
            candidateStatus = "Palette prepared locally"
            if (kind === "schemeCandidate") {
                candidateStatus = "Verifying renderer before palette publication…"
                Qt.callLater(() => beginOperation("scheme", [helperPath,
                    "scheme", candidateWallpaper, pendingScheme,
                    candidateToken]))
            } else if (kind === "directCandidate") {
                candidateStatus = "Applying wallpaper…"
                Qt.callLater(() => root.applyCandidate(root.pendingMonitorName))
            } else {
                operationState = "ready"
            }
            return
        }

        if (kind === "apply" || kind === "scheme") {
            const committed = exitCode === 0 && output.includes("COMMITTED=true")
            applying = false
            pendingWallpaper = ""
            pendingMonitorName = ""
            if (committed) {
                const appliedPath = currentWallpaper
                paletteAvailable = true
                if (kind === "scheme")
                    SettingsStore.setScheme(pendingScheme)
                clearCandidateState()
                pendingScheme = ""
                directApplyPending = false
                errorMessage = ""
                operationState = "idle"
                wallpaperApplied(appliedPath, true)
            } else {
                errorMessage = detail || "Wallpaper transaction failed; previous state was restored"
                if (kind === "scheme" || directApplyPending) {
                    pendingScheme = ""
                    clearCandidateState()
                    Qt.callLater(() => beginOperation("cancel",
                        [helperPath, "cancel-candidate"]))
                }
                directApplyPending = false
                operationState = "idle"
                recoveryTimer.restart()
            }
            return
        }

        if (kind === "cancel") {
            operationState = "idle"
            if (exitCode !== 0)
                errorMessage = detail || "Candidate cleanup failed"
        }

        if (kind === "stopvideo") {
            operationState = "idle"
            videoTranscoding = false
            transcodeTimer.running = false
            videoPlaying = false
            videoPausedOutputs = {}
            if (exitCode !== 0)
                errorMessage = detail || "Video player stop failed"
        }

        if (kind === "startvideo" || kind === "pausevideo" || kind === "resumevideo") {
            operationState = "idle"
            if (exitCode !== 0 && kind === "startvideo")
                errorMessage = detail || "Video playback failed"
            // For per-monitor pause state: parse output lines and update map.
            // On failure, revert pending changes so next debounce tick retries.
            if (kind === "pausevideo") {
                if (exitCode === 0) {
                    // Parse PAUSE_OK/PAUSE_FAIL lines and update map
                    const updates = {}
                    for (const line of output.split("\n")) {
                        if (line.startsWith("PAUSE_OK=")) {
                            const out = line.substring(9)
                            if (out in videoPauseRequested)
                                updates[out] = videoPauseRequested[out]
                        } else if (line.startsWith("PAUSE_FAIL=")) {
                            // Leave map entry unchanged; retry on next tick
                            delete updates[line.substring(11)]
                        }
                    }
                    // Commit successful updates by creating a new object
                    const newMap = Object.assign({}, videoPausedOutputs, updates)
                    videoPausedOutputs = newMap
                } else {
                    // On failure, clear pending map entries so next tick retries
                    videoPausedOutputs = {}
                }
            }
        }
        // Some other operation may have been holding operationProcess busy
        // while the pause/resume policy changed underneath it; reconcile now
        // that it's free again.
        videoPauseDebounce.restart()
    }

    // ---- Background transcode polling ------------------------------------
    // The proxy build runs detached in wallpaperctl.sh; this timer polls its
    // status file rather than blocking apply/bootstrap on it, so the still
    // frame stays on screen (via currentStill) the whole time it runs.

    property Timer transcodeTimer: Timer {
        interval: 700
        repeat: true
        running: false
        onTriggered: {
            if (!root.transcodeStatusProcess.running)
                root.transcodeStatusProcess.running = true
        }
    }

    property Process transcodeStatusProcess: Process {
        command: [root.helperPath, "transcode-status"]
        stdout: StdioCollector {
            onStreamFinished: root.handleTranscodeStatus(text)
        }
    }

    function handleTranscodeStatus(text: string): void {
        let stage = "idle", proxy = ""
        for (const line of text.split("\n")) {
            if (line.startsWith("STAGE="))
                stage = line.substring(6)
            else if (line.startsWith("PROXY="))
                proxy = line.substring(6)
        }
        if (stage === "probing" || stage === "encoding") {
            videoTranscoding = true
            if (backendState === "ready")
                backendDetail = "Optimising video…"
            return
        }
        videoTranscoding = false
        transcodeTimer.running = false
        if (backendState === "ready")
            backendDetail = "awww renderer ready"
        if (stage === "done" && proxy && !busy)
            beginOperation("startvideo", [helperPath, "start-video", proxy])
        else if (stage === "failed" && currentWallpaper && !busy)
            // Fall back to the raw source rather than a permanently frozen
            // still -- an un-optimised video beats a stuck wallpaper.
            beginOperation("startvideo", [helperPath, "start-video", currentWallpaper])
    }

    property var videoPaths: []  // Collected during discovery for frame extraction
    property int frameGeneration: 0  // Incremented on discovery; chains bail if stale

    property Process discoveryProcess: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = []
                const seen = new Set()
                root.videoPaths = []
                for (const line of text.split("\n")) {
                    const path = line.trim()
                    if (path && !seen.has(path)) {
                        seen.add(path)
                        const isVideo = path.match(/\.(mp4|webm|mkv|mov)$/i)
                        const isGif = path.match(/\.gif$/i)
                        const item = {
                            path: path,
                            name: root.displayName(path),
                            source: root.imageSource(path),
                            isVideo: !!isVideo,
                            isAnimated: !!isVideo || !!isGif,
                            thumbnailSource: isVideo ? "" : root.imageSource(path)
                        }
                        rows.push(item)
                        if (isVideo)
                            root.videoPaths.push(path)
                    }
                }
                root.wallpapers = rows
                // Start sequential frame extraction for videos
                if (root.videoPaths.length > 0) {
                    root.frameGeneration += 1
                    root.frameIndex = 0
                    root.extractNextFrame(root.frameGeneration)
                }
            }
        }
        onExited: exitCode => {
            root.loading = false
            if (exitCode !== 0)
                root.errorMessage = "Wallpaper scan failed"
        }
    }

    property int frameIndex: 0

    function extractNextFrame(gen: int): void {
        if (gen !== frameGeneration || frameIndex >= videoPaths.length)
            return
        const videoPath = videoPaths[frameIndex]
        const frameProc = Qt.createQmlObject(
            'import Quickshell.Io; Process { stdout: StdioCollector {} }',
            root
        )
        frameProc.command = [helperPath, "frame", videoPath]
        frameProc.stdout.onStreamFinished.connect(() => {
            const framePath = frameProc.stdout.text.trim()
            if (framePath) {
                // Immutable update: map over wallpapers, replace matching path
                root.wallpapers = root.wallpapers.map(w =>
                    w.path === videoPath
                        ? Object.assign({}, w, {thumbnailSource: root.imageSource(framePath)})
                        : w
                )
            }
            frameProc.destroy()
            frameIndex += 1
            if (frameIndex < videoPaths.length)
                Qt.callLater(() => root.extractNextFrame(gen))
        })
        frameProc.running = true
    }

    property Process operationProcess: Process {
        // Threads the videoMaxFps setting (core/Config.qml) into every
        // wallpaperctl.sh invocation this process makes (apply, bootstrap,
        // scheme, candidate...) without having to add it as a positional arg
        // to each one -- the script already reads this var with its own
        // default of 30 for paths (like the standalone `reconcile`
        // subcommand) that never go through this Process at all.
        environment: ({
            "ODYSSEY_WALLPAPER_MAX_FPS": String(Config.wallpaper.videoMaxFps)
        })
        stdout: StdioCollector {
            onStreamFinished: root.operationOutput = text
        }
        stderr: StdioCollector {
            onStreamFinished: root.operationError = text
        }
        onExited: exitCode => root.finishOperation(exitCode)
    }

    property Timer healthTimer: Timer {
        interval: 15000
        repeat: true
        running: true
        onTriggered: root.requestHealthProbe()
    }

    // Day/night video variants (wallpaperctl.sh `tick`). A minute is plenty
    // for a dusk boundary, and the tick is a no-op until the variant flips.
    // Same env as operationProcess so the proxy cache key matches.
    property Process variantTickProcess: Process {
        command: [root.helperPath, "tick"]
        environment: ({
            "ODYSSEY_WALLPAPER_MAX_FPS": String(Config.wallpaper.videoMaxFps)
        })
    }

    // Held while the battery policy keeps the video paused anyway: a tick
    // there can only spawn the helper (and, for a variant without a proxy,
    // start an ffmpeg transcode) for a wallpaper nobody is watching. One
    // catch-up tick runs when the hold lifts.
    readonly property bool variantTickHeld:
        BatteryService.onBattery && !Config.wallpaper.videoOnBattery
    onVariantTickHeldChanged: if (!variantTickHeld && currentIsAnimated) runVariantTick()
    function runVariantTick(): void {
        if (!root.busy && !root.variantTickProcess.running)
            root.variantTickProcess.running = true
    }
    property Timer variantTimer: Timer {
        interval: 60000
        repeat: true
        running: root.currentIsAnimated && !root.variantTickHeld
        onTriggered: root.runVariantTick()
    }

    property Timer recoveryTimer: Timer {
        interval: 300
        onTriggered: root.requestHealthProbe()
    }
}
