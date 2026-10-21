// Live activity for the pomodoro / `timer start` countdown: the mm:ss
// formatting, the custom countdown lifecycle (start, pause, resume, finish),
// the width the resting pill reserves for it, and the priority decisions for
// the "Focus done" toast and the battery OSD. Drives a real IslandController
// (a plain QtObject, no window) and the real PomodoroService singleton, with
// its state file redirected to a scratch path so the owner's real
// pomodoro.json is never written.
import QtQuick
import Quickshell
import "core"
import "island"
import "services"

ShellRoot {
    id: root
    property var log: []
    property var finishes: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    IslandController { id: ctrl }

    Connections {
        target: PomodoroService
        function onFinished(breakOver: bool): void { root.finishes.push(breakOver) }
    }

    Component.onCompleted: {
        PomodoroService.statePathOverride = "/tmp/qml-rice-test-timer/pomodoro.json"
        PomodoroService.reset()

        // --- formatting ---------------------------------------------------
        ok("format_zero", PomodoroService.formatClock(0) === "00:00")
        ok("format_pads_seconds", PomodoroService.formatClock(65) === "01:05")
        ok("format_pomodoro_focus", PomodoroService.formatClock(PomodoroService.focusSeconds) === "25:00")
        ok("format_floors_fraction", PomodoroService.formatClock(59.9) === "00:59")
        ok("format_clamps_negative", PomodoroService.formatClock(-4) === "00:00")
        ok("format_keeps_minutes_past_hour", PomodoroService.formatClock(3725) === "62:05")

        // --- custom countdown lifecycle -------------------------------------
        PomodoroService.start(2)
        ok("start_runs_custom_focus", PomodoroService.running && PomodoroService.customSeconds === 120
            && !PomodoroService.onBreak && PomodoroService.phaseDuration === 120)
        ok("start_full_countdown", PomodoroService.secondsLeft === 120, "" + PomodoroService.secondsLeft)
        PomodoroService.start(0)
        ok("start_zero_ignored", PomodoroService.customSeconds === 120 && PomodoroService.running)

        PomodoroService.phaseStartMs = Date.now() - 30000
        PomodoroService.tick()
        ok("tick_counts_down", PomodoroService.running && PomodoroService.secondsLeft === 90,
            "" + PomodoroService.secondsLeft)

        PomodoroService.pause()
        ok("pause_freezes", !PomodoroService.running && PomodoroService.paused
            && PomodoroService.secondsLeft === 90, "" + PomodoroService.secondsLeft)
        PomodoroService.pause()
        ok("pause_idempotent", !PomodoroService.running && PomodoroService.secondsLeft === 90)
        PomodoroService.toggle()
        ok("resume_keeps_remaining", PomodoroService.running && !PomodoroService.paused
            && PomodoroService.secondsLeft === 90)

        PomodoroService.phaseStartMs = Date.now() - 121000
        PomodoroService.tick()
        ok("custom_finish_is_focus_done", root.finishes.length === 1 && root.finishes[0] === false,
            JSON.stringify(root.finishes))
        ok("custom_finish_stops_and_clears", !PomodoroService.running && PomodoroService.customSeconds === 0
            && PomodoroService.cycle === 0 && !PomodoroService.onBreak && !PomodoroService.paused)

        // A pomodoro focus phase that ends starts a break, and says so.
        PomodoroService.reset()
        PomodoroService.toggle()
        PomodoroService.phaseStartMs = Date.now() - (PomodoroService.focusSeconds + 1) * 1000
        PomodoroService.tick()
        ok("focus_end_starts_break", PomodoroService.onBreak && PomodoroService.running
            && root.finishes.length === 2 && root.finishes[1] === false)
        PomodoroService.phaseStartMs = Date.now() - (PomodoroService.breakSeconds + 1) * 1000
        PomodoroService.tick()
        ok("break_end_is_break_over", !PomodoroService.onBreak && root.finishes.length === 3
            && root.finishes[2] === true)
        PomodoroService.reset()
        ok("reset_clears_custom", PomodoroService.customSeconds === 0 && !PomodoroService.running)

        // --- controller priorities ------------------------------------------
        ok("priority_battery_is_osd_40", ctrl.statePriority(ctrl.battery) === 40)
        ok("priority_timer_done_45", ctrl.statePriority(ctrl.timerDone) === 45)

        ctrl.requestTransient(ctrl.call, 0, false, "", 48, 0, false)
        ctrl.showBattery(0.15)
        ok("battery_cannot_cover_call", ctrl.visualState === ctrl.call, ctrl.visualState)
        ctrl.showTimerDone(false)
        ok("timer_done_cannot_cover_call", ctrl.visualState === ctrl.call, ctrl.visualState)
        ctrl.clearTransient()

        ctrl.showBattery(0.15)
        ok("battery_shows_when_idle", ctrl.visualState === ctrl.battery && ctrl.transientPriority === 40
            && ctrl.transientLevel === 0.15, ctrl.visualState)
        ctrl.showVolume(0.5, false, "x")
        ok("osd_replaces_battery_same_priority", ctrl.visualState === ctrl.volume)
        // Equal priority replaces, as OSDs already do among themselves.
        ctrl.showBattery(0.1)
        ok("battery_replaces_equal_priority_osd", ctrl.visualState === ctrl.battery)
        ctrl.clearTransient()

        ctrl.showTimerDone(true)
        ok("timer_done_shows_break_over", ctrl.visualState === ctrl.timerDone
            && ctrl.timerDoneLabel === "Break over" && ctrl.timerDoneBreakOver === true, ctrl.visualState)
        ctrl.showVolume(0.5, false, "x")
        ok("osd_cannot_cover_timer_done", ctrl.visualState === ctrl.timerDone)
        ctrl.showBattery(0.1)
        ok("battery_cannot_cover_timer_done", ctrl.visualState === ctrl.timerDone)
        ctrl.clearTransient()

        ctrl.showBattery(0.5)
        ctrl.showTimerDone(false)
        ok("timer_done_replaces_battery", ctrl.visualState === ctrl.timerDone
            && ctrl.timerDoneLabel === "Focus done" && ctrl.timerDoneBreakOver === false, ctrl.visualState)
        ctrl.clearTransient()
        ok("timer_done_clears", ctrl.visualState === ctrl.dormant && ctrl.transientState === "")

        // --- resting pill width contract -------------------------------------
        const idleWidth = ctrl.targetWidth
        PomodoroService.start(25)
        PomodoroService.phaseStartMs = Date.now() - 5000
        PomodoroService.tick()
        const runningWidth = ctrl.targetWidth
        const reserved = Config.island.restItemSpacing
            + (Config.appearance.ink ? 12 + 8 + 46 : Theme.u(0.2) + Theme.u(0.1) + Theme.u(0.72))
        ok("dormant_width_reserves_timer", Math.abs((runningWidth - idleWidth) - reserved) < 0.01,
            (runningWidth - idleWidth) + " vs " + reserved)
        PomodoroService.pause()
        ok("paused_keeps_width", ctrl.targetWidth === runningWidth)
        PomodoroService.reset()
        ok("reset_releases_width", ctrl.targetWidth === idleWidth)

        console.log("=== TIMER LIVE TEST ===")
        for (const line of log) console.log(line)
        const failed = log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (log.length - failed) + "/" + log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
