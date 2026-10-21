#!/usr/bin/env python3
"""Query the macOSicons search API for candidate icons per app (cached).

Needs an API key (free tier = 50 requests/month!): env MACOSICONS_API_KEY or
~/.config/qml-rice/macosicons.key. Without a key this exits cleanly and the manual
fallback applies: put {"source":"url","url":"https://..."} entries into picks.json.
Usage: fetch_candidates.py [-n 6] [--max-requests 40] [--only ID ...] [--refresh]
"""
import argparse, json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

def api_key():
    k = os.environ.get("MACOSICONS_API_KEY", "").strip()
    if not k:
        try:
            k = open(os.path.join(lib.HOME, ".config/qml-rice/macosicons.key")).read().strip()
        except OSError:
            pass
    return k

def search(query, key):
    return json.loads(lib.safe_fetch(lib.API_BASE + "/search", lib.ALLOWED_HOSTS, 5_000_000,
        data=json.dumps({"query": query}).encode(), method="POST",
        headers={"Content-Type": "application/json", "x-api-key": key}))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=int, default=6)
    ap.add_argument("--max-requests", type=int, default=40)
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--refresh", action="store_true")
    a = ap.parse_args()
    key = api_key()
    if not key:
        print("No macOSicons API key (MACOSICONS_API_KEY or ~/.config/qml-rice/macosicons.key).\n"
              "Get a free one at https://macosicons.com/developers. Fallback: add URL picks to picks.json.")
        return 0
    used = 0
    os.makedirs(lib.CAND_DIR, exist_ok=True)
    for app in lib.load_apps():
        if a.only and app["id"] not in a.only:
            continue
        f = os.path.join(lib.CAND_DIR, lib.app_slug(app["id"]) + ".json")
        if os.path.exists(f) and not a.refresh:
            continue
        if used >= a.max_requests:
            print("request budget reached (%d); rerun later to continue" % used)
            break
        query = app["name"] or app["id"]
        try:
            res = search(query, key); used += 1
        except lib.FetchError as e:
            if "HTTP 4" in str(e) or "HTTP 5" in str(e):
                print("%s for %r -- stopping" % (e, query)); break
            print("error for %r: %s" % (query, e)); continue
        except Exception as e:
            print("error for %r: %s" % (query, e)); continue
        cands = []
        for h in res.get("hits", [])[:a.n]:
            u = h.get("lowResPngUrl") or h.get("iOSUrl")
            if u and lib.host_ok(u):
                cands.append({"url": u, "appName": h.get("appName"), "credit": h.get("credit"),
                              "creditUrl": h.get("creditUrl"), "icnsUrl": h.get("icnsUrl")})
        lib.save_json(f, {"query": query, "fetched": int(time.time()), "candidates": cands})
        print("%-40s %d candidates" % (query, len(cands)))
        time.sleep(0.3)
    print("API requests used: %d" % used)
    return 0

sys.exit(main())
