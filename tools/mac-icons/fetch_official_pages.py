#!/usr/bin/env python3
"""Scrape the "Official icons" (verified) section of macosicons.com app pages -- the API has no such flag.
For each app: map to the site slug, fetch /apps/<slug>, parse the Official icons entries (macOS preferred over iOS,
"Classic" only if nothing else), then fetch /icon/<id> to find the .icns (1024px) and fall back to the low-res PNG.
The chosen image is downloaded through lib.safe_fetch and its sha256 pinned in the candidate file, which
lib.candidates_for ranks FIRST (source "macosicons-official"). build_theme.py --freeze records it in picks.json.
>=2 s between network requests; HTML cached in ~/.cache/qml-rice/mac-icons/pages/.
Usage: fetch_official_pages.py --only ID ... [--refresh]   (ID = desktop id with or without .desktop)"""
import argparse, html, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

BASE = "https://macosicons.com"
PAGES = os.path.join(lib.CACHE, "pages")
# desktop-id stem -> site slug(s) to try first; the accepted app names (page title) default to the app's own name
SLUG_OVERRIDES = {
    "code-oss": ["visual-studio-code"], "zen": ["zen-browser"], "brave-browser": ["brave-browser", "brave"],
    "org.telegram.desktop": ["telegram"], "com.anthropic.Claude": ["claude"], "vivaldi-stable": ["vivaldi"],
    "OBS Studio": ["obs-studio", "obs"], "codium": ["vscodium"], "figma-linux": ["figma"],
    "dev.zed.Zed": ["zed"], "org.kde.dolphin": ["dolphin"], "nvim": ["neovim"], "btop": ["btop"],
    "thunar": ["thunar"], "libreoffice-writer": ["libreoffice-writer"],
    "libreoffice-calc": ["libreoffice-calc"], "libreoffice-impress": ["libreoffice-impress"],
    "chatgpt": ["chatgpt"], "t3code": ["t3-code", "t3code"], "vesktop": ["vesktop"], "localsend": ["localsend"],
}
EXTRA_NAMES = {"code-oss": ["visual studio code"], "dev.zed.Zed": ["zed"], "org.telegram.desktop": ["telegram"],
               "nvim": ["neovim"], "codium": ["vscodium"]}
_last = [0.0]

def fetch(url, hosts, cache=None, max_bytes=8_000_000):
    """Rate-limited safe_fetch; HTML cached (404s cached as empty marker)."""
    if cache and os.path.exists(cache):
        return open(cache, "rb").read() or None
    wait = 2.1 - (time.time() - _last[0])
    if wait > 0:
        time.sleep(wait)
    _last[0] = time.time()
    try:
        data = lib.safe_fetch(url, hosts, max_bytes)
    except lib.FetchError as e:
        if "HTTP 404" in str(e):
            if cache:
                os.makedirs(os.path.dirname(cache), exist_ok=True); open(cache, "wb").close()
            return None
        raise
    if cache:
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        open(cache, "wb").write(data)
    return data

def slugs_for(app):
    stem = app["id"][:-8] if app["id"].endswith(".desktop") else app["id"]
    out = list(SLUG_OVERRIDES.get(stem, []))
    nm = lib.app_name_clean(app).lower()
    for s in (re.sub(r"[^a-z0-9]+", "-", nm).strip("-"), re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")):
        if s and s not in out:
            out.append(s)
    return stem, out

def title_ok(page, app, stem):
    m = re.search(r"<title>([^<]*)", page)
    if not m:
        return False
    t = lib.norm(html.unescape(m.group(1)).split(" macOS icons")[0].split(" icons")[0])
    names = [lib.norm(lib.app_name_clean(app))] + [lib.norm(x) for x in EXTRA_NAMES.get(stem, [])]
    return bool(t) and any(n and (n in t or t in n) for n in names)

def parse_official(page):
    i = page.find('data-testid="official-icons"')
    if i < 0:
        return []
    blk = page[i:i + 8000]
    j = blk.find("<!--]--></div></div>")
    blk = blk[:j] if j > 0 else blk
    out = []
    for m in re.finditer(r'<a href="(/icon/([A-Za-z0-9_-]+))"[^>]*title="([^"]*)"[^>]*>.*?<img src="([^"]+)"', blk, re.S):
        title = html.unescape(m.group(3))
        out.append({"path": m.group(1), "slug": m.group(2), "id": m.group(2).rsplit("-", 1)[-1], "title": title,
                    "classic": "Classic" in title, "ios": "iOS" in title, "lowres": html.unescape(m.group(4))})
    out.sort(key=lambda e: (e["classic"], e["ios"]))      # macOS before iOS, Classic last
    return out

def best_image(entry, stem):
    data = fetch(BASE + entry["path"], lib.ALLOWED_HOSTS, os.path.join(PAGES, "icon-" + entry["slug"] + ".html"))
    if data:
        page = data.decode("utf-8", "replace")
        m = re.search(r'https://s3-new\.macosicons\.com/[^"\'\s\\<>]*_%s[^"\'\s\\<>]*\.icns' % re.escape(entry["id"]), page)
        if m:
            return html.unescape(m.group(0)), "icns"
    return entry["lowres"], "lowres"

def resolution(path):
    from PIL import Image
    p = lib.to_png(path)
    with Image.open(p) as im:
        return im.width

def process(app, refresh):
    f = os.path.join(lib.CAND_DIR, lib.app_slug(app["id"]) + ".official-page.json")
    if os.path.exists(f) and not refresh:
        return lib.load_json(f, {})
    stem, slugs = slugs_for(app)
    res = {"fetched": int(time.time()), "candidates": []}
    for s in slugs:
        data = fetch("%s/apps/%s" % (BASE, s), lib.ALLOWED_HOSTS, os.path.join(PAGES, "app-" + s + ".html"))
        if not data:
            continue
        page = data.decode("utf-8", "replace")
        if not title_ok(page, app, stem):
            print("  slug %r title mismatch for %s" % (s, app["id"])); continue
        res["slug"] = s
        ents = parse_official(page)
        if not ents:
            res["note"] = "no Official icons section"; break
        e = ents[0]
        url, kind = best_image(e, stem)
        dest = lib.url_cache_path(url)
        lib.download(url, dest, hosts=lib.ALLOWED_HOSTS)
        sha = lib._sha(open(dest, "rb").read())
        px = resolution(dest)
        res["candidates"].append({"url": url, "sha256": sha, "appName": e["title"], "kind": kind, "resolution": px,
                                  "iconPage": BASE + e["path"], "variant": "iOS" if e["ios"] else "macOS"})
        break
    os.makedirs(lib.CAND_DIR, exist_ok=True)
    lib.save_json(f, res)
    return res

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="+", required=True)
    ap.add_argument("--refresh", action="store_true")
    a = ap.parse_args()
    allapps = lib.load_apps()
    byid = {x["id"]: x for x in allapps}
    for w in a.only:
        app = byid.get(w) or byid.get(w + ".desktop")
        if not app:
            print("%-28s not in apps.json" % w); continue
        try:
            r = process(app, a.refresh)
        except Exception as e:
            print("%-28s ERROR %s" % (w, e)); continue
        c = (r.get("candidates") or [None])[0]
        print("%-28s %s" % (w, "%s %s %dpx (%s) %s" % (c["variant"], c["kind"], c["resolution"], r.get("slug"), c["appName"])
                            if c else "no official icon (%s)" % r.get("note", "no matching page")))
    return 0

sys.exit(main())
