"""Unit tests for macwm. Run: python3 -I tools/macwm/test_macwm.py

No test reaches Hyprland: Daemon._run_hypr is replaced by a fake for every
test case (except the one that checks the real argv, which patches subprocess).
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

# -I drops the script directory from sys.path, so add it explicitly.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import macwm  # noqa: E402

ORIG_RUN_HYPR = macwm.Daemon._run_hypr

DP1 = {"id": 0, "name": "DP-1", "x": 1920, "y": 0, "width": 1920, "height": 1080,
       "reserved": [0, 37, 0, 74]}
HDMI = {"id": 1, "name": "HDMI-A-1", "x": 0, "y": 125, "width": 1920, "height": 1080,
        "reserved": [0, 37, 0, 74]}
MONITORS = [DP1, HDMI]


def fake_hypr(eval_rc=0, eval_out="", batch_out="ok\n"):
    """Replacement for Daemon._run_hypr that records calls and answers read-only queries."""
    calls = []

    def run(self, tail):
        calls.append(list(tail))
        if tail and tail[0] == "-j":
            return 0, "[]", ""
        if tail and tail[0] == "eval":
            return eval_rc, eval_out, ""
        if tail and tail[0] == "--batch":
            return 0, batch_out, ""
        return 0, "", ""
    return run, calls


class Base(unittest.TestCase):
    def setUp(self):
        self.fake, self.calls = fake_hypr()
        patcher = mock.patch.object(macwm.Daemon, "_run_hypr", self.fake)
        patcher.start()
        self.addCleanup(patcher.stop)


class OpenDecisionTests(Base):
    def test_open_on_tiled_workspace_defers_to_tile_rule(self):
        self.assertEqual(macwm.decide_open("kitty", 3, {3}, {}, MONITORS, "0xab"), [])

    def test_open_on_floating_workspace_restores_geometry(self):
        geo = {"kitty": {"monitor": "DP-1", "x": 2000, "y": 100, "w": 900, "h": 600}}
        out = macwm.decide_open("kitty", 2, set(), geo, MONITORS, "0xab")
        self.assertEqual(len(out), 2)
        self.assertIn('x = 900, y = 600', out[0])
        self.assertIn('x = 2000, y = 100', out[1])
        self.assertIn('address:0xab', out[0])
        self.assertIn('address:0xab', out[1])

    def test_restore_dispatches_have_no_positional_exact(self):
        geo = {"kitty": {"monitor": "DP-1", "x": 2000, "y": 100, "w": 900, "h": 600}}
        for d in macwm.decide_open("kitty", 2, set(), geo, MONITORS, "0xab"):
            self.assertNotIn("exact", d)
            self.assertIn("relative = false", d)

    def test_open_without_saved_geometry_centres(self):
        out = macwm.decide_open("kitty", 2, set(), {}, MONITORS, "0xab")
        self.assertEqual(len(out), 1)
        self.assertIn("window.center", out[0])

    def test_geometry_for_missing_monitor_centres(self):
        geo = {"kitty": {"monitor": "GONE-1", "x": 10, "y": 10, "w": 800, "h": 600}}
        out = macwm.decide_open("kitty", 2, set(), geo, MONITORS, "0xab")
        self.assertEqual(len(out), 1)
        self.assertIn("window.center", out[0])

    def test_offscreen_geometry_clamped(self):
        g = {"monitor": "DP-1", "x": 9000, "y": -500, "w": 800, "h": 600}
        got = macwm.clamp_geometry(g, DP1)
        # work area of DP-1: x 1920..3840, y 37..1006
        self.assertEqual(got, {"monitor": "DP-1", "x": 3040, "y": 37, "w": 800, "h": 600})

    def test_clamp_with_missing_monitor_returns_none(self):
        self.assertIsNone(macwm.clamp_geometry({"monitor": "X", "x": 0, "y": 0, "w": 1, "h": 1}, None))

    def test_game_class_ignored(self):
        for cls in ("cs2", "steam_app_730", "gamescope"):
            self.assertEqual(macwm.decide_open(cls, 1, set(), {}, MONITORS, "0x1"), [], cls)
            self.assertEqual(macwm.decide_open(cls, 10, {10}, {}, MONITORS, "0x1"), [], cls)

    def test_parse_event_splits_on_first_double_gt(self):
        self.assertEqual(macwm.parse_event("openwindow>>a>>b"), ("openwindow", "a>>b"))
        self.assertEqual(macwm.parse_event("activewindowv2>>55fa\n"), ("activewindowv2", "55fa"))

    def test_reconnect_backoff_caps_at_5s(self):
        self.assertEqual(macwm.reconnect_delay(0), 0.25)
        self.assertEqual(macwm.reconnect_delay(3), 2.0)
        self.assertEqual(macwm.reconnect_delay(50), 5.0)

    def test_batch_joins_dispatches_with_semicolons(self):
        self.assertEqual(macwm.batch_command(["a", "b"]), "dispatch a; dispatch b")
        self.assertEqual(macwm.batch_command([]), "")

    def test_float_toggle_only_when_state_differs(self):
        self.assertEqual(macwm.float_dispatches("0x1", False, True), [macwm.d_toggle_float("0x1")])
        self.assertEqual(macwm.float_dispatches("0x1", False, False), [])
        self.assertEqual(macwm.float_dispatches("0x1", True, True), [])
        self.assertIn('action = "toggle"', macwm.d_toggle_float("0x1"))

    def test_tiling_dispatches_skip_windows_already_in_target_state(self):
        wins = [{"addr": "0x1", "class": "kitty", "floating": True},
                {"addr": "0x2", "class": "kitty", "floating": False}]
        out = macwm.tiling_dispatches(True, wins, {}, MONITORS)
        self.assertEqual(out, [macwm.d_toggle_float("0x1")])


class EvalStringTests(Base):
    def test_tile_eval_strings(self):
        self.assertEqual(macwm.tile_eval(3, True), "macwm_tile[3]:set_enabled(true)")
        self.assertEqual(macwm.tile_eval(3, False), "macwm_tile[3]:set_enabled(false)")

    def test_sync_eval_covers_workspaces_1_to_10(self):
        parts = macwm.sync_eval({3, 7, 12}).split("; ")
        self.assertEqual(len(parts), 10)
        on = {p for p in parts if p.endswith("(true)")}
        self.assertEqual(on, {"macwm_tile[3]:set_enabled(true)", "macwm_tile[7]:set_enabled(true)"})

    def test_connect_resyncs_tile_rules_from_state(self):
        d = macwm.Daemon(state_file=None, dry_run=False)
        d.tiled = set()  # floating start state
        d.tiled = {3}
        d._on_connected()
        evals = [c[1] for c in self.calls if c and c[0] == "eval"]
        self.assertEqual(evals, [macwm.sync_eval({3})])
        self.assertEqual(d.tile_fallback, set())

    def test_toggle_on_sets_only_that_rule(self):
        d = macwm.Daemon(state_file=None, dry_run=False)
        d.tiled = set()  # floating start state
        d.toggle_tiling(4)
        evals = [c[1] for c in self.calls if c and c[0] == "eval"]
        self.assertEqual(evals, ["macwm_tile[4]:set_enabled(true)"])

    def test_open_on_tiled_ws_falls_back_to_toggle_when_eval_fails(self):
        self.fake, self.calls = fake_hypr(eval_rc=1, eval_out="error: nil value")
        with mock.patch.object(macwm.Daemon, "_run_hypr", self.fake), \
                contextlib.redirect_stderr(io.StringIO()) as err:
            d = macwm.Daemon(state_file=None, dry_run=False)
            d.tiled = set()  # floating start state
            d.toggle_tiling(4)
            self.assertIn(4, d.tile_fallback)
            out = d.on_event("openwindow", "9,4,kitty,t")
        self.assertEqual(out, [macwm.d_toggle_float("0x9")])
        self.assertIn("eval failed", err.getvalue())

    def test_open_on_tiled_ws_no_fallback_when_eval_ok(self):
        d = macwm.Daemon(state_file=None, dry_run=False)
        d.tiled = set()  # floating start state
        d.toggle_tiling(4)
        self.assertEqual(d.on_event("openwindow", "9,4,kitty,t"), [])

    def test_out_of_range_workspace_uses_fallback(self):
        d = macwm.Daemon(state_file=None, dry_run=False)
        d.tiled = set()  # floating start state
        d.toggle_tiling(11)
        self.assertIn(11, d.tile_fallback)
        self.assertEqual([c for c in self.calls if c and c[0] == "eval"], [])

    def test_dry_run_prints_eval_without_calling_hyprctl(self):
        d = macwm.Daemon(state_file=None, dry_run=True)
        d.tiled = set()  # floating start state
        with contextlib.redirect_stdout(io.StringIO()) as out:
            d.toggle_tiling(2)
        self.assertIn("eval macwm_tile[2]:set_enabled(true)", out.getvalue())
        self.assertEqual(self.calls, [])


class InstanceTests(Base):
    def test_newest_instance_wins_over_stale_env(self):
        with tempfile.TemporaryDirectory() as rt:
            old = os.path.join(rt, "hypr", "old", ".socket2.sock")
            new = os.path.join(rt, "hypr", "new", ".socket2.sock")
            for p in (old, new):
                os.makedirs(os.path.dirname(p))
                open(p, "w").close()
            os.utime(old, (1000, 1000))
            os.utime(new, (2000, 2000))
            self.assertEqual(macwm.find_instance(rt, "old"), "new")

    def test_no_socket_gives_none(self):
        with tempfile.TemporaryDirectory() as rt:
            os.makedirs(os.path.join(rt, "hypr", "dead"))
            self.assertIsNone(macwm.find_instance(rt, "dead"))
            self.assertIsNone(macwm.find_instance(os.path.join(rt, "missing")))

    def test_connect_reresolves_instance_after_restart(self):
        with tempfile.TemporaryDirectory() as rt, \
                mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": rt,
                                             "HYPRLAND_INSTANCE_SIGNATURE": "old"}):
            old = os.path.join(rt, "hypr", "old", ".socket2.sock")
            os.makedirs(os.path.dirname(old))
            open(old, "w").close()
            os.utime(old, (1000, 1000))
            d = macwm.Daemon(state_file=None, dry_run=True)
            d.tiled = set()  # floating start state
            d._resolve_instance()
            self.assertEqual(d.instance, "old")
            # Hyprland restarts: a new instance appears with a newer socket.
            new = os.path.join(rt, "hypr", "new", ".socket2.sock")
            os.makedirs(os.path.dirname(new))
            open(new, "w").close()
            os.utime(new, (2000, 2000))
            d._connect_events()   # re-resolves; the socket itself is absent, so this returns None
            self.assertEqual(d.instance, "new")
            self.assertTrue(d._event_socket_path().endswith(os.path.join("new", ".socket2.sock")))

    def test_hyprctl_subprocess_gets_resolved_instance(self):
        d = macwm.Daemon(state_file=None, dry_run=True)
        d.tiled = set()  # floating start state
        d.instance = "NEWSIG"
        with mock.patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "STALE"}), \
                mock.patch.object(macwm.subprocess, "run") as run:
            run.return_value = mock.Mock(returncode=0, stdout="[]", stderr="")
            ORIG_RUN_HYPR(d, ["-j", "clients"])
        argv = run.call_args[0][0]
        env = run.call_args[1]["env"]
        self.assertEqual(argv, ["hyprctl", "--instance", "NEWSIG", "-j", "clients"])
        self.assertEqual(env["HYPRLAND_INSTANCE_SIGNATURE"], "NEWSIG")


    def test_configreloaded_triggers_resync(self):
        d = macwm.Daemon(state_file=None, dry_run=False)
        d.tiled = set()  # floating start state
        d.tiled = {3}
        self.calls.clear()
        self.assertEqual(d.on_event("configreloaded", ""), [])
        evals = [c[1] for c in self.calls if c and c[0] == "eval"]
        self.assertEqual(evals, [macwm.sync_eval({3})])


class ErrorLoggingTests(Base):
    def test_batch_errors_are_logged(self):
        self.fake, self.calls = fake_hypr(batch_out="ok\nerror: invalid dispatcher\n")
        with mock.patch.object(macwm.Daemon, "_run_hypr", self.fake), \
                contextlib.redirect_stderr(io.StringIO()) as err:
            d = macwm.Daemon(state_file=None, dry_run=False)
            d.tiled = set()  # floating start state
            d.apply(["hl.dsp.focus({ window = \"address:0x1\" })"])
        self.assertIn("invalid dispatcher", err.getvalue())

    def test_batch_errors_parser(self):
        self.assertEqual(macwm.batch_errors("ok\nok\n"), [])
        self.assertEqual(macwm.batch_errors("ok\nerror: bad\n"), ["error: bad"])


class StateTests(Base):
    def test_toggle_tiling_persists(self):
        everything = set(macwm.TILE_WORKSPACES)
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "sub", "macwm.json")
            self.assertEqual(macwm.Daemon(state_file=path, dry_run=True).tiled, everything)
            daemon = macwm.Daemon(state_file=path, dry_run=False)
            daemon.toggle_tiling(3)
            with open(path) as f:
                self.assertEqual(json.load(f)["tiled"], sorted(everything - {3}))
            reloaded = macwm.Daemon(state_file=path, dry_run=True)
            self.assertEqual(reloaded.tiled, everything - {3})
            macwm.Daemon(state_file=path, dry_run=False).toggle_tiling(3)
            self.assertEqual(macwm.Daemon(state_file=path, dry_run=True).tiled, everything)

    def test_corrupt_state_falls_back_to_default(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "macwm.json")
            with open(path, "w") as f:
                f.write("[1, 2]")
            st = macwm.load_state(path)
            self.assertEqual(st, {"geometry": {}, "tiled": list(macwm.TILE_WORKSPACES)})

    def test_toggle_off_refloats_at_saved_geometry(self):
        d = macwm.Daemon(state_file=None, dry_run=False)
        d.tiled = set()  # floating start state
        d.geometry = {"kitty": {"monitor": "DP-1", "x": 2000, "y": 100, "w": 900, "h": 600}}
        d.tiled = {4}
        d.clients = {"0xab": {"address": "0xab", "class": "kitty", "workspace": 4,
                              "floating": False, "monitor": "DP-1", "geom": None}}
        d.monitors = MONITORS
        out = d.toggle_tiling(4)
        self.assertEqual(d.tiled, set())
        self.assertIn(macwm.d_toggle_float("0xab"), out)
        self.assertTrue(any("window.resize" in x for x in out))
        self.assertTrue(all("exact" not in x for x in out))

    def test_close_before_first_geometry_does_not_crash(self):
        d = macwm.Daemon(state_file=None, dry_run=True)
        d.tiled = set()  # floating start state
        d.monitors = MONITORS
        d.on_event("openwindow", "5,1,kitty,t")
        self.assertIsNone(d.clients["0x5"]["geom"])
        self.assertEqual(d.on_event("closewindow", "5"), [])
        self.assertNotIn("kitty", d.geometry)

    def test_hand_back_dispatches_only_when_hyprland_differs(self):
        def fresh():
            d = macwm.Daemon(state_file=None, dry_run=True)
            d.tiled = set()  # floating start state
            d.clients = {
                "0x1": {"address": "0x1", "class": "kitty", "workspace": 1, "floating": True,
                        "monitor": "DP-1", "geom": {"monitor": "DP-1", "x": 0, "y": 0, "w": 1, "h": 1}},
                "0x2": {"address": "0x2", "class": "kitty", "workspace": 1, "floating": True,
                        "monitor": "DP-1", "geom": {"monitor": "DP-1", "x": 0, "y": 0, "w": 1, "h": 1}},
            }
            d.mru = ["0x1", "0x2"]
            return d
        d = fresh()
        self.assertEqual(d.on_event("closewindow", "1"), [])
        out = d.on_event("activewindowv2", "")
        self.assertEqual(len(out), 1)
        self.assertIn('address:0x2', out[0])
        self.assertIn("hl.dsp.focus", out[0])
        d = fresh()
        d.on_event("closewindow", "1")
        self.assertEqual(d.on_event("activewindowv2", "2"), [])
        d = fresh()
        d.on_event("closewindow", "2")   # closing an unfocused window: nothing pending
        self.assertEqual(d.mru, ["0x1"])
        self.assertEqual(d.on_event("activewindowv2", ""), [])


class SnapTests(Base):
    def test_snap_left_half_of_workarea(self):
        g = macwm.snap_geometry("left", DP1, {"x": 0, "y": 0, "w": 1, "h": 1}, None)
        self.assertEqual(g, {"x": 1920, "y": 37, "w": 960, "h": 969})

    def test_snap_right_half_covers_odd_width(self):
        odd = dict(DP1, width=1921)
        g = macwm.snap_geometry("right", odd, {"x": 0, "y": 0, "w": 1, "h": 1}, None)
        self.assertEqual(g["x"] + g["w"], 1920 + 1921)
        self.assertEqual(g["y"], 37)

    def test_snap_restore_returns_presnap_geometry(self):
        pre = {"x": 100, "y": 200, "w": 700, "h": 500}
        self.assertEqual(macwm.snap_geometry("restore", DP1, {"x": 0, "y": 0, "w": 1, "h": 1}, pre), pre)
        self.assertIsNone(macwm.snap_geometry("restore", DP1, {"x": 0, "y": 0, "w": 1, "h": 1}, None))

    def test_snap_on_tiled_workspace_is_noop(self):
        out = macwm.snap_dispatches("0xab", "left", 3, {3}, True, DP1,
                                    {"x": 0, "y": 0, "w": 1, "h": 1}, None)
        self.assertEqual(out, [])

    def test_snap_fill_uses_whole_workarea(self):
        out = macwm.snap_dispatches("0xab", "fill", 2, set(), True, DP1,
                                    {"x": 0, "y": 0, "w": 1, "h": 1}, None)
        self.assertIn("x = 1920, y = 969", out[0])
        self.assertIn("x = 1920, y = 37", out[1])


if __name__ == "__main__":
    unittest.main()
