#!/usr/bin/env bash
# install-thunar.sh: adds a "Quick Look" custom action to Thunar and binds it
# to Ctrl+Space (runs `quicklook %f`, see tools/quicklook/quicklook).
#
#   --dry-run       print the diff that would be applied; write nothing
#   --config-dir D  use D instead of ~/.config/Thunar (for testing)
#
# Edits ~/.config/Thunar/uca.xml and ~/.config/Thunar/accels.scm. Both are
# backed up first (only when a write is about to happen) into
# ~/.local/state/qml-rice/quicklook-backup/<timestamp>/. Idempotent: a second
# run finds the same entries and changes nothing.
#
# Key choice: Space is NOT used. GTK3 (Thunar's views) uses a bare Space to
# toggle the cursor row and to type a space into the type-ahead search, and a
# Thunar accelerator is checked before the view sees the key, so a bare Space
# binding would swallow both. Ctrl+Space is not a typed character, so type-ahead
# never sees it; it only shadows GTK's Ctrl+Space "toggle cursor row".
set -euo pipefail

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

dry_run=0
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/Thunar"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=1 ;;
        --config-dir)
            [ "$#" -ge 2 ] || { echo "install-thunar: --config-dir needs a path" >&2; exit 2; }
            config_dir="$2"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "install-thunar: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

state_root="${XDG_STATE_HOME:-$HOME/.local/state}/qml-rice/quicklook-backup"
seed_uca=/etc/xdg/Thunar/uca.xml

command -v python3 >/dev/null 2>&1 || { echo "install-thunar: python3 is required" >&2; exit 1; }

python3 - "$dry_run" "$config_dir" "$seed_uca" "$state_root" <<'PY'
import datetime
import difflib
import os
import re
import shutil
import sys

dry_run = sys.argv[1] == "1"
config_dir, seed_uca, state_root = sys.argv[2], sys.argv[3], sys.argv[4]

UID = "qml-rice-quicklook"
ACCEL_PATH = "<Actions>/ThunarActions/uca-action-" + UID
ACCEL = "<Primary>space"
ACTION = """  <action>
    <icon>document-preview</icon>
    <name>Quick Look</name>
    <unique-id>%s</unique-id>
    <command>quicklook %%f</command>
    <description>Preview the file in the shell's Quick Look window</description>
    <patterns>*</patterns>
    <directories/>
    <audio-files/>
    <image-files/>
    <other-files/>
    <text-files/>
    <video-files/>
  </action>
""" % UID
ACCEL_HEADER = "; thunar GtkAccelMap rc-file         -*- scheme -*-\n"

uca_path = os.path.join(config_dir, "uca.xml")
accels_path = os.path.join(config_dir, "accels.scm")


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def diff(old, new, name):
    return "".join(difflib.unified_diff(
        (old or "").splitlines(True), new.splitlines(True),
        fromfile=name + (" (absent)" if old is None else ""), tofile=name))


# ---- uca.xml -------------------------------------------------------------
old_uca = read(uca_path) if os.path.exists(uca_path) else None
if old_uca is not None:
    base = old_uca
elif os.path.exists(seed_uca):
    # No user file yet: Thunar shows the system one, so start from it to keep
    # those actions visible once the user file exists.
    base = read(seed_uca)
else:
    base = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<actions>\n</actions>\n"

# One action block that carries our unique-id. The inner group cannot cross a
# closing </action>, so the match stays inside a single action.
ours = re.compile(r"[ \t]*<action>(?:(?!</action>).)*?<unique-id>%s</unique-id>.*?</action>[ \t]*\n"
                  % re.escape(UID), re.S)
existing_block = ours.search(base)
if existing_block and existing_block.group(0) == ACTION:
    uca_new = base
else:
    stripped = ours.sub("", base)
    close = stripped.rfind("</actions>")
    if close < 0:
        sys.exit("install-thunar: %s has no </actions>; refusing to edit it" % uca_path)
    uca_new = stripped[:close] + ACTION + stripped[close:]

# ---- accels.scm ----------------------------------------------------------
old_accels = read(accels_path) if os.path.exists(accels_path) else None
line_new = '(gtk_accel_path "%s" "%s")\n' % (ACCEL_PATH, ACCEL)
lines = (old_accels if old_accels is not None else ACCEL_HEADER).splitlines(True)
if lines and not lines[-1].endswith("\n"):
    lines[-1] += "\n"

conflicts = [l.rstrip() for l in lines
             if ('"%s")' % ACCEL) in l and not l.lstrip().startswith(";") and ACCEL_PATH not in l]
if any(l == line_new for l in lines):
    accels_new = old_accels
else:
    replaced = False
    out = []
    for l in lines:
        if ACCEL_PATH in l:
            if not replaced:
                out.append(line_new)
                replaced = True
            continue
        out.append(l)
    if not replaced:
        out.append(line_new)
    accels_new = "".join(out)

# ---- report and write ----------------------------------------------------
changes = []
if uca_new != old_uca:
    changes.append((uca_path, old_uca, uca_new,
                    "created from %s" % seed_uca if old_uca is None and os.path.exists(seed_uca)
                    else ("created" if old_uca is None else "updated")))
if accels_new != old_accels:
    changes.append((accels_path, old_accels, accels_new,
                    "created" if old_accels is None else "updated"))

for w in conflicts:
    print("WARNING: %s is already bound to %s by another entry: %s" % (accels_path, ACCEL, w))

if not changes:
    print("No changes: Quick Look is already installed in %s" % config_dir)
    sys.exit(0)

for path, old, new, how in changes:
    print("%s %s (%s)" % ("WOULD CHANGE" if dry_run else "CHANGE", path, how))
    sys.stdout.write(diff(old, new, path))

if dry_run:
    print("dry run: nothing written")
    sys.exit(0)

stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
backup_dir = os.path.join(state_root, stamp)
backed = []
for path in (uca_path, accels_path):
    if os.path.exists(path):
        os.makedirs(backup_dir, exist_ok=True)
        dest = os.path.join(backup_dir, os.path.basename(path))
        shutil.copy2(path, dest)
        backed.append((path, dest))
for src, dest in backed:
    print("BACKUP %s -> %s" % (src, dest))
if not backed:
    print("BACKUP none (no existing Thunar files)")

os.makedirs(config_dir, exist_ok=True)
for path, _old, new, _how in changes:
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(new)
    print("WROTE %s" % path)
PY

# PATH check and the next steps (the script never edits PATH or restarts Thunar).
if [ "$dry_run" -eq 0 ]; then
    if ! command -v quicklook >/dev/null 2>&1; then
        echo "NOTE: quicklook is not on PATH. Add it, e.g.:"
        echo "      ln -s \"$(cd "$(dirname "$0")" && pwd)/quicklook\" ~/.local/bin/quicklook"
    fi
    echo "NOTE: restart Thunar for the action and key to load (thunar -q, then reopen)."
fi
