#!/usr/bin/env python3
"""Targeted, idempotent text merges for tools/mac-apps/apply.sh and check.sh.

Every sub-command reads a live file and prints the merged result on stdout, so
the caller can compare with the original and only then write it. Nothing here
touches the disk. Run as:  python3 -I merge.py <command> ...

  flags-conf  FILE FLAG...              one flag per line (spotify-flags.conf)
  desktop     FILE BINARY FLAG...       merge FLAGs into every Exec= line whose
                                        program is BINARY
  ini         FILE SECTION KEY VALUE    set KEY in [SECTION] (Qt/GTK ini files)
  env-cursor  FILE                      add the XCURSOR_* block to a Hyprland env.lua
  env-qt      FILE VALUE                set QT_QPA_PLATFORMTHEME in env.lua
  check-flags FILE FLAG...              exit 0 if every FLAG is present (conf or Exec)
"""
import re
import sys

ENABLE_FEATURES = "--enable-features"

CURSOR_BLOCK = (
    "-- >>> mac-apps cursor (tools/mac-apps/apply.sh) >>>\n"
    'hl.env("XCURSOR_THEME", "macOS")\n'
    'hl.env("XCURSOR_SIZE", "24")\n'
    "-- <<< mac-apps cursor <<<\n"
)


def key_of(tok):
    return tok.split("=", 1)[0]


def merge_tokens(tokens, flags):
    """Return tokens with each flag present. Same-key flags: enable-features is
    unioned; any other existing value is left alone (the owner's value wins)."""
    out = list(tokens)
    added = []
    for flag in flags:
        key = key_of(flag)
        idx = next((i for i, t in enumerate(out) if key_of(t) == key), None)
        if idx is None:
            out.append(flag)
            added.append(flag)
        elif key == ENABLE_FEATURES:
            have = out[idx].split("=", 1)[1].split(",") if "=" in out[idx] else []
            want = flag.split("=", 1)[1].split(",")
            merged = have + [f for f in want if f not in have]
            out[idx] = ENABLE_FEATURES + "=" + ",".join(merged)
        elif out[idx] != flag:
            sys.stderr.write("merge: keeping existing %s (wanted %s)\n" % (out[idx], flag))
    return out


def cmd_flags_conf(path, flags):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    live = [l for l in lines if l.strip() and not l.lstrip().startswith("#")]
    tokens = [l.strip() for l in live]
    merged = merge_tokens(tokens, flags)
    # merge_tokens replaces in place and appends new flags at the end.
    new_flags = merged[len(tokens):]
    # Rewrite only the flag lines that changed (enable-features union), keep the rest verbatim.
    out = []
    for l in lines:
        s = l.strip()
        if s and not s.startswith("#") and key_of(s) in {key_of(t) for t in merged}:
            k = key_of(s)
            out.append(next(t for t in merged if key_of(t) == k))
        else:
            out.append(l)
    out.extend(new_flags)
    sys.stdout.write("\n".join(out) + "\n")


def cmd_check_flags(path, flags):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    toks = []
    for l in text.splitlines():
        s = l.strip()
        if s.startswith("Exec="):
            toks.extend(s[5:].split())
        elif s and not s.startswith("#") and "=" in s:
            toks.append(s)
    have_features = set()
    for t in toks:
        if key_of(t) == ENABLE_FEATURES and "=" in t:
            have_features.update(t.split("=", 1)[1].split(","))
    missing = []
    for flag in flags:
        if key_of(flag) == ENABLE_FEATURES:
            if not set(flag.split("=", 1)[1].split(",")) <= have_features:
                missing.append(flag)
        elif flag not in toks:
            missing.append(flag)
    if missing:
        sys.stdout.write("missing: " + " ".join(missing) + "\n")
        sys.exit(1)


def cmd_desktop(path, binary, flags):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    out = []
    for l in lines:
        if l.startswith("Exec="):
            toks = l[5:].split()
            if toks and toks[0] == binary:
                rest = toks[1:]
                merged = merge_tokens(rest, flags)
                # merge_tokens replaces in place and appends new flags at the end;
                # move the appended ones right after the binary, before any %U.
                extras = merged[len(rest):]
                out.append("Exec=" + " ".join([toks[0]] + extras + merged[:len(rest)]))
                continue
        out.append(l)
    sys.stdout.write("\n".join(out) + "\n")


def cmd_ini(path, section, key, value):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    header = "[%s]" % section
    start = next((i for i, l in enumerate(lines) if l.strip() == header), None)
    if start is None:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend([header, "%s=%s" % (key, value)])
    else:
        end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
        hit = None
        for i in range(start + 1, end):
            if re.match(r"^\s*%s\s*=" % re.escape(key), lines[i]):
                hit = i
                break
        if hit is None:
            lines.insert(start + 1, "%s=%s" % (key, value))
        else:
            lines[hit] = "%s=%s" % (key, value)
    sys.stdout.write("\n".join(lines) + "\n")


def cmd_env_cursor(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if re.search(r'hl\.env\(\s*"XCURSOR_THEME"', text):
        sys.stdout.write(text)
        return
    if text and not text.endswith("\n"):
        text += "\n"
    sys.stdout.write(text + "\n" + CURSOR_BLOCK)


def cmd_env_qt(path, value):
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    pat = re.compile(r'^(\s*)hl\.env\(\s*"QT_QPA_PLATFORMTHEME"\s*,\s*"[^"]*"\s*\)')
    hit = 0
    for i, l in enumerate(lines):
        m = pat.match(l)
        if m:
            lines[i] = '%shl.env("QT_QPA_PLATFORMTHEME", "%s")' % (m.group(1), value)
            hit += 1
    if hit == 0:
        lines.append('hl.env("QT_QPA_PLATFORMTHEME", "%s")' % value)
    sys.stdout.write("\n".join(lines) + "\n")


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    cmd, args = argv[1], argv[2:]
    if cmd == "flags-conf":
        cmd_flags_conf(args[0], args[1:])
    elif cmd == "check-flags":
        cmd_check_flags(args[0], args[1:])
    elif cmd == "desktop":
        cmd_desktop(args[0], args[1], args[2:])
    elif cmd == "ini":
        cmd_ini(*args[:4])
    elif cmd == "env-cursor":
        cmd_env_cursor(args[0])
    elif cmd == "env-qt":
        cmd_env_qt(args[0], args[1])
    else:
        sys.stderr.write("unknown command: %s\n" % cmd)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
