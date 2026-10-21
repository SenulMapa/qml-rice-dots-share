#!/usr/bin/env python3
"""
Compute focal points for wallpaper images using saliency + face detection.

Scans exactly the three wallpaper library directories under
~/.local/share/wallpapers/ (personal-library, extra-wallpapers,
impasto-creations -- each a symlink to a real Pictures/* directory),
following symlinks, for jpg/jpeg/png/webp images. Results are cached to
~/.local/state/quickshell/focal-points.json.

--------------------------------------------------------------------------
CACHE KEY CONTRACT (must match wallpaper/DitherWallpaper.qml exactly):

    key = "<path>|<mtime>"

`<path>` is NOT necessarily resolved -- it's whatever path the caller asks
about. At *scan* time we resolve the symlinked library dirs down to their
real target (Path.resolve()), because that's what actually lives on disk.
Critically, the live QML/WallpaperService code path never even sees the
~/.local/share/wallpapers/<symlink>/... form: Config.wallpaper.directories
(core/Config.qml) points wallpaperctl.sh's `list`/`candidate` scan directly
at `~/Pictures/Wallpapers` and `~/Pictures/wallpapers` (the real dirs the
personal-library/extra-wallpapers symlinks target), so
WallpaperService.currentStill is already the resolved real path. As long as
this script keys on the resolved real path too, the two sides agree without
either side needing to resolve anything at lookup time. `<mtime>` is
`int(os.stat(path).st_mtime)` -- the integer seconds mtime of the resolved
file, read with plain os.stat() (which follows symlinks), matching the
`stat -c %Y <path>` the QML side shells out to.

(impasto-creations -> ~/Pictures/Impasto is scanned and cached here too,
for completeness/future use, even though it isn't currently one of
Config.wallpaper.directories -- harmless extra cache entries.)
--------------------------------------------------------------------------

Usage:
    focal-points.py                 # Scan all three library directories
    focal-points.py /path/to/image  # Compute for a single image (incremental)

Preview crops (9:16 portrait) are written to /tmp/focal-preview/ for
verification, plus a combined contact sheet at /tmp/focal-preview/sheet.jpg
for a sample of images (--contact-sheet).
"""

import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Tuple
import time

try:
    import cv2
    import numpy as np
    HAS_OPENCV = True
except ImportError:
    HAS_OPENCV = False

HAS_SALIENCY = HAS_OPENCV and hasattr(cv2, "saliency")

# Bundled with this venv's opencv-contrib-python wheel there is no cv2/data
# haarcascades dir (some wheel builds omit it) -- fall back to the system
# opencv5 package's copy, which this Arch box has installed.
_CASCADE_CANDIDATES = []
if HAS_OPENCV:
    _CASCADE_CANDIDATES = [
        os.path.join(getattr(cv2.data, "haarcascades", ""), "haarcascade_frontalface_default.xml") if hasattr(cv2, "data") else "",
        "/usr/share/opencv5/haarcascades/haarcascade_frontalface_default.xml",
        "/usr/share/opencv4/haarcascades/haarcascade_frontalface_default.xml",
    ]

DOWNSCALE_TARGET = 512  # long-edge px for saliency/face work

LIBRARY_DIRS = [
    "personal-library",
    "extra-wallpapers",
    "impasto-creations",
]
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}


def _load_face_cascade():
    if not HAS_OPENCV:
        return None
    for path in _CASCADE_CANDIDATES:
        if path and os.path.exists(path):
            cascade = cv2.CascadeClassifier(path)
            if not cascade.empty():
                return cascade
    return None


_FACE_CASCADE = _load_face_cascade() if HAS_OPENCV else None


def _downscale(img):
    h, w = img.shape[:2]
    scale = DOWNSCALE_TARGET / float(max(h, w))
    if scale >= 1.0:
        return img, 1.0
    small = cv2.resize(img, (max(1, int(w * scale)), max(1, int(h * scale))),
                        interpolation=cv2.INTER_AREA)
    return small, scale


def _detect_faces(gray_small):
    """Return list of (cx, cy, weight) in the small image's pixel space."""
    if _FACE_CASCADE is None:
        return []
    faces = _FACE_CASCADE.detectMultiScale(
        gray_small, scaleFactor=1.1, minNeighbors=5,
        minSize=(max(20, gray_small.shape[1] // 20),) * 2)
    out = []
    for (x, y, w, h) in faces:
        out.append((x + w / 2.0, y + h / 2.0, float(w * h)))
    return out


def _saliency_centroid(bgr_small):
    """
    Weighted centroid of the TOP-saliency region (not the global mean, which
    regresses to center for symmetric compositions). Prefers fine-grained
    saliency (higher quality, more expensive) and falls back to spectral
    residual; both are cheap at 512px.
    """
    sal_map = None
    if HAS_SALIENCY:
        for ctor_name in ("StaticSaliencyFineGrained_create",
                          "StaticSaliencySpectralResidual_create"):
            ctor = getattr(cv2.saliency, ctor_name, None)
            if ctor is None:
                continue
            try:
                success, sal = ctor().computeSaliency(bgr_small)
                if success:
                    sal_map = sal.astype(np.float32)
                    break
            except Exception:
                continue

    if sal_map is None:
        # Fallback: blurred Canny edge energy as a crude saliency proxy.
        gray = cv2.cvtColor(bgr_small, cv2.COLOR_BGR2GRAY)
        edges = cv2.Canny(gray, 50, 150).astype(np.float32) / 255.0
        sal_map = cv2.GaussianBlur(edges, (31, 31), 0)

    if sal_map.max() <= sal_map.min():
        h, w = sal_map.shape[:2]
        return (w / 2.0, h / 2.0)

    norm = (sal_map - sal_map.min()) / (sal_map.max() - sal_map.min())

    # Weighted centroid of the top-saliency region only: threshold at the
    # 80th percentile so the centroid tracks the salient subject instead of
    # being pulled toward the mean of the whole (mostly background) frame.
    threshold = np.percentile(norm, 80)
    mask = norm >= threshold
    if not mask.any():
        h, w = norm.shape[:2]
        return (w / 2.0, h / 2.0)

    ys, xs = np.where(mask)
    weights = norm[ys, xs]
    cx = float((xs * weights).sum() / weights.sum())
    cy = float((ys * weights).sum() / weights.sum())
    return (cx, cy)


def compute_focal_point(image_path: str) -> Tuple[float, float, int, int]:
    """
    Compute focal point for an image as (fx, fy) in [0, 1], plus the
    image's natural (width, height) in pixels.

    Faces (when detected) dominate the result -- a strongly weighted blend
    toward the face centroid -- since a face is almost always the intended
    subject. Otherwise falls back to the saliency centroid.

    The natural size is read here (from the same cv2.imread() decode this
    function already has to do for saliency/face analysis -- no extra
    decode cost) and cached alongside fx/fy specifically so the QML side
    never has to derive crop dimensions from its own loaded Image's
    implicitWidth/implicitHeight. Those become the CLIPPED size once
    sourceClipRect is set, so computing a crop from them creates a
    feedback loop that shrinks the clip every recompute. Caching the true
    natural size here breaks that loop at the source.
    """
    if not HAS_OPENCV:
        raise RuntimeError("OpenCV not available; install: pip install opencv-contrib-python")

    img = cv2.imread(image_path)
    if img is None:
        raise ValueError(f"Could not read image: {image_path}")
    if img.ndim == 2:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)

    natural_h, natural_w = img.shape[:2]

    small, scale = _downscale(img)
    h, w = small.shape[:2]

    gray_small = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
    faces = _detect_faces(gray_small)
    sx, sy = _saliency_centroid(small)

    if faces:
        total_w = sum(fw for _, _, fw in faces)
        fcx = sum(fx * fw for fx, fy, fw in faces) / total_w
        fcy = sum(fy * fw for fx, fy, fw in faces) / total_w
        # Faces dominate strongly (0.85) -- saliency only nudges the crop.
        cx = 0.85 * fcx + 0.15 * sx
        cy = 0.85 * fcy + 0.15 * sy
    else:
        cx, cy = sx, sy

    fx = max(0.0, min(1.0, cx / w))
    fy = max(0.0, min(1.0, cy / h))
    return (fx, fy, natural_w, natural_h)


def get_cache_key(resolved_path: str) -> str:
    """
    Cache key: <resolved real path>|<int mtime>. See module docstring for
    the full contract this must satisfy on both the python and QML sides.
    `resolved_path` must already be a real (non-symlink) path -- callers
    are responsible for resolving symlinks before calling this.
    """
    try:
        stat = os.stat(resolved_path)
        mtime = int(stat.st_mtime)
        return f"{resolved_path}|{mtime}"
    except OSError:
        return ""


def load_cache() -> Dict[str, Dict]:
    cache_file = Path.home() / ".local/state/quickshell/focal-points.json"
    if cache_file.exists():
        try:
            with open(cache_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            print(f"Warning: Could not load cache: {e}", file=sys.stderr)
    return {}


def save_cache(cache: Dict[str, Dict]) -> None:
    cache_dir = Path.home() / ".local/state/quickshell"
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_file = cache_dir / "focal-points.json"
    try:
        with open(cache_file, 'w') as f:
            json.dump(cache, f, indent=2)
    except Exception as e:
        print(f"Error: Could not save cache: {e}", file=sys.stderr)


def scan_wallpaper_directories() -> List[Path]:
    """
    Scan exactly ~/.local/share/wallpapers/{personal-library,extra-wallpapers,
    impasto-creations}, following symlinks, for jpg/jpeg/png/webp images.
    Returns a list of RESOLVED (real, symlink-free) absolute paths, deduped.
    """
    hub = Path.home() / ".local/share/wallpapers"
    seen = set()
    images: List[Path] = []

    for name in LIBRARY_DIRS:
        base = hub / name
        if not base.exists():
            print(f"Warning: library dir missing: {base}", file=sys.stderr)
            continue
        real_base = base.resolve()
        for dirpath, _dirnames, filenames in os.walk(real_base, followlinks=True):
            for fname in filenames:
                if Path(fname).suffix.lower() in IMAGE_EXTENSIONS:
                    p = Path(dirpath) / fname
                    try:
                        resolved = p.resolve()
                    except (OSError, RuntimeError):
                        continue
                    if resolved.exists() and resolved not in seen:
                        seen.add(resolved)
                        images.append(resolved)

    return images


def create_preview_crop(image_path: str, fx: float, fy: float, out_dir: Path = None) -> Path:
    """
    Create a 9:16 portrait preview crop centered on focal point.
    Writes to <out_dir>/<basename>-crop.jpg (default /tmp/focal-preview/).
    Returns the written path, or None.
    """
    if not HAS_OPENCV:
        return None

    out_dir = out_dir or Path("/tmp/focal-preview")
    try:
        img = cv2.imread(image_path)
        if img is None:
            return None

        h, w = img.shape[:2]
        target_aspect = 9.0 / 16.0

        if w / h > target_aspect:
            crop_w = int(h * target_aspect)
            crop_h = h
        else:
            crop_h = int(w / target_aspect)
            crop_w = w

        center_x = int(fx * w)
        center_y = int(fy * h)

        x_start = max(0, center_x - crop_w // 2)
        y_start = max(0, center_y - crop_h // 2)
        x_end = min(w, x_start + crop_w)
        y_end = min(h, y_start + crop_h)

        if x_end - x_start < crop_w:
            if x_end == w:
                x_start = max(0, w - crop_w)
            else:
                x_end = min(w, x_start + crop_w)

        if y_end - y_start < crop_h:
            if y_end == h:
                y_start = max(0, h - crop_h)
            else:
                y_end = min(h, y_start + crop_h)

        crop = img[y_start:y_end, x_start:x_end]

        out_dir.mkdir(parents=True, exist_ok=True)
        basename = Path(image_path).stem
        preview_path = out_dir / f"{basename}-crop.jpg"
        cv2.imwrite(str(preview_path), crop)
        return preview_path
    except Exception as e:
        print(f"Warning: Could not create preview for {image_path}: {e}", file=sys.stderr)
        return None


def process_single_image(image_path: str) -> None:
    """
    Process a single image and update the cache. `image_path` is resolved
    to its real path first so the cache key matches scan-time keys.
    """
    resolved = str(Path(image_path).resolve())
    if not os.path.isfile(resolved):
        print(f"Error: Not a file: {resolved}", file=sys.stderr)
        return

    print(f"Processing: {resolved}")

    cache = load_cache()
    cache_key = get_cache_key(resolved)

    if not cache_key:
        print(f"Error: Could not stat {resolved}", file=sys.stderr)
        return

    if cache_key in cache:
        print(f"  Already cached: {cache[cache_key]}")
        return

    try:
        fx, fy, w, h = compute_focal_point(resolved)
        cache[cache_key] = {"fx": round(fx, 4), "fy": round(fy, 4), "w": w, "h": h}
        save_cache(cache)
        print(f"  Focal point: ({fx:.4f}, {fy:.4f}), size: {w}x{h}")
        create_preview_crop(resolved, fx, fy)
    except Exception as e:
        print(f"Error: Failed to process {resolved}: {e}", file=sys.stderr)


def main():
    if not HAS_OPENCV:
        print("Error: opencv not installed.", file=sys.stderr)
        print("  pip install opencv-contrib-python", file=sys.stderr)
        sys.exit(1)

    method = []
    if HAS_SALIENCY:
        method.append("saliency")
    else:
        method.append("edge-fallback")
    if _FACE_CASCADE is not None:
        method.append("face-detect")
    print(f"Using: {' + '.join(method)}")

    if len(sys.argv) > 1:
        process_single_image(sys.argv[1])
        return

    print("Scanning wallpaper directories...")
    images = scan_wallpaper_directories()
    print(f"Found {len(images)} images")

    if not images:
        print("No images found")
        return

    cache = load_cache()
    start_time = time.time()
    processed = 0
    skipped = 0

    for resolved_path in images:
        cache_key = get_cache_key(str(resolved_path))
        if not cache_key:
            print(f"Warning: Could not stat {resolved_path}")
            continue

        if cache_key in cache:
            skipped += 1
            continue

        try:
            print(f"Processing: {resolved_path}")
            fx, fy, w, h = compute_focal_point(str(resolved_path))
            cache[cache_key] = {"fx": round(fx, 4), "fy": round(fy, 4), "w": w, "h": h}
            print(f"  Focal point: ({fx:.4f}, {fy:.4f}), size: {w}x{h}")
            processed += 1
        except Exception as e:
            print(f"Warning: Failed to process {resolved_path}: {e}", file=sys.stderr)

    save_cache(cache)
    elapsed = time.time() - start_time

    print(f"\nResults:")
    print(f"  Processed: {processed} new images")
    print(f"  Skipped (cached): {skipped} images")
    print(f"  Time: {elapsed:.1f}s")
    print(f"  Cache: ~/.local/state/quickshell/focal-points.json")


if __name__ == "__main__":
    main()
