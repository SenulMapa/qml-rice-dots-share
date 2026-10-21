#!/usr/bin/env python3
"""Fetch + verify the curated official vendor icons (official_sources.json) into the cache.
Usage: fetch_official.py [--record]   --record pins sha256 for entries that have none (first verified fetch).
Entries whose fetched bytes do not match a recorded sha256 are rejected (vendor changed the file: review, then re-pin)."""
import argparse, hashlib, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--record", action="store_true"); a = ap.parse_args()
    man = lib.load_json(lib.OFFICIAL, {"entries": []})
    changed = False
    for e in man["entries"]:
        try:
            dest = lib.url_cache_path(e["url"])
            lib.download(e["url"], dest, lib.OFFICIAL_HOSTS, e.get("sha256"))
            h = hashlib.sha256(open(dest, "rb").read()).hexdigest()
            png = lib.to_png(dest)   # raises unless it is a real icns/png/svg
            if e.get("sha256") and e["sha256"] != h:
                print("REJECT %-14s sha mismatch (pinned %s.. got %s..)" % (e["id"], e["sha256"][:8], h[:8])); continue
            if not e.get("sha256") and a.record:
                e["sha256"] = h; changed = True
            from PIL import Image
            print("ok     %-14s %s %s" % (e["id"], Image.open(png).size, h[:12]))
        except Exception as ex:
            print("FAIL   %-14s %s" % (e["id"], ex))
    if changed:
        lib.save_json(lib.OFFICIAL, man)
main()
