#!/usr/bin/env python3
"""macwm: macOS-like window placement for Hyprland (user daemon, stdlib only).

Reads Hyprland's event socket (socket2) and keeps:
  * float-by-default placement: windows float (hl.window_rule in
    hypr/hyprland/mac-windows.lua); per-workspace tile rules make windows on a
    tiled workspace tile at open, and a dispatch fallback covers rule failures;
  * a per-workspace tiling toggle, persisted in the state file;
  * MRU focus hand-back on close, and keyboard snaps.

The Hyprland instance is re-resolved on every (re)connect, so a Hyprland
restart (new instance signature) is picked up without restarting macwm.

Control: JSON lines on $XDG_RUNTIME_DIR/macwm.sock (see macwmctl).
Dispatches produced by one wakeup are sent as a single `hyprctl --batch`.
--dry-run prints those batches and eval calls instead of running them,
and never writes state.
"""
import argparse
import json
import os
import re
import selectors
import socket
import subprocess
import sys
import time

GAME_RE = re.compile(r"^(cs2|steam_app_.*|gamescope)$")
STATE_FILE = os.path.expanduser("~/.local/state/qml-rice/macwm.json")
REFRESH_INTERVAL = 0.5   # at most 2 client refreshes per second
RECONNECT_CAP = 5.0      # seconds
HAND_BACK_WINDOW = 1.0   # a pending focus hand-back expires after this
TILE_WORKSPACES = range(1, 11)   # workspaces that have a macwm_tile[N] rule in mac-windows.lua


# ---- pure helpers ---------------------------------------------------------

def is_game(cls):
    return bool(GAME_RE.match(cls or ""))


def norm_addr(addr):
    """socket2 gives addresses without 0x; hyprctl -j gives them with it."""
    addr = (addr or "").strip()
    if not addr:
        return ""
    return addr if addr.startswith("0x") else "0x" + addr


def parse_ws(name):
    name = name.strip()
    return int(name) if re.fullmatch(r"-?\d+", name) else name


def parse_event(line):
    name, _, args = line.rstrip("\r\n").partition(">>")
    return name, args


def reconnect_delay(attempt):
    return min(RECONNECT_CAP, 0.25 * (2 ** min(attempt, 10)))


def batch_command(dispatches):
    return "; ".join("dispatch " + d for d in dispatches)


def batch_errors(text):
    """Lines of `hyprctl --batch` output other than a plain 'ok' acknowledgement."""
    return [ln.strip() for ln in text.splitlines() if ln.strip() and ln.strip().lower() != "ok"]


def eval_failed(rc, text):
    return rc != 0 or "error" in (text or "").lower()


def find_instance(runtime, env_sig=""):
    """Newest Hyprland instance under $XDG_RUNTIME_DIR/hypr that has a socket2.

    env_sig is accepted for symmetry but ignored: after a Hyprland restart the
    inherited signature is stale, while the newest live socket is current.
    """
    base = os.path.join(runtime, "hypr")
    try:
        names = os.listdir(base)
    except OSError:
        return None
    best, best_t = None, -1.0
    for name in names:
        try:
            t = os.stat(os.path.join(base, name, ".socket2.sock")).st_mtime
        except OSError:
            continue
        if t > best_t:
            best, best_t = name, t
    return best


def workarea(mon):
    left, top, right, bottom = mon.get("reserved", [0, 0, 0, 0])
    return (mon["x"] + left, mon["y"] + top,
            mon["width"] - left - right, mon["height"] - top - bottom)


def find_monitor(monitors, name):
    for m in monitors:
        if m["name"] == name:
            return m
    return None


def clamp_geometry(g, monitor):
    """Fit a saved geometry into the monitor's work area; None if the monitor is gone."""
    if monitor is None:
        return None
    wx, wy, ww, wh = workarea(monitor)
    w = min(g["w"], ww)
    h = min(g["h"], wh)
    x = min(max(g["x"], wx), wx + ww - w)
    y = min(max(g["y"], wy), wy + wh - h)
    return {"monitor": monitor["name"], "x": x, "y": y, "w": w, "h": h}


# Dispatch builders (Hyprland 0.56 Lua API, as used in shell/services/RunningApps.qml).

def _call(path, body):
    return "hl.dsp." + path + "({ " + body + " })"


def _win(addr):
    return 'window = "address:' + addr + '"'


def d_toggle_float(addr):
    return _call("window.float", 'action = "toggle", ' + _win(addr))


def float_dispatches(addr, want_floating, currently_floating):
    """Toggle only when the window is not already in the wanted state."""
    if bool(want_floating) == bool(currently_floating):
        return []
    return [d_toggle_float(addr)]


def d_focus(addr):
    return _call("focus", _win(addr))


def d_center(addr):
    return _call("window.center", _win(addr))


def d_resize(addr, w, h):
    return _call("window.resize", "x = %d, y = %d, relative = false, " % (w, h) + _win(addr))


def d_move(addr, x, y):
    return _call("window.move", "x = %d, y = %d, relative = false, " % (x, y) + _win(addr))


def restore_dispatches(addr, cls, geometry, monitors):
    """Put a floating window back where its class last was, or centre it."""
    g = geometry.get(cls)
    if g is None:
        return [d_center(addr)]
    cg = clamp_geometry(g, find_monitor(monitors, g.get("monitor")))
    if cg is None:
        return [d_center(addr)]
    return [d_resize(addr, cg["w"], cg["h"]), d_move(addr, cg["x"], cg["y"])]


def decide_open(cls, workspace_id, tiled, geometry, monitors, addr):
    """Dispatches for a window that has just opened.

    On a tiled workspace nothing is dispatched: the per-workspace tile rule
    tiles the window at open. The daemon adds a fallback when that rule is down.
    """
    if is_game(cls) or workspace_id in tiled:
        return []
    return restore_dispatches(addr, cls, geometry, monitors)


def tiling_dispatches(now_tiled, windows, geometry, monitors):
    """Dispatches for flipping a workspace's tiling. windows: dicts addr/class/floating."""
    out = []
    for w in windows:
        if is_game(w["class"]):
            continue
        if now_tiled:
            out += float_dispatches(w["addr"], False, w["floating"])
        else:
            if not w["floating"]:
                out += float_dispatches(w["addr"], True, False)
                out += restore_dispatches(w["addr"], w["class"], geometry, monitors)
    return out


def tile_eval(ws, enabled):
    return "macwm_tile[%d]:set_enabled(%s)" % (ws, "true" if enabled else "false")


def sync_eval(tiled):
    """One eval that sets every macwm_tile rule to match the tiled set."""
    return "; ".join(tile_eval(ws, ws in tiled) for ws in TILE_WORKSPACES)


def next_focus_after_close(closed_addr, closed_class, workspace_id, mru, clients):
    """Window to focus when the focused window closes, or None.

    Only the close of the focused window (mru[0]) hands focus back. The target
    stays on the same workspace; the same app wins, then most recently used.
    """
    if not mru or mru[0] != closed_addr:
        return None
    cands = [c for c in clients
             if c["address"] != closed_addr and c["workspace"] == workspace_id]
    if not cands:
        return None
    order = {a: i for i, a in enumerate(mru)}
    same = [c for c in cands if c["class"] == closed_class]
    pool = same or cands
    return min(pool, key=lambda c: order.get(c["address"], len(order)))["address"]


SNAP_DIRS = ("left", "right", "fill", "restore")


def snap_geometry(direction, monitor, current, presnap):
    """Target geometry for a keyboard snap inside the monitor's work area.

    `restore` returns the geometry from before the first snap (None if there is none).
    """
    if direction == "restore":
        return presnap
    wx, wy, ww, wh = workarea(monitor)
    if direction == "left":
        x, w = wx, ww // 2
    elif direction == "right":
        x, w = wx + ww // 2, ww - ww // 2
    elif direction == "fill":
        x, w = wx, ww
    else:
        return None
    return {"x": x, "y": wy, "w": w, "h": wh}


def snap_dispatches(addr, direction, workspace_id, tiled, floating, monitor, current, presnap):
    """Snapping only applies to a floating window on a floating workspace."""
    if workspace_id in tiled or not floating or monitor is None:
        return []
    g = snap_geometry(direction, monitor, current, presnap)
    if g is None:
        return []
    return [d_resize(addr, g["w"], g["h"]), d_move(addr, g["x"], g["y"])]


# ---- state file -----------------------------------------------------------

def load_state(path):
    # Tiling is the default (owner, 19 Oct): floating stays a per-workspace opt-in until
    # drag-to-snap, snap layouts and an overview exist.
    default = {"geometry": {}, "tiled": list(TILE_WORKSPACES)}
    if not path:
        return default
    try:
        with open(path) as f:
            st = json.load(f)
    except (OSError, ValueError):
        return default
    if not isinstance(st, dict):
        return default
    geom = st.get("geometry") if isinstance(st.get("geometry"), dict) else {}
    tiled = [t for t in st.get("tiled", default["tiled"]) if isinstance(t, int)]
    return {"geometry": geom, "tiled": tiled}


def save_state(path, state):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


def _log(msg):
    sys.stderr.write("macwm: %s\n" % msg)
    sys.stderr.flush()


# ---- daemon ---------------------------------------------------------------

class Daemon:
    def __init__(self, state_file=STATE_FILE, dry_run=False):
        self.state_file = state_file
        self.dry_run = dry_run
        st = load_state(state_file)
        self.geometry = st["geometry"]
        self.tiled = set(st["tiled"])
        self.tile_fallback = set()  # tiled workspaces whose tile rule is down
        self.instance = None        # Hyprland instance signature, re-resolved per connect
        self.mru = []               # window addresses, most recently focused first
        self.clients = {}           # address -> snapshot dict
        self.monitors = []
        self.dirty = False
        self.pending = None         # (target, workspace, monotonic time) after a close
        self.presnap = {}           # address -> geometry before its first snap
        self.last_refresh = 0.0
        self.evsock = None
        self.next_connect = 0.0
        self.attempt = 0

    # hyprctl plumbing -------------------------------------------------------

    def _resolve_instance(self):
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        self.instance = find_instance(runtime) if runtime else None
        return self.instance

    def _run_hypr(self, tail):
        """Run hyprctl against the resolved instance. Returns (rc, stdout, stderr)."""
        argv = ["hyprctl"]
        env = dict(os.environ)
        if self.instance:
            argv += ["--instance", self.instance]
            env["HYPRLAND_INSTANCE_SIGNATURE"] = self.instance
        argv += list(tail)
        try:
            p = subprocess.run(argv, capture_output=True, text=True, timeout=5, env=env)
        except (OSError, subprocess.TimeoutExpired) as e:
            return 1, "", str(e)
        return p.returncode, p.stdout, p.stderr

    def _hypr_json(self, args):
        rc, out, _ = self._run_hypr(["-j", *args])
        if rc != 0:
            return None
        try:
            return json.loads(out)
        except ValueError:
            return None

    def refresh(self):
        monitors = self._hypr_json(["monitors"])
        if monitors is not None:
            self.monitors = monitors
        clients = self._hypr_json(["clients"])
        if clients is None:
            return
        names = {m["id"]: m["name"] for m in self.monitors}
        snap = {}
        for c in clients:
            if not c.get("mapped", True):
                continue
            addr = norm_addr(c["address"])
            monitor = names.get(c.get("monitor"))
            x, y = c["at"]
            w, h = c["size"]
            snap[addr] = {
                "address": addr,
                "class": c.get("class", ""),
                "workspace": c["workspace"]["id"],
                "floating": bool(c.get("floating")),
                "monitor": monitor,
                "geom": {"monitor": monitor, "x": x, "y": y, "w": w, "h": h},
            }
        self.clients = snap
        self.mru = [a for a in self.mru if a in snap]

    def apply(self, dispatches):
        if not dispatches:
            return
        cmd = batch_command(dispatches)
        if self.dry_run:
            print(cmd, flush=True)
            return
        rc, out, err = self._run_hypr(["--batch", cmd])
        text = out + "\n" + err
        for line in batch_errors(text):
            _log("batch error: %s" % line)
        if rc != 0:
            _log("batch failed (rc %d): %s" % (rc, cmd))

    def _eval(self, code):
        """Run a Lua snippet in Hyprland. Returns True on success; logs failures."""
        if self.dry_run:
            print("eval " + code, flush=True)
            return True
        rc, out, err = self._run_hypr(["eval", code])
        if eval_failed(rc, out + err):
            _log("eval failed (rc %d): %s: %s" % (rc, code, (out + err).strip()))
            return False
        return True

    def _set_tile_rule(self, ws, enabled):
        ok = ws in TILE_WORKSPACES and self._eval(tile_eval(ws, enabled))
        if ok or not enabled:
            self.tile_fallback.discard(ws)
        else:
            self.tile_fallback.add(ws)
        return ok

    def sync_tile_rules(self):
        """Make every macwm_tile rule match the state. Runs on every (re)connect."""
        in_range = {ws for ws in self.tiled if ws in TILE_WORKSPACES}
        ok = self._eval(sync_eval(self.tiled))
        self.tile_fallback = set(self.tiled) if not ok else (self.tiled - in_range)
        return ok

    def _save(self):
        if self.dry_run or not self.state_file:
            return
        save_state(self.state_file, {"geometry": self.geometry, "tiled": sorted(self.tiled)})

    # actions ----------------------------------------------------------------

    def toggle_tiling(self, ws):
        now_tiled = ws not in self.tiled
        if now_tiled:
            self.tiled.add(ws)
        else:
            self.tiled.discard(ws)
        self._save()
        self._set_tile_rule(ws, now_tiled)
        windows = []
        for c in self.clients.values():
            if c["workspace"] == ws and not is_game(c["class"]):
                windows.append({"addr": c["address"], "class": c["class"], "floating": c["floating"]})
                c["floating"] = not now_tiled
        return tiling_dispatches(now_tiled, windows, self.geometry, self.monitors)

    def snap(self, direction):
        if direction not in SNAP_DIRS:
            return {"ok": False, "error": "dir must be one of %s" % ", ".join(SNAP_DIRS)}, []
        self.refresh()
        if not self.mru or self.mru[0] not in self.clients:
            return {"ok": False, "error": "no focused window"}, []
        addr = self.mru[0]
        c = self.clients[addr]
        mon = find_monitor(self.monitors, c["monitor"])
        before = self.presnap.get(addr)
        disp = snap_dispatches(addr, direction, c["workspace"], self.tiled, c["floating"],
                               mon, c["geom"], before)
        if disp:
            if direction == "restore":
                self.presnap.pop(addr, None)
            else:
                self.presnap.setdefault(addr, {k: c["geom"][k] for k in ("x", "y", "w", "h")})
        return {"ok": True, "dispatched": len(disp)}, disp

    def _active_workspace(self):
        j = self._hypr_json(["activeworkspace"])
        return j["id"] if isinstance(j, dict) and "id" in j else None

    def handle_command(self, cmd):
        name = cmd.get("cmd")
        if name == "status":
            return {"ok": True, "tiled": sorted(self.tiled), "mru": self.mru}, []
        if name == "toggle-tiling":
            ws = cmd.get("workspace")
            if ws is None:
                ws = self._active_workspace()
            if not isinstance(ws, int):
                return {"ok": False, "error": "no workspace"}, []
            self.refresh()
            disp = self.toggle_tiling(ws)
            return {"ok": True, "workspace": ws, "tiled": sorted(self.tiled)}, disp
        if name == "snap":
            return self.snap(cmd.get("dir"))
        return {"ok": False, "error": "unknown cmd: %s" % name}, []

    # events -----------------------------------------------------------------

    def _open_dispatches(self, cls, ws, addr):
        disp = decide_open(cls, ws, self.tiled, self.geometry, self.monitors, addr)
        if not is_game(cls) and ws in self.tiled and ws in self.tile_fallback:
            # The tile rule is down: the window is floating (blanket rule), so toggle it.
            disp = [d_toggle_float(addr)]
        return disp

    def _hand_back(self, active):
        """After a focused close, focus the chosen window, but only if Hyprland
        picked nothing or a different window on the same workspace."""
        if self.pending is None:
            return []
        target, ws, t0 = self.pending
        self.pending = None
        if time.monotonic() - t0 > HAND_BACK_WINDOW or active == target:
            return []
        if active and self.clients.get(active, {}).get("workspace") != ws:
            return []
        return [d_focus(target)]

    def on_event(self, name, args):
        if name == "openwindow":
            parts = args.split(",", 3)
            if len(parts) < 3:
                return []
            addr = norm_addr(parts[0])
            ws = parse_ws(parts[1])
            cls = parts[2]
            self.clients[addr] = {"address": addr, "class": cls, "workspace": ws,
                                  "floating": not is_game(cls) and ws not in self.tiled,
                                  "monitor": None, "geom": None}
            self.dirty = True
            return self._open_dispatches(cls, ws, addr)
        if name == "closewindow":
            addr = norm_addr(args)
            info = self.clients.pop(addr, None)
            if info is None:
                if addr in self.mru:
                    self.mru.remove(addr)
                return []
            target = next_focus_after_close(addr, info["class"], info["workspace"], self.mru,
                                            list(self.clients.values()))
            if addr in self.mru:
                self.mru.remove(addr)
            if target is not None:
                self.pending = (target, info["workspace"], time.monotonic())
            # geom is None for a window that closed before its first refresh.
            geom = info["geom"]
            if info["floating"] and not is_game(info["class"]) and geom and geom["monitor"]:
                self.geometry[info["class"]] = dict(geom)
                self._save()
            return []
        if name == "activewindowv2":
            addr = norm_addr(args)
            if addr:
                if addr in self.mru:
                    self.mru.remove(addr)
                self.mru.insert(0, addr)
            self.dirty = True
            return self._hand_back(addr)
        if name == "changefloatingmode":
            addr, _, flag = args.partition(",")
            c = self.clients.get(norm_addr(addr))
            if c is not None:
                c["floating"] = flag.strip() == "1"
            self.dirty = True
            return []
        if name == "movewindowv2":
            self.dirty = True
        if name == "configreloaded":
            # `hyprctl reload` recreates the macwm_tile rules disabled; re-sync from state.
            self.sync_tile_rules()
        return []

    # loop -------------------------------------------------------------------

    def _listen(self):
        runtime = os.environ.get("XDG_RUNTIME_DIR")
        if not runtime:
            sys.exit("macwm: XDG_RUNTIME_DIR is not set")
        self.ctl_path = os.path.join(runtime, "macwm.sock")
        try:
            os.unlink(self.ctl_path)
        except FileNotFoundError:
            pass
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.bind(self.ctl_path)
        os.chmod(self.ctl_path, 0o600)
        s.listen(8)
        return s

    def _event_socket_path(self):
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        if not runtime or not self.instance:
            return None
        return os.path.join(runtime, "hypr", self.instance, ".socket2.sock")

    def _connect_events(self):
        """Re-resolve the instance first: a Hyprland restart changes the signature."""
        self._resolve_instance()
        path = self._event_socket_path()
        if path is None:
            return None
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            s.connect(path)
        except OSError:
            s.close()
            return None
        return s

    def _on_connected(self):
        self.attempt = 0
        self.refresh()
        self.sync_tile_rules()
        self.last_refresh = time.monotonic()

    def _serve_control(self, conn):
        try:
            conn.settimeout(1.0)
            data = b""
            while b"\n" not in data and len(data) < 4096:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                data += chunk
            try:
                cmd = json.loads(data.decode("utf-8", "replace").strip() or "{}")
                if not isinstance(cmd, dict):
                    raise ValueError
            except ValueError:
                reply, disp = {"ok": False, "error": "bad json"}, []
            else:
                reply, disp = self.handle_command(cmd)
            self.apply(disp)
            conn.sendall((json.dumps(reply) + "\n").encode())
        except OSError:
            pass
        finally:
            conn.close()

    def _maybe_refresh(self, now):
        if self.dirty and now - self.last_refresh >= REFRESH_INTERVAL:
            self.refresh()
            self.dirty = False
            self.last_refresh = now

    def _timeout(self, now):
        waits = []
        if self.dirty:
            waits.append(max(0.0, self.last_refresh + REFRESH_INTERVAL - now))
        if self.evsock is None:
            waits.append(max(0.0, self.next_connect - now))
        return min(waits) if waits else None

    def run(self):
        ctl = self._listen()
        sel = selectors.DefaultSelector()
        sel.register(ctl, selectors.EVENT_READ, "ctl")
        buf = b""
        try:
            while True:
                now = time.monotonic()
                if self.evsock is None and now >= self.next_connect:
                    self.evsock = self._connect_events()
                    if self.evsock is not None:
                        sel.register(self.evsock, selectors.EVENT_READ, "ev")
                        buf = b""
                        self._on_connected()
                    else:
                        self.next_connect = now + reconnect_delay(self.attempt)
                        self.attempt += 1
                for key, _ in sel.select(self._timeout(time.monotonic())):
                    if key.data == "ctl":
                        conn, _ = ctl.accept()
                        self._serve_control(conn)
                    elif key.data == "ev":
                        try:
                            chunk = self.evsock.recv(65536)
                        except OSError:
                            chunk = b""
                        if not chunk:
                            sel.unregister(self.evsock)
                            self.evsock.close()
                            self.evsock = None
                            self.next_connect = time.monotonic() + reconnect_delay(0)
                            self.attempt = 0
                            buf = b""
                            continue
                        buf += chunk
                        disp = []
                        while b"\n" in buf:
                            line, buf = buf.split(b"\n", 1)
                            name, args = parse_event(line.decode("utf-8", "replace"))
                            disp += self.on_event(name, args)
                        self.apply(disp)
                self._maybe_refresh(time.monotonic())
        finally:
            sel.close()
            ctl.close()
            try:
                os.unlink(self.ctl_path)
            except OSError:
                pass


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--dry-run", action="store_true",
                    help="print dispatch batches and evals instead of running them; never writes state")
    args = ap.parse_args(argv)
    daemon = Daemon(state_file=STATE_FILE, dry_run=args.dry_run)
    daemon._resolve_instance()
    daemon.refresh()
    try:
        daemon.run()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
