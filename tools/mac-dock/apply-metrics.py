#!/usr/bin/env python3
"""Write measured values from metrics.json into shell/dock/DockMetrics.qml.

  python3 -I apply-metrics.py metrics.json [--qml PATH] [--dry-run]
  python3 -I apply-metrics.py --selftest

Only known numeric DockMetrics properties are touched, one `property` line at
a time; the trailing "// src:" comment is rewritten to say where the number
came from. Everything else in the file is left byte-for-byte alone.
"""
import argparse
import json
import math
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_QML = os.path.normpath(os.path.join(HERE, "..", "..", "shell", "dock", "DockMetrics.qml"))
LIMITS = {  # sanity ranges: a bad measurement must not brick the dock
    "tileSize": (16, 256), "peakScale": (1.0, 4.0), "radiusTiles": (0.5, 8.0),
    "bounceHeight": (0.05, 2.0), "bouncePeriod": (0.2, 3.0), "bounceRestFraction": (0.0, 0.8),
    "revealDelay": (0.0, 3.0), "hideDelay": (0.0, 3.0), "slideDuration": (0.05, 3.0),
    "slotGap": (0, 64), "shelfPadding": (0, 64), "shelfRadius": (0, 128), "dotSize": (1, 16),
    "pointerOmega": (5, 200), "rampOmega": (5, 200), "bounceMaxSeconds": (1, 60),
}
LINE = re.compile(r"^(?P<head>\s*readonly property (?:real|int) (?P<name>\w+):\s*)(?P<val>-?[0-9.]+)"
                  r"(?P<mid>\s*)// src: (?P<src>[^.\n]*)\.?(?P<desc>[^\n]*)$")


def fmt(v):
    r = round(float(v), 3)
    return str(int(r)) if r == int(r) else str(r)


def apply(text, metrics, label):
    changed, seen = [], set()
    out = []
    for line in text.split("\n"):
        m = LINE.match(line)
        if m and m["name"] in metrics:
            name = m["name"]
            v = metrics[name]
            if not isinstance(v, (int, float)) or isinstance(v, bool) or not math.isfinite(v):
                raise SystemExit(f"{name}: not a finite number: {v!r}")
            lo, hi = LIMITS.get(name, (-math.inf, math.inf))
            if not lo <= v <= hi:
                raise SystemExit(f"{name}={v} outside sane range [{lo}, {hi}]; refusing")
            desc = m["desc"].strip()
            line = f"{m['head']}{fmt(v)}{m['mid']}// src: measured {label}." + (f" {desc}" if desc else "")
            changed.append((name, m["val"], fmt(v)))
            seen.add(name)
        out.append(line)
    return "\n".join(out), changed, set(metrics) - seen


def selftest():
    sample = (
        "QtObject {\n"
        "    readonly property real tileSize: 48            // src: pending reference capture. Icon edge px @1x, resting\n"
        "    readonly property real peakScale: 2.0          // src: pending reference capture. Scale under pointer\n"
        "    readonly property string falloff: \"cosine\"     // src: pending reference capture. cosine or gauss\n"
        "    readonly property real bouncePeriod: 0.6       // src: pending reference capture. Seconds per bounce\n"
        "}\n")
    new, changed, unknown = apply(sample, {"tileSize": 52.0, "peakScale": 2.4, "nope": 1}, "from test.mov")
    ok = ("tileSize: 52 " in new and "peakScale: 2.4 " in new and "bouncePeriod: 0.6 " in new
          and 'falloff: "cosine"' in new and "// src: measured from test.mov. Icon edge px @1x, resting" in new
          and unknown == {"nope"} and len(changed) == 2 and new.count("pending reference capture") == 2)
    try:
        apply(sample, {"peakScale": 9.0}, "x")
        ok = False
    except SystemExit:
        pass
    # real file: applying nothing changes nothing
    if os.path.exists(DEFAULT_QML):
        real = open(DEFAULT_QML).read()
        same, ch, _ = apply(real, {}, "x")
        ok = ok and same == real and ch == []
        # every metric the analyzer can emit exists as a property line
        names = {m["name"] for m in map(LINE.match, real.split("\n")) if m}
        for k in ("tileSize", "peakScale", "radiusTiles", "bounceHeight", "bouncePeriod",
                  "bounceRestFraction", "revealDelay", "hideDelay", "slideDuration"):
            if k not in names:
                print("  FAIL  DockMetrics.qml has no property", k)
                ok = False
    print("apply-metrics selftest:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("metrics", nargs="?")
    ap.add_argument("--qml", default=DEFAULT_QML)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(selftest())
    if not a.metrics:
        ap.error("metrics.json required")
    data = json.load(open(a.metrics))
    metrics = data["metrics"] if "metrics" in data else data
    src = ", ".join(f"{k}={v}" for k, v in (data.get("source") or {}).items()) or os.path.basename(a.metrics)
    text = open(a.qml).read()
    new, changed, unknown = apply(text, metrics, f"from {src}")
    for n, old, nv in changed:
        print(f"  {n}: {old} -> {nv}")
    for n in sorted(unknown):
        print(f"  skipped unknown/unsupported metric: {n}")
    if a.dry_run or not changed:
        print("dry run / nothing to do; file untouched")
        return
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(a.qml))
    with os.fdopen(fd, "w") as f:
        f.write(new)
    os.replace(tmp, a.qml)
    print("updated", a.qml)


if __name__ == "__main__":
    main()
