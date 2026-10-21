#!/usr/bin/env python3
"""Validate a built theme. Usage: check_theme.py THEME_DIR [--strict]"""
import configparser, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib
from PIL import Image

def main():
    theme = sys.argv[1]; strict = "--strict" in sys.argv
    errs, warns = [], []
    cp = configparser.RawConfigParser(strict=False); cp.optionxform = str
    try:
        cp.read(os.path.join(theme, "index.theme"), encoding="utf-8")
        assert cp.get("Icon Theme", "Name") == "qml-rice-mac"
        assert "Papirus-Dark" in cp.get("Icon Theme", "Inherits")
        dirs = [d for d in cp.get("Icon Theme", "Directories").split(",") if d]
    except Exception as e:
        print("FAIL index.theme: %s" % e); return 1
    for d in dirs:
        if not os.path.isdir(os.path.join(theme, d)): errs.append("missing dir " + d); continue
        if not cp.has_section(d): errs.append("no section for " + d); continue
        size, scale = int(cp.get(d, "Size")), int(cp.get(d, "Scale", fallback="1"))
        for f in os.listdir(os.path.join(theme, d)):
            p = os.path.join(theme, d, f)
            if not os.path.exists(p): errs.append("dangling " + p); continue
            if os.path.islink(p): continue
            try:
                if Image.open(p).size != (size * scale,) * 2: errs.append("wrong px size " + p)
            except Exception as e: errs.append("bad png %s: %s" % (p, e))
    apps = lib.load_json(lib.APPS_JSON, [])
    if not apps: errs.append("apps.json empty/missing")
    for a in apps:
        names = lib.icon_names_for(a)
        ok = any(os.path.exists(os.path.join(theme, "48x48/apps", n + ".png")) or lib.find_icon(n, ("Papirus-Dark", "Adwaita")) for n in names)
        if not ok and (a.get("icon") or "").startswith("/") and os.path.exists(a["icon"]): ok = True
        if not ok: warns.append("%s (Icon=%s) resolves nowhere" % (a["id"], a.get("icon")))
    for w in warns: print("WARN", w)
    if strict: errs += warns
    for e in errs: print("FAIL", e)
    print("%s: %d dirs, %d apps, %d errors, %d warnings" % ("FAIL" if errs else "OK", len(dirs), len(apps), len(errs), len(warns)))
    return 1 if errs else 0

sys.exit(main())
