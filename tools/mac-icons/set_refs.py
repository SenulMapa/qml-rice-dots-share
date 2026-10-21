#!/usr/bin/env python3
"""Targeted icon-theme reference edits (line-based, preserves everything else).
Usage: set_refs.py THEME   -> edits gtk-3.0/gtk-4.0 settings.ini, kdeglobals [Icons], qt6ct.conf [Appearance]
Paths are relative to $HOME. Prints the files it touched."""
import os, re, sys
H = os.path.expanduser("~")

def set_key(path, section, key, value, create=True):
    text = open(path).read() if os.path.exists(path) else ""
    lines = text.split("\n")
    sec_re = re.compile(r"^\[(.+)\]\s*$")
    start = end = None
    for i, l in enumerate(lines):
        m = sec_re.match(l)
        if m:
            if m.group(1) == section: start = i; end = len(lines)
            elif start is not None and end == len(lines): end = i
    if start is None:
        if not create: return False
        if text and not text.endswith("\n"): lines.append("")
        while lines and lines[-1] == "": lines.pop()
        lines += (["" ] if lines else []) + ["[%s]" % section, "%s=%s" % (key, value), ""]
    else:
        for i in range(start + 1, end):
            if re.match(r"^\s*%s\s*=" % re.escape(key), lines[i]):
                if lines[i] == "%s=%s" % (key, value): return False
                lines[i] = "%s=%s" % (key, value); break
        else:
            j = end
            while j > start + 1 and lines[j - 1].strip() == "": j -= 1
            lines.insert(j, "%s=%s" % (key, value))
    new = "\n".join(lines)
    if new == text: return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(new)
    return True

def main():
    theme = sys.argv[1]
    cfg = os.path.join(H, ".config")
    for p in (os.path.join(cfg, "gtk-3.0/settings.ini"), os.path.join(cfg, "gtk-4.0/settings.ini")):
        if set_key(p, "Settings", "gtk-icon-theme-name", theme): print("edited", p)
    if set_key(os.path.join(cfg, "kdeglobals"), "Icons", "Theme", theme): print("edited kdeglobals")
    q = os.path.join(cfg, "qt6ct/qt6ct.conf")
    if os.path.exists(q) and set_key(q, "Appearance", "icon_theme", theme): print("edited qt6ct.conf")
main()
