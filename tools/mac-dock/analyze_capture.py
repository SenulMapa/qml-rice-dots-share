#!/usr/bin/env python3
"""Measure the REAL macOS dock from screen recordings -> metrics.json.

Run with:  python3 -I analyze_capture.py --sweep sweep.mov [--bounce b.mov]
           [--autohide a.mov --arrival-t 1.2 --leave-t 4.0] --crop X,Y,W,H
           [--pixel-ratio 2] [--out metrics.json]
           python3 -I analyze_capture.py --selftest

Needs ffmpeg + ffprobe on PATH and numpy (checked, never installed). All the
estimators work on small per-frame feature dicts, so --selftest can prove them
against synthetic recordings with known ground truth.

What is measured (see README.md for how to record):
  sweep    tileSize, peakScale, radiusTiles   (icon size vs pointer distance)
  bounce   bounceHeight, bouncePeriod, bounceRestFraction
  autohide slideDuration, revealDelay, hideDelay (delays need --arrival-t /
           --leave-t: seconds into the video when the pointer reaches / leaves
           the screen edge, read off the video in QuickTime)
"""
import argparse
import json
import math
import os
import shutil
import subprocess
import sys

try:
    import numpy as np
except ImportError:  # pragma: no cover
    np = None

THRESH = 48        # per-channel difference from the plain wallpaper = "icon pixel"
MIN_COL_PX = 3     # a column needs this many icon pixels to count
SEG_GAP = 2        # columns of gap that still belong to one icon


# ---------------------------------------------------------------- features
def frame_features(frame, bg, thresh=THRESH):
    """frame: HxWx3 uint8. Returns dict: top (min row of any icon pixel or None),
    bottom (max row), segs [(x0, x1, top)] left->right."""
    diff = np.abs(frame.astype(np.int16) - bg.astype(np.int16)).max(axis=2)
    mask = diff > thresh
    colcount = mask.sum(axis=0)
    cols = colcount >= MIN_COL_PX
    if not cols.any():
        return {"top": None, "bottom": None, "segs": []}
    rows_any = np.where(mask[:, cols].any(axis=1))[0]
    tops = np.where(mask.any(axis=0), mask.argmax(axis=0), mask.shape[0])
    segs, start, last = [], None, None
    for x in np.where(cols)[0]:
        if start is None:
            start = last = x
        elif x - last <= SEG_GAP + 1:
            last = x
        else:
            segs.append((start, last))
            start = last = x
    if start is not None:
        segs.append((start, last))
    out = []
    for a, b in segs:
        if b - a < 4:
            continue
        out.append((int(a), int(b), int(tops[a:b + 1].min())))
    return {"top": int(rows_any.min()), "bottom": int(rows_any.max()), "segs": out}


def bell(t):
    t = abs(t)
    return 0.0 if t >= 1 else 0.5 * (1 + math.cos(math.pi * t))


def median(v):
    v = sorted(v)
    n = len(v)
    return None if n == 0 else (v[n // 2] if n % 2 else 0.5 * (v[n // 2 - 1] + v[n // 2]))


# ------------------------------------------------------------------- sweep
def analyze_sweep(feats, ratio=1.0):
    """feats: per-frame features (frame order). The first frames must show the
    dock at rest (pointer away)."""
    rest = [f for f in feats[:15] if f["segs"]]
    if not rest:
        raise ValueError("sweep: no dock found in the first frames (check --crop and the wallpaper)")
    n_icons = int(median([len(f["segs"]) for f in rest]))
    rest = [f for f in rest if len(f["segs"]) == n_icons]
    bottom_ref = median([f["bottom"] for f in rest])
    base_h = median([bottom_ref - f["top"] + 1 for f in rest])
    rest_c = [median([0.5 * (f["segs"][i][0] + f["segs"][i][1]) for f in rest]) for i in range(n_icons)]
    pitch = median([rest_c[i + 1] - rest_c[i] for i in range(n_icons - 1)])

    samples, observed_peak = [], 1.0     # samples: (distance_px_in_rest_coords, scale)
    for f in feats:
        if len(f["segs"]) != n_icons:
            continue                      # icons merged/missing in this frame
        scales = [(bottom_ref - s[2] + 1) / base_h for s in f["segs"]]
        observed_peak = max(observed_peak, max(scales))
        w = [max(0.0, s - 1.02) for s in scales]
        if sum(w) < 0.3:
            continue                      # pointer not on the dock
        ptr = sum(wi * c for wi, c in zip(w, rest_c)) / sum(w)
        samples.extend((abs(c - ptr), s) for c, s in zip(rest_c, scales))
    if len(samples) < 20:
        raise ValueError("sweep: pointer never magnified enough icons (record a slower sweep)")

    best = None
    for P in [1 + 0.01 * k for k in range(40, 141)]:
        for R in [pitch * (0.8 + 0.05 * k) for k in range(0, 85)]:
            err = sum((1 + (P - 1) * bell(d / R) - s) ** 2 for d, s in samples)
            if best is None or err < best[0]:
                best = (err, P, R)
    _, P, R = best
    rms = math.sqrt(best[0] / len(samples))
    return {"tileSize": round(base_h / ratio, 2), "peakScale": round(P, 3),
            "radiusTiles": round(R / pitch, 3),
            "_notes": [f"{n_icons} icons, rest pitch {pitch / ratio:.1f}px, observed peak {observed_peak:.2f}x, "
                       f"cosine-fit rms {rms:.3f}, {len(samples)} samples"]}


# ------------------------------------------------------------------ bounce
def analyze_bounce(feats, fps, ratio=1.0):
    rest = [f for f in feats[:int(fps * 0.5) + 1] if f["top"] is not None]
    if not rest:
        raise ValueError("bounce: no dock found at the start")
    top0 = median([f["top"] for f in rest])
    bottom = median([f["bottom"] for f in rest])
    base_h = bottom - top0 + 1
    lift = [(top0 - f["top"]) if f["top"] is not None else 0 for f in feats]
    peak = max(lift)
    if peak < 0.1 * base_h:
        raise ValueError("bounce: no bounce detected (is the icon you launched pinned and not already running?)")
    thr = 0.5 * peak
    peaks, i = [], 0
    while i < len(lift):
        if lift[i] >= thr:
            j = i
            while j < len(lift) and lift[j] >= thr:
                j += 1
            seg = lift[i:j]
            peaks.append((i + seg.index(max(seg))) / fps)
            i = j
        else:
            i += 1
    out = {"bounceHeight": round(peak / base_h, 3)}
    notes = [f"{len(peaks)} bounce peaks"]
    if len(peaks) >= 2:
        d = [b - a for a, b in zip(peaks, peaks[1:])]
        period = median(d)
        out["bouncePeriod"] = round(period, 3)
        a, b = int(peaks[0] * fps - period * fps / 2), int(peaks[-1] * fps + period * fps / 2)
        win = lift[max(0, a):min(len(lift), b)]
        out["bounceRestFraction"] = round(sum(1 for v in win if v < 0.03 * peak) / max(1, len(win)), 3)
    else:
        notes.append("fewer than 2 bounces recorded: period not measured (let the bounce run longer)")
    out["_notes"] = notes
    return out


# ---------------------------------------------------------------- autohide
EASINGS = {
    "quad": lambda u: 2 * u * u if u < 0.5 else 1 - (-2 * u + 2) ** 2 / 2,
    "cubic": lambda u: 4 * u ** 3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2,
    "sine": lambda u: -(math.cos(math.pi * u) - 1) / 2,
}


def _fit_slide(ts, vs, rising):
    """Least-squares fit of start time + duration + easing to a normalised
    0..1 visibility curve. Returns (start, duration, easing, rms)."""
    best = None
    t_lo, t_hi = ts[0], ts[-1]
    # coarse anchor: where the curve first/last leaves its plateau
    for name, fn in EASINGS.items():
        for dur in [0.08 + 0.01 * k for k in range(0, 130)]:
            for start in [t_lo + 0.01 * k for k in range(0, int((t_hi - t_lo) / 0.01))]:
                err = 0.0
                for t, v in zip(ts, vs):
                    u = min(1.0, max(0.0, (t - start) / dur))
                    m = fn(u) if rising else 1 - fn(u)
                    err += (m - v) ** 2
                if best is None or err < best[0]:
                    best = (err, start, dur, name)
    return best[1], best[2], best[3], math.sqrt(best[0] / len(ts))


def analyze_autohide(feats, fps, crop_h, arrival_t=None, leave_t=None):
    vis = [(crop_h - f["top"]) if f["top"] is not None else 0 for f in feats]
    full = max(vis)
    if full < 8:
        raise ValueError("autohide: the dock never appeared")
    norm = [v / full for v in vis]
    t = [i / fps for i in range(len(vis))]
    first = next(i for i, v in enumerate(norm) if v > 0.02)
    full_i = next(i for i, v in enumerate(norm) if v >= 0.98)
    # slide-in window: a little before the first visible frame to the first full frame
    lo = max(0, first - int(0.3 * fps))
    hi = min(len(norm) - 1, full_i + int(0.1 * fps))
    step = max(1, int(fps / 60))
    s_in, d_in, ease, rms = _fit_slide(t[lo:hi + 1:step], norm[lo:hi + 1:step], True)
    out, notes = {"slideDuration": round(d_in, 3)}, [f"slide-in fit: easing {ease}, rms {rms:.3f}"]
    if arrival_t is not None:
        out["revealDelay"] = round(max(0.0, s_in - arrival_t), 3)
    else:
        notes.append("revealDelay needs --arrival-t")
    # slide-out, if the video has one
    out_start = next((i for i in range(full_i, len(norm)) if norm[i] < 0.98), None)
    if out_start is not None and min(norm[out_start:]) < 0.02:
        end = next(i for i in range(out_start, len(norm)) if norm[i] < 0.02)
        lo2, hi2 = max(full_i, out_start - int(0.3 * fps)), min(len(norm) - 1, end + int(0.1 * fps))
        s_out, d_out, ease2, rms2 = _fit_slide(t[lo2:hi2 + 1:step], norm[lo2:hi2 + 1:step], False)
        notes.append(f"slide-out fit: easing {ease2}, rms {rms2:.3f}, duration {d_out:.3f}s")
        if leave_t is not None:
            out["hideDelay"] = round(max(0.0, s_out - leave_t), 3)
        else:
            notes.append("hideDelay needs --leave-t")
    else:
        notes.append("no complete slide-out recorded: hideDelay not measured")
    out["_notes"] = notes
    return out


# ------------------------------------------------------------- video input
def need_tools():
    if np is None:
        sys.exit("numpy is required (not installed here; not installing it for you)")
    for tool in ("ffmpeg", "ffprobe"):
        if not shutil.which(tool):
            sys.exit(f"{tool} not found on PATH")


def probe(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                        "stream=width,height,r_frame_rate", "-of", "json", path],
                       capture_output=True, text=True, check=True)
    s = json.loads(r.stdout)["streams"][0]
    a, b = s["r_frame_rate"].split("/")
    return int(s["width"]), int(s["height"]), float(a) / float(b)


def video_features(path, crop, fps_cap=60.0):
    w, h, fps = probe(path)
    if crop is None:
        crop = (0, int(h * 0.7), w, h - int(h * 0.7))     # bottom 30 %
    x, y, cw, ch = crop
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-vf", f"crop={cw}:{ch}:{x}:{y}", "-f", "rawvideo",
           "-pix_fmt", "rgb24", "-"]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    size = cw * ch * 3
    feats, bg = [], None
    while True:
        buf = p.stdout.read(size)
        if len(buf) < size:
            break
        fr = np.frombuffer(buf, np.uint8).reshape(ch, cw, 3)
        if bg is None:
            bg = np.median(fr[:6].reshape(-1, 3), axis=0).astype(np.uint8)
        feats.append(frame_features(fr, bg))
    p.wait()
    return feats, fps, ch


def parse_crop(s):
    if not s:
        return None
    v = [int(x) for x in s.split(",")]
    if len(v) != 4:
        raise argparse.ArgumentTypeError("--crop X,Y,W,H")
    return tuple(v)


# ---------------------------------------------------------------- selftest
def _synth_icons(n, tile, pitch, ptr, P, R, amount=1.0):
    """Forward model identical to dock/magnify.js: returns [(cx, size)]."""
    rest = [pitch * (i + 0.5) for i in range(n)]
    sc = [1 + (P - 1) * bell((ptr - c) / R) * amount if ptr is not None else 1.0 for c in rest]
    widths = [pitch * s for s in sc]
    left = rest[0] - pitch / 2 - (sum(widths) - n * pitch) / 2
    out, x = [], left
    for s, w in zip(sc, widths):
        out.append((x + w / 2, tile * s))
        x += w
    return out


def _draw(icons, W, H, bottom, bg=(40, 40, 60), fg=(220, 200, 90)):
    fr = np.empty((H, W, 3), np.uint8)
    fr[:] = bg
    for cx, size in icons:
        x0, x1 = int(round(cx - size / 2)), int(round(cx + size / 2))
        y1, y0 = bottom, int(round(bottom - size))
        fr[max(0, y0):y1 + 1, max(0, x0):x1] = fg
    return fr


def selftest():
    need_tools_np = np is not None
    if not need_tools_np:
        print("analyze_capture selftest: SKIPPED (numpy missing)")
        return 0
    ok = True

    def check(name, got, want, tol):
        nonlocal ok
        good = got is not None and abs(got - want) <= tol
        ok &= good
        print(f"  {'PASS' if good else 'FAIL'}  {name}: got {got} want {want} +/- {tol}")

    W, H, bottom = 760, 200, 190
    bg = np.array((40, 40, 60), np.uint8)
    # --- sweep: 10 icons, tile 48 pitch 60, truth P=1.9 R=2.4 pitches, ratio 2 (retina)
    TILE, PITCH, P, R = 48, 60, 1.9, 2.4 * 60
    feats = []
    for _ in range(12):
        feats.append(frame_features(_draw(_synth_icons(10, TILE, PITCH, None, P, R), W, H, bottom), bg))
    for k in range(180):
        ptr = 20 + (PITCH * 10 - 40) * k / 179
        amt = min(1.0, k / 6)
        feats.append(frame_features(_draw(_synth_icons(10, TILE, PITCH, ptr, P, R, amt), W, H, bottom), bg))
    # frames are 1:1 logical->pixel here, so pretend a 1x capture
    r = analyze_sweep(feats, ratio=1.0)
    print("  sweep:", r)
    check("tileSize", r["tileSize"], TILE, 1.5)
    check("peakScale", r["peakScale"], P, 0.12)
    check("radiusTiles", r["radiusTiles"], 2.4, 0.35)

    # --- bounce: period 0.6 s, height 0.5 tile, rest 10 %, 60 fps
    fps = 60.0
    def lift_at(t):
        T, act = 0.6, 0.6 * 0.9
        ph = t % T
        if ph >= act or t < 0.5:
            return 0.0
        u = ph / act
        return 0.5 * (1 - (1 - 2 * u) ** 2 if u < 0.5 else 1 - (2 * u - 1) ** 2)
    feats = []
    for i in range(int(fps * 5)):
        l = lift_at(i / fps) * TILE
        feats.append(frame_features(_draw([(100, TILE)], 200, H, bottom - int(round(l))), bg))
    r = analyze_bounce(feats, fps)
    print("  bounce:", r)
    check("bounceHeight", r["bounceHeight"], 0.5, 0.06)
    check("bouncePeriod", r.get("bouncePeriod"), 0.6, 0.03)
    check("bounceRestFraction", r.get("bounceRestFraction"), 0.1, 0.1)

    # --- autohide: arrival at 1.0 s, delay 0.2, slide 0.45 (cubic in-out), leave 4.0, delay 0.3
    def vis_at(t):
        def ease(u):
            u = min(1, max(0, u))
            return 4 * u ** 3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2
        if t < 4.3:
            return ease((t - 1.2) / 0.45)
        return 1 - ease((t - 4.3) / 0.45)
    feats = []
    for i in range(int(fps * 7)):
        v = vis_at(i / fps)
        h = int(round(v * 70))
        fr = np.empty((90, 100, 3), np.uint8); fr[:] = bg
        if h > 0:
            fr[90 - h:90, 10:90] = (220, 200, 90)
        feats.append(frame_features(fr, bg))
    r = analyze_autohide(feats, fps, 90, arrival_t=1.0, leave_t=4.0)
    print("  autohide:", r)
    check("revealDelay", r.get("revealDelay"), 0.2, 0.06)
    check("hideDelay", r.get("hideDelay"), 0.3, 0.06)
    check("slideDuration", r["slideDuration"], 0.45, 0.12)

    print("analyze_capture selftest:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


# --------------------------------------------------------------------- cli
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sweep")
    ap.add_argument("--bounce")
    ap.add_argument("--autohide")
    ap.add_argument("--crop", type=parse_crop, help="X,Y,W,H of the bottom strip, in video pixels")
    ap.add_argument("--pixel-ratio", type=float, default=2.0, help="video px per logical px (2 on a Retina capture)")
    ap.add_argument("--arrival-t", type=float)
    ap.add_argument("--leave-t", type=float)
    ap.add_argument("--out", default="metrics.json")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        sys.exit(selftest())
    need_tools()
    if not (a.sweep or a.bounce or a.autohide):
        ap.error("give at least one of --sweep/--bounce/--autohide")
    metrics, notes, sources = {}, [], {}
    for kind, path in (("sweep", a.sweep), ("bounce", a.bounce), ("autohide", a.autohide)):
        if not path:
            continue
        feats, fps, ch = video_features(path, a.crop)
        if kind == "sweep":
            r = analyze_sweep(feats, a.pixel_ratio)
        elif kind == "bounce":
            r = analyze_bounce(feats, fps, a.pixel_ratio)
        else:
            r = analyze_autohide(feats, fps, ch, a.arrival_t, a.leave_t)
        notes += [f"{kind}: {n}" for n in r.pop("_notes", [])]
        metrics.update(r)
        sources[kind] = os.path.basename(path)
    with open(a.out, "w") as f:
        json.dump({"source": sources, "metrics": metrics, "notes": notes}, f, indent=2)
    print(json.dumps({"metrics": metrics, "notes": notes}, indent=2))
    print("wrote", a.out)


if __name__ == "__main__":
    main()
