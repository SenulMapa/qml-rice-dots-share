#!/usr/bin/env python3
"""Log system stalls (PSI) over 250 ms with the top offending processes.

Stdlib only. Runs as a systemd user service (see stallmon.service).

Mechanism: open /proc/pressure/{memory,io,cpu} and write a trigger
"some 250000 2000000" plus a NUL byte: 250 ms of stall within a 2 s window
(12.5% duty). Unprivileged triggers need a window that is a multiple of 2 s,
and the kernel overwrites the last byte of the write with NUL, so the NUL
must be written explicitly. Then wait on the fds with POLLPRI. If arming
fails (any OSError), fall back to sampling the cumulative "some" total= once
per second and logging when the delta reaches 250 ms per elapsed second.

Output: one JSON line per event appended to
$HOME/.local/state/qml-rice/stalls.jsonl (rotated to .1 at 5 MB).
Recording failures are logged to stderr and never stop the monitor.
"""
import datetime
import json
import os
import select
import sys
import time

KINDS = ("memory", "io", "cpu")
PSI_DIR = "/proc/pressure"
THRESHOLD_MS = 250
TRIGGER_WINDOW_US = 2_000_000  # unprivileged triggers need a multiple of 2 s
MAX_BYTES = 5_000_000
TOP_N = 5
CLK_TCK = os.sysconf("SC_CLK_TCK")
PAGE_SIZE = os.sysconf("SC_PAGE_SIZE")


def state_path():
    home = os.environ.get("HOME") or os.path.expanduser("~")
    return os.path.join(home, ".local", "state", "qml-rice", "stalls.jsonl")


def trigger_spec():
    """Bytes written to arm a trigger; NUL-terminated (the kernel needs it)."""
    return ("some %d %d\x00" % (THRESHOLD_MS * 1000, TRIGGER_WINDOW_US)).encode()


def format_event(kind, stall_ms, top, ts=None):
    if ts is None:
        ts = datetime.datetime.now(datetime.timezone.utc).isoformat(
            timespec="milliseconds")
    obj = {"ts": ts, "kind": kind, "stall_ms": int(stall_ms), "top": top}
    return json.dumps(obj, separators=(",", ":")) + "\n"


def append_event(path, line, max_bytes=MAX_BYTES):
    try:
        if os.path.getsize(path) >= max_bytes:
            os.replace(path, path + ".1")
    except FileNotFoundError:
        pass
    with open(path, "a", encoding="utf-8") as f:
        f.write(line)


def record_events(path, events, top):
    """Write one line per (kind, stall_ms). Never raises; logs to stderr."""
    for kind, stall_ms in events:
        try:
            append_event(path, format_event(kind, stall_ms, top))
        except OSError as e:
            print("stallmon: cannot record %s event to %s: %s"
                  % (kind, path, e), file=sys.stderr, flush=True)


def delta_trigger(prev_total_us, cur_total_us, threshold_ms=THRESHOLD_MS,
                  elapsed_s=1.0):
    """True if the stall delta reaches threshold_ms per elapsed second."""
    return (cur_total_us - prev_total_us) >= threshold_ms * 1000 * elapsed_s


def classify_poll_event(ev):
    """'stall' for a POLLPRI trigger, 'dead' for an fd that cannot fire."""
    if ev & select.POLLPRI:
        return "stall"
    if ev & (select.POLLERR | select.POLLNVAL | select.POLLHUP):
        return "dead"
    return None


def read_total(kind):
    """Cumulative microseconds of 'some' stall time for a PSI file."""
    with open(os.path.join(PSI_DIR, kind), "r") as f:
        for line in f:
            if line.startswith("some "):
                for field in line.split():
                    if field.startswith("total="):
                        return int(field[len("total="):])
    raise OSError("no 'some total=' in %s" % kind)


def _snapshot():
    snap = {}
    own = str(os.getpid())
    for name in os.listdir("/proc"):
        if not name.isdigit() or name == own:
            continue
        try:
            with open("/proc/%s/stat" % name, "r") as f:
                raw = f.read()
            comm = raw[raw.index("(") + 1:raw.rindex(")")]
            rest = raw[raw.rindex(")") + 2:].split()
            ticks = int(rest[11]) + int(rest[12])  # utime + stime
            with open("/proc/%s/statm" % name, "r") as f:
                rss_pages = int(f.read().split()[1])
        except (OSError, ValueError, IndexError):
            continue
        io_r = io_w = 0
        try:
            with open("/proc/%s/io" % name, "r") as f:
                for line in f:
                    if line.startswith("read_bytes:"):
                        io_r = int(line.split()[1])
                    elif line.startswith("write_bytes:"):
                        io_w = int(line.split()[1])
        except OSError:
            pass  # not ours to read; I/O counts stay at 0
        snap[int(name)] = {
            "comm": comm, "ticks": ticks, "rss": rss_pages * PAGE_SIZE,
            "io_r": io_r, "io_w": io_w,
        }
    return snap


def top_procs(n=TOP_N, window=0.25):
    """Top-n processes by CPU over a short window, with RSS and disk I/O."""
    before = _snapshot()
    time.sleep(window)
    after = _snapshot()
    rows = []
    for pid, b in before.items():
        a = after.get(pid)
        if a is None:
            continue
        dticks = max(0, a["ticks"] - b["ticks"])
        rows.append({
            "pid": pid,
            "comm": a["comm"],
            "cpu_pct": round(dticks / CLK_TCK / window * 100, 1),
            "rss_mb": round(a["rss"] / 1048576, 1),
            "io_read_kb": round(max(0, a["io_r"] - b["io_r"]) / 1024, 1),
            "io_write_kb": round(max(0, a["io_w"] - b["io_w"]) / 1024, 1),
        })
    rows.sort(key=lambda r: (r["cpu_pct"], r["rss_mb"]), reverse=True)
    return rows[:n]


def _sample_top():
    """One /proc sample; an error here must not stop the monitor."""
    try:
        return top_procs()
    except OSError as e:
        print("stallmon: process sample failed: %s" % e, file=sys.stderr,
              flush=True)
        return []


def _open_triggers():
    """Arm a PSI trigger per kind. Returns {fd: kind}, or raises OSError."""
    fds = {}
    try:
        for kind in KINDS:
            fd = os.open(os.path.join(PSI_DIR, kind), os.O_RDWR | os.O_NONBLOCK)
            fds[fd] = kind
            os.write(fd, trigger_spec())
    except OSError:
        for fd in fds:
            os.close(fd)
        raise
    return fds


def run_triggers(path, fds):
    """Wait on armed triggers. Returns once no trigger fd is left alive."""
    poller = select.poll()
    last = {}
    for fd, kind in fds.items():
        poller.register(fd, select.POLLPRI)
        try:
            last[kind] = read_total(kind)
        except OSError:
            last[kind] = None
    while fds:
        fired = []
        for fd, ev in poller.poll():
            kind = fds.get(fd)
            if kind is None:
                continue
            state = classify_poll_event(ev)
            if state == "stall":
                fired.append(kind)
            elif state == "dead":
                print("stallmon: %s trigger fd dropped (revents=%#x)"
                      % (kind, ev), file=sys.stderr, flush=True)
                poller.unregister(fd)
                os.close(fd)
                del fds[fd]
        if not fired:
            continue
        # One stall-time read per resource, then one /proc sample shared
        # by every resource that fired in this tick.
        events = []
        for kind in fired:
            try:
                cur = read_total(kind)
            except OSError:
                continue
            if last.get(kind) is None:
                last[kind] = cur
                continue
            # Stall time accrued since the last event, floored at the trigger.
            stall_ms = max(THRESHOLD_MS, (cur - last[kind]) // 1000)
            last[kind] = cur
            events.append((kind, stall_ms))
        if events:
            record_events(path, events, _sample_top())


def run_fallback(path):
    last = {}
    t_last = time.monotonic()
    for kind in KINDS:
        try:
            last[kind] = read_total(kind)
        except OSError:
            pass
    while True:
        time.sleep(1)
        now = time.monotonic()
        elapsed = now - t_last
        t_last = now
        fired = []
        for kind in list(last):
            try:
                cur = read_total(kind)
            except OSError:
                continue
            if delta_trigger(last[kind], cur, elapsed_s=elapsed):
                fired.append((kind, (cur - last[kind]) // 1000))
            last[kind] = cur
        if fired:
            record_events(path, fired, _sample_top())


def main():
    path = state_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
    except OSError as e:
        print("stallmon: cannot create %s: %s" % (os.path.dirname(path), e),
              file=sys.stderr, flush=True)
    try:
        fds = _open_triggers()
    except OSError as e:
        print("stallmon: mode=fallback (PSI trigger refused: %s); "
              "polling total= every 1 s" % e, file=sys.stderr, flush=True)
        run_fallback(path)
        return
    print("stallmon: mode=psi-trigger (%s; 250 ms in 2 s window)"
          % ", ".join(fds.values()), file=sys.stderr, flush=True)
    run_triggers(path, fds)
    print("stallmon: mode=fallback (all PSI triggers dropped); "
          "polling total= every 1 s", file=sys.stderr, flush=True)
    run_fallback(path)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
