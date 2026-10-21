#!/usr/bin/env bash
# Layer 5 (dock) -- apply to the LIVE desktop. Run by the orchestrator, not
# by the layer agent. The shell itself needs no copying: the live shell runs
# from the repo (~/qml-rice/shell is a symlink to <repo>/shell), so the dock
# arrives with the merge. What lives OUTSIDE the repo is the Hyprland blur
# rule for the `qml-rice:dock` layer namespace in ~/.config/hypr/hyprland/glass.lua;
# this script appends exactly that block (targeted, idempotent, backed up).
#
# Honours $HOME so it can be proven in a throwaway HOME.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
src="$repo/hypr/hyprland/glass.lua"
live="$HOME/.config/hypr/hyprland/glass.lua"
state="$HOME/.local/state/qml-rice/mac-dock"
begin='-- mac-dock:begin'
end='-- mac-dock:end'

[ -f "$src" ] || { echo "repo glass.lua missing: $src" >&2; exit 1; }
[ -f "$live" ] || { echo "live glass.lua missing: $live (nothing to patch; is the hypr config installed?)" >&2; exit 1; }

block="$(awk -v b="$begin" -v e="$end" '$0==b{f=1} f{print} $0==e{f=0}' "$src")"
[ -n "$block" ] || { echo "no mac-dock block in $src" >&2; exit 1; }

if grep -qxF -- "$begin" "$live"; then
  if [ "$(awk -v b="$begin" -v e="$end" '$0==b{f=1} f{print} $0==e{f=0}' "$live")" = "$block" ]; then
    echo "dock blur rule already present and current in $live (nothing to do)"
    restart=1
  fi
fi

if [ -z "${restart:-}" ]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  dir="$state/$stamp"
  n=1
  while [ -e "$dir" ]; do dir="$state/$stamp-$n"; n=$((n+1)); done   # never overwrite a backup
  mkdir -p "$dir"
  cp -p "$live" "$dir/glass.lua"
  printf 'target=%s\nstamp=%s\n' "$live" "$stamp" > "$dir/MANIFEST"
  tmp="$(mktemp)"
  if grep -qxF -- "$begin" "$live"; then
    # replace a stale block in place
    awk -v b="$begin" -v e="$end" -v blk="$block" '$0==b{print blk; skip=1} skip{ if($0==e) skip=0; next } {print}' "$live" > "$tmp"
  else
    { cat "$live"; printf '\n'; awk -v b="$begin" -v e="$end" '/^-- Dock \(shell\/dock/{f=1} f{print} $0==e{f=0}' "$src"; } > "$tmp"
  fi
  cat "$tmp" > "$live"; rm -f "$tmp"
  echo "patched $live (backup: $dir)"
fi

cat <<MSG

Next steps (the orchestrator does these, apply.sh never touches live state):
  1. Hyprland must re-read its config for the layer rule:  hyprctl reload
  2. Restart the shell so the dock appears (shell/shell.qml now instantiates it
     behind setting dock.enabled, default true):
        pkill -f '^qs -p ./shell.qml'     # then relaunch the shell as usual
        (or: qml-rice restart-shell)
Disable without reverting:  set dock.enabled=false in the shell settings.json.
MSG
