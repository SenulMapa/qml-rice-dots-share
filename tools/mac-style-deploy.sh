#!/usr/bin/env bash
# mac-style-deploy.sh: OWNER-RUN deploy of the mac-style branch (the Tahoe "mac" presentation).
#
#   bash tools/mac-style-deploy.sh              run the steps; asks y / N / s(kip) before each one
#   bash tools/mac-style-deploy.sh --dry-run    print every command that would run; change nothing
#   bash tools/mac-style-deploy.sh --rollback   restore the glass.lua backup, reset master to the
#                                               recorded old sha, and reload Hyprland
#
# Steps:
#   (a) record master's sha in ~/.local/state/qml-rice/mac-style-deploy.old
#   (b) merge mac-style into master (fast-forward if possible, else --no-ff), then check the shell log
#   (c) back up hypr/hyprland/glass.lua, add the mac-style block if it is missing,
#       run hyprctl reload and check that hyprctl configerrors is empty
#   (d) optionally run `qml-rice ipc style set mac`, and print how to switch back
#
# Nothing is pushed. Every command is printed before it runs.
set -euo pipefail

REPO="$HOME/qml-rice-dots"
BRANCH="mac-style"
HYPR_GLASS="$HOME/.config/hypr/hyprland/glass.lua"
STATE_DIR="$HOME/.local/state/qml-rice"
OLD_FILE="$STATE_DIR/mac-style-deploy.old"
GLASS_BAK_FILE="$STATE_DIR/mac-style-deploy.glass-backup"
# qs keys instances by the resolved path, so resolve the ~/qml-rice/shell symlink.
SHELL_QML="$(realpath -m "$HOME/qml-rice/shell/shell.qml")"

DRY_RUN=0
ROLLBACK=0
ASK_OK=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --rollback) ROLLBACK=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'ABORT: %s\n' "$*" >&2; exit 1; }

# ask LABEL: y runs the step, s skips it, N (or anything else) stops the whole run.
# A dry run never prompts: it names the step and runs nothing.
ask() {
  ASK_OK=0
  if (( DRY_RUN )); then
    say "[dry run] would ask: $1"
    ASK_OK=1
    return 0
  fi
  local ans=""
  printf '\n%s\n[y/N/s(kip)] ' "$1"
  read -r ans || ans=""
  case "$ans" in
    y|Y|yes) ASK_OK=1 ;;
    s|S|skip) say "skipped: $1" ;;
    *) say "stopped before: $1. Nothing after this was run."; exit 3 ;;
  esac
}

# run CMD...: prints the command, then runs it unless this is a dry run.
run() {
  say "+ $*"
  if (( DRY_RUN )); then
    return 0
  fi
  "$@"
}

# write_text PATH TEXT: writes TEXT and a newline to PATH (printed only on a dry run).
write_text() {
  say "+ write $1: $2"
  if (( DRY_RUN )); then
    return 0
  fi
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
}

# qs_text: the shell's qs log for this config, ANSI codes stripped.
qs_text() {
  qs log -p "$SHELL_QML" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true
}

qs_lines() {
  qs_text | wc -l
}

# shell_check BEFORE: waits up to 15 s for a fresh "Configuration Loaded" after the first BEFORE
# lines of the qs log, and fails on any ERROR or "caused by" line in the new part.
shell_check() {
  local before="$1" text new
  if (( DRY_RUN )); then
    say "+ qs log -p $SHELL_QML   (wait for a fresh 'Configuration Loaded' and no ERROR)"
    return 0
  fi
  for _ in $(seq 1 15); do
    text="$(qs_text)"
    new="$(tail -n "+$((before + 1))" <<<"$text")"
    if grep -q "Configuration Loaded" <<<"$new"; then
      if grep -Eq "ERROR|caused by" <<<"$new"; then
        say "shell log has ERROR lines since the merge:"
        grep -E "ERROR|caused by" <<<"$new" | head -20 || true
        return 1
      fi
      say "shell reloaded: fresh 'Configuration Loaded', no ERROR"
      return 0
    fi
    sleep 1
  done
  say "no fresh 'Configuration Loaded' within 15 s"
  return 1
}

# reload_check: hyprctl configerrors must print nothing.
reload_check() {
  local errs=""
  if (( DRY_RUN )); then
    say "+ hyprctl configerrors   (must print nothing)"
    return 0
  fi
  errs="$(hyprctl configerrors 2>&1 || true)"
  if [[ -n "$errs" ]]; then
    say "hyprctl configerrors is not empty:"
    say "$errs"
    return 1
  fi
  say "hyprctl configerrors: empty"
}

preflight() {
  local c
  for c in git qs hyprctl realpath sed; do
    command -v "$c" >/dev/null 2>&1 || die "required command missing: $c"
  done
  [[ -d "$REPO" ]] || die "main checkout not found: $REPO"
  [[ "$(git -C "$REPO" symbolic-ref --short HEAD)" == master ]] || die "$REPO is not on master"
  if [[ -n "$(git -C "$REPO" status --porcelain)" ]]; then
    git -C "$REPO" status --short >&2
    if (( DRY_RUN )); then
      say "WARNING: a real run would stop here: $REPO has local changes or untracked files"
    else
      die "$REPO has local changes or untracked files; the merge would stop or overwrite them. Clean it first."
    fi
  fi
  git -C "$REPO" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null || die "no $BRANCH branch in $REPO"
  [[ -f "$HYPR_GLASS" ]] || die "live Hyprland glass config missing: $HYPR_GLASS"
  [[ -f "$SHELL_QML" ]] || die "shell entry not found: $SHELL_QML"
}

# ---- (a) record master ------------------------------------------------------------------------
step_record_old() {
  local sha
  sha="$(git -C "$REPO" rev-parse master)"
  say "master is at $sha"
  ask "(a) record master's sha in $OLD_FILE"
  if (( ASK_OK )); then
    write_text "$OLD_FILE" "$sha"
  fi
}

# ---- (b) merge and check the shell -----------------------------------------------------------
step_merge() {
  local kind before
  if [[ "$(git -C "$REPO" rev-parse master)" == "$(git -C "$REPO" rev-parse "$BRANCH")" ]]; then
    say "master already at $BRANCH; nothing to merge"
    return 0
  fi
  if git -C "$REPO" merge-base --is-ancestor master "$BRANCH"; then
    kind="ff-only"
    MERGE_CMD=(git -C "$REPO" merge --ff-only "$BRANCH")
  else
    kind="no-ff"
    MERGE_CMD=(git -C "$REPO" merge --no-ff -m "Merge branch '$BRANCH'" "$BRANCH")
  fi
  ask "(b) merge $BRANCH into master ($kind): ${MERGE_CMD[*]}, then check the shell log"
  (( ASK_OK )) || return 0
  before="$(qs_lines)"
  run "${MERGE_CMD[@]}"
  if ! shell_check "$before"; then
    die "shell check failed after the merge. Undo with: bash $0 --rollback"
  fi
}

# ---- (c) glass.lua and Hyprland reload -------------------------------------------------------
step_glass() {
  local block bak
  block="$(git -C "$REPO" show "$BRANCH:hypr/hyprland/glass.lua" | sed -n '/^-- mac-style:begin$/,/^-- mac-style:end$/p')"
  [[ -n "$block" ]] || die "$BRANCH has no mac-style block in hypr/hyprland/glass.lua"
  bak="$HYPR_GLASS.bak-mac-style-$(date +%Y%m%d-%H%M%S)"
  ask "(c) back up $HYPR_GLASS to $bak, add the mac-style block if missing, reload Hyprland"
  (( ASK_OK )) || return 0
  run cp -p "$HYPR_GLASS" "$bak"
  write_text "$GLASS_BAK_FILE" "$bak"
  if grep -q '^-- mac-style:begin$' "$HYPR_GLASS"; then
    say "$HYPR_GLASS already has the mac-style block"
  else
    say "+ append the mac-style block from $BRANCH:hypr/hyprland/glass.lua to $HYPR_GLASS"
    if (( ! DRY_RUN )); then
      printf '\n%s\n' "$block" >> "$HYPR_GLASS"
    fi
  fi
  run hyprctl reload
  if ! reload_check; then
    die "Hyprland reports config errors. Restore with: bash $0 --rollback"
  fi
}

# ---- (d) optional style switch ---------------------------------------------------------------
step_style() {
  ask "(d) switch the presentation to mac: qml-rice ipc style set mac"
  (( ASK_OK )) || return 0
  command -v qml-rice >/dev/null 2>&1 || die "qml-rice not found on PATH"
  run qml-rice ipc style set mac
  say "switch back to the pill any time: qml-rice ipc style set pill"
  say "or toggle between the two:       qml-rice ipc style toggle"
}

# ---- rollback --------------------------------------------------------------------------------
rollback() {
  local old bak
  command -v git >/dev/null 2>&1 || die "git not found"
  [[ -f "$OLD_FILE" ]] || die "no recorded old sha at $OLD_FILE; nothing to roll back"
  old="$(cat "$OLD_FILE")"
  say "rollback: master goes back to $old"
  if [[ -f "$GLASS_BAK_FILE" ]]; then
    bak="$(cat "$GLASS_BAK_FILE")"
    ask "restore $HYPR_GLASS from $bak"
    if (( ASK_OK )); then
      run cp -p "$bak" "$HYPR_GLASS"
    fi
  else
    say "no glass.lua backup recorded; glass.lua is left as it is"
  fi
  ask "git -C $REPO reset --keep $old"
  if (( ASK_OK )); then
    run git -C "$REPO" reset --keep "$old"
  fi
  ask "hyprctl reload"
  if (( ASK_OK )); then
    run hyprctl reload
    reload_check || die "hyprctl configerrors is not empty after the rollback"
  fi
}

main() {
  if (( ROLLBACK )); then
    rollback
    exit 0
  fi
  preflight
  say "plan: (a) record master, (b) merge $BRANCH, (c) glass.lua and Hyprland reload, (d) optional style mac"
  step_record_old
  step_merge
  step_glass
  step_style
  say "deploy steps finished"
}

main
