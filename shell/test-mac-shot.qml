// Logic test for shell/mac/MacShotThumbnail.qml: the screenshot thumbnail
// queue (FIFO), the 5 s lifetime, hover pause, the pending cap, the
// first-read priming that stops old captures replaying at shell start, and
// the JSONL parser's rejection of bad lines. The live card is never shown:
// autoTick is off and tick() is driven by the test. The queue file path
// points at a temp file, so the owner's runtime dir is never read.
// Run: QT_QPA_PLATFORM=offscreen qs -p test-mac-shot.qml
import QtQuick
import Quickshell
import "core"
import "mac"

ShellRoot {
    id: root
    property var log: []
    function ok(name, cond, detail) {
        log.push((cond ? "PASS  " : "FAIL  ") + name + (detail ? "   " + detail : ""))
    }

    Timer {
        interval: 30; running: true; repeat: false
        onTriggered: root.run()
    }

    MacShotThumbnail {
        id: shot
        autoTick: false
        queuePath: "/tmp/qmlrice-mac-shot-test-" + Date.now() + ".jsonl"
    }

    // Default path, no override: must sit under the runtime dir, and be empty
    // (feature off) when XDG_RUNTIME_DIR is unset. Never /tmp.
    MacShotThumbnail {
        id: defaults
        autoTick: false
    }

    function line(id, path) {
        // Fixtures sit in the screenshot folder: the path gate rejects anything else.
        return JSON.stringify({ id: id, path: path || (shot.screenshotDir + "shot-" + id + ".png"), mode: "area" })
    }

    function ids(list) {
        return list.map(e => e.id).join(",")
    }

    function run() {
        // ---- offscreen: layer shell must be off so the window is never built
        root.ok("layer_shell_off_offscreen", MacTokens.layerShell === false)
        const dq = defaults.queuePath
        root.ok("default_queue_never_tmp", dq.indexOf("/tmp") !== 0
            && (defaults.runtimeDir === "" ? dq === ""
                : dq === defaults.runtimeDir + "/qml-rice/mac-shot.jsonl"),
            "queuePath=" + dq)
        root.ok("starts_idle", shot.current === null && shot.pending.length === 0 && !shot.busy)

        // ---- priming: history present at shell start is marked, not shown
        const primed = shot.ingest(line("h1") + "\n" + line("h2") + "\n", false)
        root.ok("priming_shows_nothing", primed === 0 && shot.current === null,
            "added=" + primed)
        root.ok("priming_marks_seen", shot.isSeen("h1") && shot.isSeen("h2"))

        // ---- first live capture shows immediately with the full lifetime
        shot.ingest(line("a1"), true)
        root.ok("first_capture_on_screen", shot.current !== null && shot.current.id === "a1",
            "current=" + (shot.current ? shot.current.id : "null"))
        root.ok("lifetime_is_5s", shot.remainingMs === 5000 && shot.lifetimeMs === 5000,
            "remaining=" + shot.remainingMs)

        // ---- duplicates and bad lines are ignored
        root.ok("duplicate_ignored", shot.ingest(line("a1"), true) === 0)
        const bad = [
            "not json",
            JSON.stringify({ id: "x1" }),
            JSON.stringify({ id: 7, path: "/tmp/n.png" }),
            JSON.stringify({ id: "x2", path: "" }),
            "null",
            "",
        ].join("\n")
        root.ok("bad_lines_ignored", shot.ingest(bad, true) === 0 && shot.pending.length === 0,
            "pending=" + shot.pending.length)

        // ---- later captures queue FIFO behind the one on screen
        shot.ingest(line("a2") + "\n" + line("a3"), true)
        root.ok("queued_not_shown", shot.current.id === "a1"
            && ids(shot.pending) === "a2,a3", "pending=" + ids(shot.pending))

        // ---- countdown: 4 s keeps it, the 5th second advances
        shot.tick(4000)
        root.ok("still_shown_at_4s", shot.current.id === "a1", "remaining=" + shot.remainingMs)
        shot.tick(1000)
        root.ok("advances_at_5s_fifo", shot.current.id === "a2" && ids(shot.pending) === "a3",
            "current=" + shot.current.id)
        root.ok("lifetime_resets_on_advance", shot.remainingMs === 5000)

        // ---- hover freezes the countdown
        shot.hovered = true
        shot.tick(20000)
        root.ok("hover_pauses_countdown", shot.current.id === "a2" && shot.remainingMs === 5000)
        shot.hovered = false
        shot.tick(100)
        root.ok("resumes_after_hover", shot.remainingMs === 4900)

        // ---- the pending cap drops the oldest queued entry
        let burst = []
        for (let i = 0; i < shot.maxPending + 3; i++)
            burst.push(line("b" + i))
        shot.ingest(burst.join("\n"), true)
        root.ok("pending_capped", shot.pending.length === shot.maxPending,
            "pending=" + shot.pending.length + " max=" + shot.maxPending)
        // Before the burst pending was [a3]; with 11 more it held 12, so the
        // four oldest (a3, b0, b1, b2) go and b3..b10 remain.
        root.ok("oldest_dropped_newest_kept", shot.pending[0].id === "b3"
            && shot.pending[shot.pending.length - 1].id === "b" + (shot.maxPending + 2),
            "pending=" + ids(shot.pending))

        // ---- drain: every entry leaves, then the card clears
        let guard = 0
        while (shot.current !== null && guard < 100) {
            shot.tick(5000)
            guard++
        }
        root.ok("drains_to_idle", shot.current === null && shot.pending.length === 0
            && !shot.busy, "guard=" + guard)

        // ---- seen cap bounds memory on a long session
        let many = []
        for (let i = 0; i < shot.seenCap + 50; i++)
            many.push(line("s" + i))
        shot.ingest(many.join("\n"), false)
        root.ok("seen_list_capped", shot.seenIds.length === shot.seenCap,
            "seen=" + shot.seenIds.length)

        // ---- path gate: only absolute, traversal-free PNGs inside the
        // screenshot folder are ever shown or acted on
        const dir = shot.screenshotDir
        root.ok("screenshot_dir_from_home", dir !== "" && dir.slice(-"/Pictures/Screenshots/".length)
            === "/Pictures/Screenshots/", "dir=" + dir)
        const hostile = [
            JSON.stringify({ id: "p1", path: "/etc/passwd", mode: "area" }),
            JSON.stringify({ id: "p2", path: dir + "../../../../etc/passwd.png", mode: "area" }),
            JSON.stringify({ id: "p3", path: "file://" + dir + "ok.png", mode: "area" }),
            JSON.stringify({ id: "p4", path: dir + "ok.jpg", mode: "area" }),
            JSON.stringify({ id: "p5", path: "/tmp/evil.png", mode: "area" }),
            JSON.stringify({ id: "p6", path: "Screenshots/ok.png", mode: "area" }),
            JSON.stringify({ id: "p7", path: dir + "a/../../evil.png", mode: "area" }),
            JSON.stringify({ id: "p8", path: 42, mode: "area" }),
        ].join("\n")
        root.ok("hostile_paths_rejected", shot.ingest(hostile, true) === 0
            && shot.current === null && shot.pending.length === 0)
        root.ok("safe_path_accepted", shot.safePath(dir + "Screenshot 2026-10-21 at 02.02.22.png"))
        root.ok("safe_path_rejects_dotdot_in_name", !shot.safePath(dir + "x..y.png"))

        // A rejected current never reaches gio or the opener. Force one in
        // directly, since ingest would not let it through.
        shot.current = { id: "forced", path: "/etc/passwd", mode: "area" }
        const before = shot.spawnCount
        shot.discard()
        root.ok("discard_refuses_outside_path", shot.spawnCount === before && shot.current === null)
        shot.current = { id: "forced2", path: "/etc/passwd", mode: "area" }
        shot.openCurrent()
        root.ok("open_refuses_outside_path", shot.spawnCount === before && shot.current === null)

        // ---- idle ingest shows at once with a fresh countdown
        shot.ingest(line("z1"), true)
        root.ok("idle_ingest_shows_now", shot.current.id === "z1" && shot.remainingMs === 5000)

        root.finish()
    }

    function finish() {
        for (const l of root.log) console.log(l)
        const failed = root.log.filter(l => l.indexOf("FAIL") === 0).length
        console.log("=== " + (root.log.length - failed) + "/" + root.log.length + " passed ===")
        Qt.exit(failed === 0 ? 0 : 1)
    }
}
