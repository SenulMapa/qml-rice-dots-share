pragma Singleton
import QtCore
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * PomodoroService -- wall-clock-based pomodoro timer backing
 * widgets/PomodoroWidget.qml, ported from end4-ii's services/TimerService.qml
 * (pomodoro half only -- the stopwatch tab is skipped, see the port report).
 * Deliberately wall-clock-anchored (phaseStartMs + running), not a plain
 * counting-down integer, so the remaining time stays correct across the
 * shell restarting or the machine sleeping, exactly like ii's
 * getCurrentTimeInSeconds()-anchored version.
 */
QtObject {
    id: root

    readonly property int focusSeconds: 25 * 60
    readonly property int breakSeconds: 5 * 60
    readonly property int longBreakSeconds: 15 * 60
    readonly property int cyclesBeforeLongBreak: 4

    property bool running: false
    property bool onBreak: false
    property int cycle: 0
    property double phaseStartMs: Date.now()
    property bool loaded: false
    // Non-zero while `timer start <minutes>` runs a one-off focus countdown.
    // It is not a pomodoro: it does not advance the cycle, and it stops when
    // it ends instead of starting a break.
    property int customSeconds: 0

    // Emitted once per finished phase. breakOver is false for a focus phase
    // (or a custom countdown) and true when a break ends.
    signal finished(bool breakOver)

    readonly property int phaseDuration: root.customSeconds > 0 ? root.customSeconds
        : root.onBreak
            ? (root.cycle + 1 === root.cyclesBeforeLongBreak ? root.longBreakSeconds : root.breakSeconds)
            : root.focusSeconds

    // Only meaningful while `running` -- ticks every second so the display
    // updates, recomputed from phaseStartMs rather than decremented so it
    // can never drift.
    property double nowMs: Date.now()
    readonly property int elapsedSeconds: Math.max(0, Math.floor((root.nowMs - root.phaseStartMs) / 1000))
    readonly property int secondsLeft: Math.max(0, root.phaseDuration - root.elapsedSeconds)
    // Stopped part-way through a phase. The live pill keeps showing it so the
    // user can resume from there.
    readonly property bool paused: !root.running && root.elapsedSeconds > 0

    property Timer tickTimer: Timer {
        interval: 1000
        repeat: true
        running: root.running
        onTriggered: root.tick()
    }

    function tick(): void {
        root.nowMs = Date.now()
        if (root.elapsedSeconds >= root.phaseDuration)
            root.finishPhase()
    }

    function finishPhase(): void {
        if (root.customSeconds > 0) {
            root.customSeconds = 0
            root.running = false
            root.phaseStartMs = Date.now()
            root.nowMs = root.phaseStartMs
            root.save()
            root.finished(false)
            return
        }
        const wasBreak = root.onBreak
        root.advancePhase()
        root.finished(wasBreak)
    }

    function advancePhase(): void {
        if (!root.onBreak)
            root.cycle = (root.cycle + 1) % root.cyclesBeforeLongBreak
        root.onBreak = !root.onBreak
        root.phaseStartMs = Date.now()
        root.nowMs = root.phaseStartMs
        root.save()
    }

    // `timer start <minutes>`: a one-off focus countdown from now. It replaces
    // whatever pomodoro phase was running.
    function start(minutes: real): void {
        const seconds = Math.round(minutes * 60)
        if (!(seconds > 0))
            return
        root.customSeconds = seconds
        root.onBreak = false
        root.running = true
        root.phaseStartMs = Date.now()
        root.nowMs = root.phaseStartMs
        root.save()
    }

    // `timer pause`: a no-op unless running, so a repeated pause is harmless.
    function pause(): void {
        if (root.running)
            root.toggle()
    }

    // mm:ss for a whole number of seconds. Minutes are not capped at 59, so a
    // long custom countdown still reads correctly.
    function formatClock(totalSeconds: real): string {
        const s = Math.max(0, Math.floor(totalSeconds))
        const m = Math.floor(s / 60)
        const r = s % 60
        return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r
    }

    function toggle(): void {
        if (!root.running) {
            // Resume mid-phase rather than restarting it.
            root.phaseStartMs = Date.now() - root.elapsedSeconds * 1000
        }
        root.running = !root.running
        root.save()
    }

    function reset(): void {
        root.running = false
        root.onBreak = false
        root.cycle = 0
        root.customSeconds = 0
        root.phaseStartMs = Date.now()
        root.nowMs = root.phaseStartMs
        root.save()
    }

    function resolveStateRoot(): string {
        const explicit = Quickshell.env("XDG_STATE_HOME") || ""
        if (explicit.length > 0)
            return explicit
        return (Quickshell.env("HOME") || "") + "/.local/state"
    }

    // Test seam: test-timer-live.qml points this at a scratch file so a test
    // never writes the owner's real pomodoro state. Empty in the shell.
    property string statePathOverride: ""
    readonly property string statePath: statePathOverride.length > 0 ? statePathOverride
        : resolveStateRoot() + "/qml-rice/pomodoro.json"

    function save(): void {
        if (!root.loaded)
            return
        pomodoroFile.setText(JSON.stringify({
            version: 1, running: root.running, onBreak: root.onBreak,
            cycle: root.cycle, phaseStartMs: root.phaseStartMs,
            customSeconds: root.customSeconds, elapsedSeconds: root.elapsedSeconds
        }, null, 2))
    }

    property FileView pomodoroFile: FileView {
        path: root.statePath
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            let pausedElapsed = -1
            try {
                const parsed = JSON.parse(text())
                root.running = !!parsed.running
                root.onBreak = !!parsed.onBreak
                root.cycle = Number.isInteger(parsed.cycle) ? parsed.cycle : 0
                root.phaseStartMs = typeof parsed.phaseStartMs === "number"
                    ? parsed.phaseStartMs : Date.now()
                root.customSeconds = Number.isInteger(parsed.customSeconds) && parsed.customSeconds > 0
                    ? parsed.customSeconds : 0
                // A paused phase must keep the elapsed time it was paused at,
                // not the wall-clock time since phaseStartMs.
                pausedElapsed = Number.isInteger(parsed.elapsedSeconds) ? parsed.elapsedSeconds : -1
            } catch (error) {
                // Fall through with the fresh-start defaults.
            }
            root.nowMs = !root.running && pausedElapsed >= 0
                ? root.phaseStartMs + pausedElapsed * 1000 : Date.now()
            root.loaded = true
        }
        onLoadFailed: error => {
            root.loaded = true
            if (error !== FileViewError.FileNotFound)
                console.warn("qml-rice PomodoroService:", FileViewError.toString(error))
        }
        onSaveFailed: error => console.warn("qml-rice PomodoroService:",
            FileViewError.toString(error))
    }
}
