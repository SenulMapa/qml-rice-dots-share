#!/usr/bin/env python3
"""List apps to cover -> $CACHE/apps.json. Read-only on the system (hyprctl clients -j only)."""
import configparser, glob, json, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lib

def parse(path):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
    except (configparser.Error, UnicodeDecodeError):
        return None
    if not cp.has_section("Desktop Entry"):
        return None
    g = lambda k, d="": cp.get("Desktop Entry", k, fallback=d).strip()
    if g("Type") != "Application" or g("NoDisplay").lower() == "true" or g("Hidden").lower() == "true":
        return None
    return {"id": os.path.basename(path), "name": g("Name"), "icon": g("Icon"),
            "wmclass": g("StartupWMClass"), "path": path}

def clients():
    try:
        out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=5).stdout
        return sorted({c.get("class", "") for c in json.loads(out) if c.get("class")})
    except Exception:
        return []

def main(out=None):
    apps = {}
    for d in lib.app_dirs():                      # earlier dirs win
        for p in sorted(glob.glob(os.path.join(d, "**", "*.desktop"), recursive=True)):
            a = parse(p)
            if a and a["id"] not in apps:
                apps[a["id"]] = a
    known = {lib.norm(a["wmclass"]) for a in apps.values() if a["wmclass"]}
    known |= {lib.norm(a["id"][:-8]) for a in apps.values()}
    known |= {lib.norm(a["icon"]) for a in apps.values() if a["icon"]}
    for cls in clients():
        if lib.norm(cls) not in known:
            apps["class:" + cls] = {"id": "class:" + cls, "name": cls, "icon": cls.lower(),
                                    "wmclass": cls, "path": ""}
    res = sorted(apps.values(), key=lambda a: a["id"].lower())
    lib.save_json(out or lib.APPS_JSON, res)
    print("%d apps -> %s" % (len(res), out or lib.APPS_JSON))

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
