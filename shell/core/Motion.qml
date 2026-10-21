pragma Singleton
import QtQuick
import Quickshell.Hyprland
import "."

/**
 * Motion — the shell's single frame clock and spring vocabulary.
 *
 * CLOSED FORM. Each MotionValue solves the damped harmonic oscillator
 * analytically (docs/superpowers/specs/2026-09-23-blob-rebuild-design.md
 * section 2), not by fixed-step Euler integration. Retargeting captures the
 * value AND velocity at the moment of retarget (x0, v0, t0) and evaluates
 * x(t), v(t) from the closed-form solution at whatever t the caller asks
 * for. This is numerically EXACT for any dt (unlike Euler, which only
 * approximates), so "frame-rate independence" stops being an approximation
 * that needs a small fixed step to hold -- it's now algebraically true.
 *
 * WHY NOT Qt's SpringAnimation. Measured (spikes/spring-calibrate.qml) to
 * DIVERGE at the stiffness this design needs: at spring:160 it reports 156%
 * overshoot and a NEGATIVE damping ratio, which is an unstable integrator
 * rather than a spring. Its `damping` also saturates at 1.0, and its omega
 * does not track sqrt(spring), so there is no stable mapping from a
 * designable vocabulary onto its units.
 *
 * CLOCK. A single shared vsync-driven FrameAnimation accumulates elapsed
 * seconds into `now`. Every MotionValue evaluates against that shared `now`,
 * so two windows on two different refresh rates (the 60Hz laptop panel and
 * the 240Hz desktop monitor) agree on where every spring physically is at
 * any instant -- there is one wall of time, not one per window.
 *
 * VOCABULARY. Springs are described either by (omega, zeta) directly -- the
 * legacy vocabulary used throughout the shell (Motion.omegaEnter etc, still
 * supported so every existing call site keeps compiling) -- or by the blob
 * engine's (response, dampingFraction) presets below, converted via
 * omega = 2*pi/response, zeta = dampingFraction.
 *   overshoot = exp(-zeta*pi/sqrt(1-zeta^2))    (zeta < 1)
 *
 * SLEEP. An active list, not a scan. FrameAnimation.running follows
 * activeCount > 0, so a shell at rest costs zero callbacks per frame.
 */
QtObject {
    id: root

    // ---- legacy (omega, zeta) design presets --------------------------
    // Kept verbatim: every existing MotionValue{} literal in the shell
    // references these by name and must keep compiling and feeling the same.
    readonly property real omegaEnter: 22.0
    readonly property real omegaExit: 16.0
    readonly property real zetaEnter: 0.88
    readonly property real zetaExit: 1.0
    readonly property real omegaDefault: 18.0
    readonly property real zetaDefault: 0.92

    // ---- blob-engine (response, dampingFraction) presets --------------
    // response: seconds to (approximately) settle. dampingFraction: zeta.
    // omega = 2*pi/response. Config.appearance.motionSpeedMultiplier
    // (settings-v2's Motion tab, 0.8-1.2) divides response directly, per
    // its own name: 0.8x response is 20% quicker to settle, 1.2x is 20%
    // slower -- every preset call site honours it automatically rather
    // than each one remembering to apply it separately.
    function _response(base) {
        return base / Math.max(0.5, Config.appearance.motionSpeedMultiplier)
    }
    function presetSnappy() { return { omega: 2 * Math.PI / root._response(0.30), zeta: 0.86 } }
    function presetSmooth() { return { omega: 2 * Math.PI / root._response(0.45), zeta: 1.0 } }
    function presetBouncy() { return { omega: 2 * Math.PI / root._response(0.50), zeta: 0.75 } }
    function presetGentle() { return { omega: 2 * Math.PI / root._response(0.60), zeta: 1.0 } }

    readonly property bool reduceMotion: Config.appearance.reducedMotion

    // Retained for compatibility with call sites/tests that still reference
    // a nominal substep size (eg. manual `for (...) mv.step(Motion.h)` loops
    // in test-motion.qml -- step() is now an EXACT closed-form advance by h,
    // not an Euler approximation, so looping it still integrates correctly,
    // just no longer approximately).
    readonly property real h: 1.0 / 240.0

    // ---- shared frame clock --------------------------------------------
    // Elapsed seconds, monotonically increasing while the clock runs. Every
    // MotionValue's t0 is stamped from this on retarget/snap, and evaluate()
    // reads (now - t0) as its solution's t.
    property real now: 0

    property var registry: []          // active MotionValue instances
    readonly property int activeCount: registry.length

    // ROOT CAUSE of "0 animation" opens/closes: activeCount drops to 0
    // between every transition (nothing is springing at rest), so every
    // window's own FrameAnimation stops (running: activeCount > 0) and
    // Motion.tick() goes uncalled for however long the island sits idle --
    // seconds, easily. The MOMENT a transition kicks the first MotionValue
    // back into the registry, that window's FrameAnimation restarts and
    // its very next tick() computes dt against the STALE lastTickMs from
    // before the idle gap, which is >250ms almost every time -- tripping
    // tick()'s own "compositor stopped painting us" snap-everything guard
    // on the FIRST frame of what should have been a fresh 0.45s spring.
    // Every body morph was therefore snapping to target before a single
    // interpolated frame ever rendered; only the separate opacity/Reveal
    // fades (a different, duration-based system) were ever visible.
    //
    // Fix: track whether the clock was idle (activeCount at 0) and, on the
    // 0->active edge, reset lastTickMs to 0 so the resuming tick takes
    // tick()'s own `lastTickMs === 0` branch (dt = 0, i.e. "first tick",
    // exactly like the very first spring the process ever ran) instead of
    // its long-gap branch. A real mid-flight compositor stall (registry
    // already non-empty, painting resumes after a pause) is untouched --
    // _wasIdle is only ever true while activeCount is 0, and that dt>250ms
    // guard still fires for it exactly as designed.
    property bool _wasIdle: true
    onActiveCountChanged: {
        if (root.activeCount > 0) {
            if (root._wasIdle) {
                root.lastTickMs = 0
                root._wasIdle = false
            }
        } else {
            root._wasIdle = true
        }
    }

    function register(mv) {
        if (registry.indexOf(mv) === -1) {
            registry.push(mv)
            registryChanged()
        }
    }
    function unregister(mv) {
        const i = registry.indexOf(mv)
        if (i !== -1) { registry.splice(i, 1); registryChanged() }
    }

    /**
     * REFRESH PERIOD. The highest refreshRate reported across all Hyprland
     * monitors (Hyprland.monitors[i].lastIpcObject.refreshRate -- confirmed
     * against src/wayland/hyprland/ipc/monitor.hpp: HyprlandMonitor has no
     * dedicated refreshRate property, only lastIpcObject, which mirrors
     * `hyprctl monitors -j`'s "refreshRate" field verbatim). Deliberately the
     * HIGHEST rate, not the island's own screen's rate: on the desktop this
     * shell was designed on (240Hz primary + 60Hz secondary), 16.67ms
     * (60Hz) is exactly 4x4.17ms (240Hz), so quantizing every window's tick
     * to the fast period keeps the slow screen's steps aligned too. Falls
     * back to 60Hz (16.67ms) if Hyprland reports nothing usable, and is
     * exposed read-only so FrameProbe (core/FrameProbe.qml) could adopt it
     * later without this file changing again.
     */
    readonly property real refreshPeriodMs: _computeRefreshPeriodMs()

    function _computeRefreshPeriodMs(): real {
        const monitors = Hyprland.monitors?.values || []
        let maxRate = 0
        for (const monitor of monitors) {
            const rate = Number(monitor?.lastIpcObject?.refreshRate)
            if (rate > maxRate) maxRate = rate
        }
        return maxRate > 0 ? 1000.0 / maxRate : 1000.0 / 60.0
    }

    /**
     * WALL-CLOCK DEDUP + QUANTIZE. Multiple windows (one per screen) each
     * drive their own FrameAnimation at that screen's real vsync and all
     * call Motion.tick() with NO argument.
     *
     * TWO DRIVERS, ONE CLOCK. island/Island.qml's per-window FrameAnimation
     * and this file's own fallback `clock` FrameAnimation both run whenever
     * activeCount > 0 -- instrumenting tick() during a dashboard open/close
     * caught BOTH firing every frame (132 vs 134 calls over the same
     * window), the fallback trailing the island's call by ~15ms, so springs
     * were evaluated twice per frame at different wall-clock moments and
     * which result actually got presented was whichever driver fired last.
     * Same-frame dedup (below) makes a second same-frame caller a no-op.
     *
     * QUANTIZED DT. Date.now() at JS execution time is not a vsync
     * timestamp: measured island-driver gaps ranged 11-20ms (bulk 13-17) on
     * this 60Hz panel instead of a steady 16.67ms -- up to +-25% step error,
     * which reads as visible judder in a closed-form spring that is otherwise
     * exact. Qt's own FrameAnimation.frameTime is equally jittery (measured
     * p50 16.06ms, p95 17.93ms), so swapping to it would not fix this.
     * Instead, raw elapsed time is rounded to the nearest whole multiple of
     * the display's refresh period (refreshPeriodMs above) before being fed
     * to the springs, so every step is either exactly one frame or an exact
     * multiple of one -- eliminating the jitter without needing a steadier
     * timestamp source.
     *
     * dt policy: a stopped-painting gap (>250ms -- another workspace, a
     * locked session) SNAPs every active spring instead of replaying a
     * multi-second trajectory when the compositor resumes painting us. That
     * guard and the same-frame dedup below both key off the RAW wall-clock
     * gap (rawMs), never the quantized one. Otherwise `now` advances by the
     * quantized dt and every registered MotionValue is evaluated there.
     */
    function tick() {
        const live = registry.filter(mv => mv && typeof mv.evaluate === "function")
        if (live.length !== registry.length) registry = live

        const nowMs = Date.now()
        const isFirstTick = lastTickMs === 0
        const rawMs = isFirstTick ? 0 : (nowMs - lastTickMs)

        // WALL-CLOCK JUMPED BACKWARDS (NTP correcting a local-time RTC after
        // boot, a dual-boot classic): rawMs goes hugely negative, the
        // same-frame dedup below reads that as "same frame" and returns
        // without touching lastTickMs, so `now` froze until wall time caught
        // up (5.5h on 10 Oct) and every spring stood still. Re-baseline and
        // count this tick as a fresh first frame instead.
        if (rawMs < 0) {
            lastTickMs = nowMs
            return
        }

        // SAME-FRAME DEDUP. A second driver (the fallback `clock` racing
        // island/Island.qml's per-window FrameAnimation, or two islands on
        // two screens) firing within half a refresh period of the last real
        // tick is presenting the same frame again, not a new one -- bail
        // out before touching lastTickMs so it costs nothing and does not
        // perturb the next real driver's rawMs measurement. The very first
        // tick after idle (isFirstTick) always evaluates with dt 0, exactly
        // as before this change.
        if (!isFirstTick && rawMs < refreshPeriodMs * 0.5)
            return

        lastTickMs = nowMs

        if (rawMs > 250) {
            for (const mv of registry.slice()) mv.snap()
            now += rawMs / 1000.0
            return
        }

        const period = refreshPeriodMs
        const steps = isFirstTick ? 0 : Math.max(1, Math.round(rawMs / period))
        const dt = steps * period / 1000.0
        now += dt
        for (const mv of registry.slice()) mv.evaluate(now)
    }

    property real lastTickMs: 0

    // Real per-window drivers (island/Island.qml etc) call Motion.tick()
    // themselves from their OWN FrameAnimation so springs are evaluated
    // eagerly at that screen's real presentation rate. This fallback driver
    // keeps things working headless / before any such window exists.
    property FrameAnimation clock: FrameAnimation {
        running: root.activeCount > 0
        onTriggered: root.tick()
    }
}
