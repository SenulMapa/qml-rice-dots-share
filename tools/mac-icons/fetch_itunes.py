#!/usr/bin/env python3
"""Mac App Store artwork via the public, keyless iTunes Search API (cached, rate-limited ~18 req/min).
Strict matching: a result is accepted only when trackName equals the app name (or is "<name> for ..."/"<name> ...")
AND the bundleId or sellerName contains the app name token, or an explicit override pins the bundleId.
Generic one-word names (code, micro, ...) never match on name alone.
Usage: fetch_itunes.py [--only ID ...] [--refresh] [--dry]"""
import argparse, json, os, sys, time, urllib.parse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

OVERRIDES = {  # desktop id -> exact Mac bundleId that IS this app (vendor ships on the MAS under another name)
    "org.telegram.desktop.desktop": "ru.keepcoder.Telegram",
    "todoist.desktop": "com.todoist.mac.Todoist",
    "slack.desktop": "com.tinyspeck.slackmacgap",
    "equibop.desktop": None, "vesktop.desktop": None,
}
GENERIC = {"code", "micro", "foot", "rofi", "vim", "nvim", "htop", "btop", "mpv", "yazi", "timeset", "assistant", "designer", "linguist",
           "terminal", "paper", "files", "settings", "system", "monitor", "keyboard", "network", "about", "calculator"}

def query(term):
    u = "https://itunes.apple.com/search?" + urllib.parse.urlencode({"term": term, "entity": "macSoftware", "limit": 5})
    return json.loads(lib.safe_fetch(u, lib.ITUNES_API_HOSTS, 3_000_000)).get("results", [])

def match(app, results):
    name = lib.norm(lib.app_name_clean(app))
    forced = OVERRIDES.get(app["id"], "")
    for r in results:
        if forced and r.get("bundleId") == forced:
            return r
    if app["id"].startswith(("org.gnome.", "org.kde.", "org.xfce.", "org.freedesktop.")):
        return None            # Linux-native desktop apps: a same-named MAS app is a different product
    if forced is None or not name or name in GENERIC or len(name) < 3:
        return None
    ids = {lib.norm(x) for x in lib.icon_names_for(app)} | {name}
    raw = lib.app_name_clean(app).lower()
    for r in results:
        tn = r["trackName"].lower()
        # exact name, or "<name> for Desktop/Mac" / "<name>: subtitle" / "<name> - subtitle" only
        if not (lib.norm(tn) == name or any(tn.startswith(raw + sep) for sep in (" for ", ": ", " - ", " \u2013 "))):
            continue
        bid = r.get("bundleId", "")
        if lib.norm(bid.split(".")[-1]) in ids or name in lib.norm(bid):   # bundleId must mention the app
            return r
    return None

def big(url):
    # .../512x512bb.png -> 1024x1024bb.png (mzstatic serves arbitrary sizes)
    import re
    return re.sub(r"/\d+x\d+bb(\.\w+)$", r"/1024x1024bb\1", url)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*"); ap.add_argument("--refresh", action="store_true"); ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    os.makedirs(lib.CAND_DIR, exist_ok=True)
    for app in lib.load_apps():
        if a.only and app["id"] not in a.only:
            continue
        f = os.path.join(lib.CAND_DIR, lib.app_slug(app["id"]) + ".itunes.json")
        if os.path.exists(f) and not a.refresh:
            continue
        term = lib.app_name_clean(app) or app["id"]
        try:
            res = query(term)
        except Exception as e:
            print("error for %r: %s (stopping; rerun later)" % (term, e)); break
        r = match(app, res)
        cands = []
        if r and r.get("artworkUrl512"):
            u = big(r["artworkUrl512"])
            if lib.host_ok(u, lib.ITUNES_HOSTS):
                cands.append({"url": u, "appName": r["trackName"], "bundleId": r.get("bundleId"), "seller": r.get("sellerName")})
        print("%-36s -> %s" % (term, (r or {}).get("trackName", "-- no match (%s)" % ", ".join(x["trackName"] for x in res[:2]))))
        if not a.dry:
            lib.save_json(f, {"query": term, "fetched": int(time.time()), "candidates": cands,
                         "raw": [{k: x.get(k) for k in ("trackName", "bundleId", "sellerName", "artworkUrl512")} for x in res]})
        time.sleep(3.4)
main()
