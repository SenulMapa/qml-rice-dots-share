#!/usr/bin/env bash
# mac-parity-deploy.sh: OWNER-RUN deploy of the Mac parity work (shell merge, Hyprland config,
# macwm + stallmon services, probes). Run it at the desk. Every step says what it is about to do
# and asks [y/N/s(kip)]: y runs the step, s skips it and continues, N stops the whole run.
#
#   bash tools/mac-parity-deploy.sh [--yes]      run steps 0-7 (--yes answers y to every prompt)
#   bash tools/mac-parity-deploy.sh --rollback   restore the latest ~/.config/hypr backup, reset
#                                                master to the recorded OLD, disable macwm + stallmon,
#                                                and reload Hyprland
#
# Run it from the integrate worktree: this script only exists in master after step 2 merges it.
set -euo pipefail
shopt -s nullglob

REPO="$HOME/qml-rice-dots"
HYPR="$HOME/.config/hypr"
BAK="$HOME/.config/hypr.bak-mac-parity-2026-10-19"
STATE_DIR="$HOME/.local/state/qml-rice"
OLD_FILE="$STATE_DIR/mac-parity-deploy.old"
# qs keys instances by the resolved path, so resolve the ~/qml-rice/shell symlink.
SHELL_QML="$(realpath -m "$HOME/qml-rice/shell/shell.qml")"
# Probe from this checkout: the main checkout lacks tools/perf until step 2 merges it.
PROBE="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/perf/qs-cpu-probe.sh"
DOCKQA="${DOCKQA_DIR:-/tmp/dockqa}"

YES=0
ROLLBACK=0
CONFIRMED=0
OLD=""
CPU_NUM="NA"
CPU_STATUS="SKIP"
RESULTS=()

for arg in "$@"; do
  case "$arg" in
    --yes) YES=1 ;;
    --rollback) ROLLBACK=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }
hdr() { printf '\n==== %s ====\n' "$*"; }
record() { RESULTS+=("$1|$2|$3"); }

summary() {
  local r s st d
  printf '\n%-22s %-10s %s\n' "STEP" "STATUS" "DETAIL"
  printf '%-22s %-10s %s\n' "----" "------" "------"
  for r in "${RESULTS[@]+"${RESULTS[@]}"}"; do
    IFS='|' read -r s st d <<<"$r"
    printf '%-22s %-10s %s\n' "$s" "$st" "$d"
  done
}

die() {
  record "ABORT" "FAIL" "$*"
  summary
  echo "ABORTED: $*" >&2
  exit 1
}

# confirm LABEL: sets CONFIRMED=1 to run the step, 0 to skip it. N stops the whole run (exit 3).
confirm() {
  local ans=""
  if (( YES )); then
    say "[--yes] $1"
    CONFIRMED=1
    return 0
  fi
  printf '%s\n[y/N/s(kip)] ' "$1"
  read -r ans || ans=""
  case "$ans" in
    y|Y|yes) CONFIRMED=1 ;;
    s|S|skip) CONFIRMED=0 ;;
    *)
      say "Stopped before: $1. Steps after this were not run."
      summary
      exit 3
      ;;
  esac
}

load_old() {
  [[ -f "$OLD_FILE" ]] || die "no recorded OLD at $OLD_FILE (run step 0 first)"
  OLD="$(cat "$OLD_FILE")"
}

preflight() {
  local c
  for c in git qs hyprctl python3 jq patch luac5.4 systemctl journalctl awk; do
    command -v "$c" >/dev/null 2>&1 || die "required command missing: $c"
  done
  [[ -d "$REPO" ]] || die "main checkout not found: $REPO"
  [[ "$(git -C "$REPO" symbolic-ref --short HEAD)" == master ]] || die "$REPO is not on master"
  git -C "$REPO" rev-parse -q --verify integrate >/dev/null || die "no integrate branch in $REPO"
  [[ -f "$HYPR/hyprland.lua" ]] || die "live Hyprland config missing: $HYPR/hyprland.lua"
  [[ -f "$SHELL_QML" ]] || die "shell entry not found: $SHELL_QML"
}

# ---- quickshell log check -------------------------------------------------------------------

qs_text() { qs log -p "$SHELL_QML" 2>&1 || true; }
qs_lines() { qs_text | wc -l; }

# qs_wait BEFORE_LINES: poll up to 15 s for a fresh "Configuration Loaded" among the log lines
# after BEFORE_LINES, and fail on any new ERROR or "caused by" line.
qs_wait() {
  local before="$1" i out total new
  new=""
  for i in $(seq 1 15); do
    out="$(qs_text)"
    total="$(printf '%s\n' "$out" | wc -l)"
    if (( total < before )); then
      new="$out"
    else
      new="$(printf '%s\n' "$out" | tail -n +"$((before + 1))")"
    fi
    if grep -Eq 'ERROR|[Cc]aused by' <<<"$new"; then
      printf '%s\n' "$new" | tail -n 40
      say "qs: new ERROR / 'caused by' lines after the change"
      return 1
    fi
    if grep -q 'Configuration Loaded' <<<"$new"; then
      say "qs: fresh 'Configuration Loaded' after ${i}s, no new errors"
      return 0
    fi
    sleep 1
  done
  printf '%s\n' "$new" | tail -n 40
  say "qs: no fresh 'Configuration Loaded' within 15 s"
  return 1
}

# ff_merge_checked BRANCH: ff-only merge BRANCH into master, verify the shell reloaded cleanly.
# On failure master is reset to its pre-merge commit and the old config is re-checked.
ff_merge_checked() {
  local branch="$1" pre target before before2
  pre="$(git -C "$REPO" rev-parse master)"
  target="$(git -C "$REPO" rev-parse "$branch")"
  if [[ "$pre" == "$target" ]]; then
    say "master already at $branch; nothing to merge"
    return 0
  fi
  before="$(qs_lines)"
  if ! git -C "$REPO" merge --ff-only "$branch"; then
    say "ff-only merge refused; master unchanged"
    return 1
  fi
  if qs_wait "$before"; then
    return 0
  fi
  say "shell check failed: resetting master to $pre"
  before2="$(qs_lines)"
  git -C "$REPO" reset --keep "$pre" || say "WARNING: git reset --keep $pre failed"
  if qs_wait "$before2"; then
    say "old shell config reloaded"
  else
    say "WARNING: could not confirm the old shell config reloaded"
  fi
  return 1
}

# ---- CPU probe ------------------------------------------------------------------------------

# cpu_probe SECONDS: runs qs-cpu-probe.sh, sets CPU_NUM and CPU_STATUS (PASS / OVER / NA).
cpu_probe() {
  local out rc=0 budget="${QS_CPU_BUDGET:-2.0}"
  out="$(QS_CPU_BUDGET="$budget" bash "$PROBE" "$1" 2>&1)" || rc=$?
  CPU_NUM="$(sed -n 's/^qs_cpu_pct=\([0-9.]*\).*/\1/p' <<<"$out" | head -n 1 || true)"
  CPU_NUM="${CPU_NUM:-NA}"
  case "$rc" in
    0) CPU_STATUS="PASS" ;;
    1) CPU_STATUS="OVER" ;;
    *) CPU_STATUS="NA" ;;
  esac
  say "qs_cpu_pct=$CPU_NUM (budget $budget): $CPU_STATUS"
}

# ---- step 0: backups ------------------------------------------------------------------------

step0_backup() {
  mkdir -p "$STATE_DIR"
  if [[ -e "$BAK" ]]; then
    say "backup already exists, not overwritten: $BAK"
    [[ -f "$OLD_FILE" ]] || die "backup exists but $OLD_FILE is missing"
  else
    [[ -d "$HYPR" ]] || die "$HYPR not found"
    cp -a "$HYPR" "$BAK"
    git -C "$REPO" rev-parse master > "$OLD_FILE"
  fi
  load_old
  say "backup: $BAK"
  say "OLD (master before deploy): $OLD"
  record 0 ok "backup written, OLD=${OLD:0:12}"
  cpu_probe 60
  record "0 start CPU" "$CPU_STATUS" "qs_cpu_pct=$CPU_NUM"
}

# ---- step 1: repo wiring (committed in the worktree; script only verifies) -------------------

step1_verify() {
  local txt
  txt="$(git -C "$REPO" show integrate:hypr/hyprland.lua)"
  if grep -qF 'require("hyprland.mac-windows")' <<<"$txt"; then
    record 1 ok "require line present on integrate"
  else
    die "integrate:hypr/hyprland.lua has no require(\"hyprland.mac-windows\"); commit step 1 first"
  fi
}

# ---- step 2: shell merge --------------------------------------------------------------------

step2_merge() {
  if ff_merge_checked integrate; then
    record 2 ok "master = integrate, shell reloaded clean"
  else
    record 2 FAILED "shell check failed; master reset to pre-merge commit"
    die "step 2 failed: master reset with --keep (see above)"
  fi
}

# ---- step 3: Hyprland config ----------------------------------------------------------------

hypr_rollback() {
  say "STEP 3 FAILED: $1"
  say "restoring $BAK -> $HYPR and reloading Hyprland"
  rm -rf "$HYPR"
  cp -a "$BAK" "$HYPR"
  hyprctl reload >/dev/null 2>&1 || say "WARNING: reload after restore failed"
  record 3 ROLLED-BACK "$1"
  die "step 3 rolled back: $1"
}

step3_hypr() {
  [[ -d "$BAK" ]] || die "no backup at $BAK (run step 0 first)"
  load_old
  local t plug_before plug_after fm errs
  t="$(mktemp -d)"

  # Plan every change in a scratch copy first. Nothing under $HYPR is touched until all checks pass.
  git -C "$REPO" show integrate:hypr/hyprland/mac-windows.lua > "$t/mac-windows.lua"
  git -C "$REPO" show integrate:hypr/hyprland/mac.lua > "$t/mac.lua"

  # glass.lua: only the dock ignore_alpha hunk (OLD -> integrate), applied to a copy of the live file.
  cp "$HYPR/hyprland/glass.lua" "$t/glass.lua"
  if grep -qF 'namespace = "^qml-rice:dock$" }, ignore_alpha = 0.05' "$t/glass.lua"; then
    say "glass.lua: dock ignore_alpha already applied"
  else
    git -C "$REPO" diff "$OLD" integrate -- hypr/hyprland/glass.lua > "$t/glass.diff"
    if ! patch --forward --no-backup-if-mismatch "$t/glass.lua" < "$t/glass.diff" > "$t/patch.log" 2>&1; then
      cat "$t/patch.log"
      die "glass.lua hunk does not apply to the live file (drifted); nothing was installed"
    fi
  fi
  grep -qF 'ignore_alpha = 0.05' "$t/glass.lua" || die "glass.lua check failed after patch; nothing was installed"

  # rules.lua: only the phone-airplay-view block, inserted after the Zotero size rule. Never a wholesale copy.
  cp "$HYPR/hyprland/rules.lua" "$t/rules.lua"
  if grep -qF 'phone-airplay-view' "$t/rules.lua"; then
    say "rules.lua: phone-airplay-view rules already present"
  else
    git -C "$REPO" show integrate:hypr/hyprland/rules.lua > "$t/rules-dots.lua"
    awk '/^-- phone-glue: AirPlay viewer/ { on = 1 } on { print } on && /^end$/ { exit }' \
      "$t/rules-dots.lua" > "$t/phone-block.lua"
    grep -qF 'phone-airplay-view' "$t/phone-block.lua" || die "could not extract phone-airplay-view block from integrate"
    local anchors
    anchors="$(grep -F '^(Zotero)$' "$t/rules.lua" | grep -cF 'monitor_h*0.45' || true)"
    [[ "$anchors" == 1 ]] || die "rules.lua Zotero anchor matched $anchors times, expected 1; nothing was installed"
    awk -v blk="$t/phone-block.lua" '
      { print }
      index($0, "^(Zotero)$") && index($0, "monitor_h*0.45") {
        print ""
        while ((getline line < blk) > 0) print line
        close(blk)
      }' "$t/rules.lua" > "$t/rules.new"
    mv "$t/rules.new" "$t/rules.lua"
  fi
  grep -qF 'phone-airplay-view' "$t/rules.lua" || die "rules.lua check failed; nothing was installed"

  # hyprland.lua: the require line right after the webapps block, before gaming.
  cp "$HYPR/hyprland.lua" "$t/hyprland.lua"
  if grep -qF 'require("hyprland.mac-windows")' "$t/hyprland.lua"; then
    say "hyprland.lua: mac-windows already required"
  else
    [[ "$(grep -cF 'require("hyprland.webapps")' "$t/hyprland.lua" || true)" == 1 ]] \
      || die "require(\"hyprland.webapps\") is not unique in live hyprland.lua; nothing was installed"
    awk '
      { print }
      state == 1 && /^end[[:space:]]*$/ {
        print "-- macOS window placement (macwm glue); after webapps, before gaming."
        print "require(\"hyprland.mac-windows\")"
        state = 2
      }
      index($0, "require(\"hyprland.webapps\")") { state = 1 }' "$t/hyprland.lua" > "$t/hyprland.new"
    mv "$t/hyprland.new" "$t/hyprland.lua"
  fi
  [[ "$(grep -cF 'require("hyprland.mac-windows")' "$t/hyprland.lua" || true)" == 1 ]] \
    || die "hyprland.lua check failed; nothing was installed"

  luac5.4 -p "$t/hyprland.lua" "$t/glass.lua" "$t/rules.lua" "$t/mac.lua" "$t/mac-windows.lua" \
    || die "luac5.4 -p failed on the planned files; nothing was installed"

  # Install. The backup at $BAK already holds the pre-deploy state.
  plug_before="$(hyprctl plugin list 2>/dev/null || true)"
  mkdir -p "$HYPR/hyprland"
  cp "$t/mac-windows.lua" "$HYPR/hyprland/mac-windows.lua"
  cp "$t/mac.lua" "$HYPR/hyprland/mac.lua"
  cat "$t/glass.lua" > "$HYPR/hyprland/glass.lua"
  cat "$t/rules.lua" > "$HYPR/hyprland/rules.lua"
  cat "$t/hyprland.lua" > "$HYPR/hyprland.lua"
  rm -rf "$t"

  say "reloading Hyprland"
  hyprctl reload >/dev/null 2>&1 || hypr_rollback "hyprctl reload failed"
  errs="$(hyprctl configerrors 2>&1 || true)"
  if [[ -n "$errs" && "$errs" != "[]" ]]; then
    hypr_rollback "hyprctl configerrors not empty: $errs"
  fi
  fm="$(hyprctl getoption input:follow_mouse -j 2>/dev/null | jq -r '.int' 2>/dev/null || true)"
  [[ "$fm" == 2 ]] || hypr_rollback "input:follow_mouse is '$fm', expected 2"
  if grep -qi hyprbars <<<"$plug_before"; then
    plug_after="$(hyprctl plugin list 2>/dev/null || true)"
    grep -qi hyprbars <<<"$plug_after" || hypr_rollback "hyprbars plugin no longer loaded after reload"
  fi
  record 3 ok "configerrors empty, follow_mouse=2, hyprbars ok"
}

# ---- step 4: services -----------------------------------------------------------------------

step4_services() {
  [[ -f "$REPO/tools/stallmon/install.sh" && -f "$REPO/tools/macwm/install.sh" ]] \
    || die "install scripts missing from $REPO/tools (step 2 must succeed first)"
  bash "$REPO/tools/stallmon/install.sh" || die "stallmon install.sh failed"
  bash "$REPO/tools/macwm/install.sh" || die "macwm install.sh failed"
  local states s1 s2 jlog
  states="$(systemctl --user is-active stallmon.service macwm.service 2>&1 || true)"
  s1="$(sed -n 1p <<<"$states")"
  s2="$(sed -n 2p <<<"$states")"
  say "stallmon: $s1 | macwm: $s2"
  [[ "$s1" == active && "$s2" == active ]] || die "stallmon/macwm not both active (run --rollback to disable them)"
  jlog="$(journalctl --user -u macwm -n 30 --no-pager 2>&1 || true)"
  if grep -q 'Traceback' <<<"$jlog"; then
    printf '%s\n' "$jlog" | tail -n 30
    die "traceback in macwm journal (run --rollback to disable services)"
  fi
  record 4 ok "stallmon and macwm active, no traceback"
}

# ---- step 5: macwm live probes --------------------------------------------------------------

win_by_class() { hyprctl clients -j | jq -c --arg c "$1" 'map(select(.class == $c)) | .[0] // empty'; }
win_by_addr() { hyprctl clients -j | jq -c --arg a "$1" 'map(select(.address == $a)) | .[0] // empty'; }

# wait_win CLASS: poll up to 5 s for a window of that class; prints its JSON.
wait_win() {
  local i w
  for ((i = 0; i < 50; i++)); do
    w="$(win_by_class "$1")"
    if [[ -n "$w" ]]; then
      printf '%s' "$w"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

mon_of() { hyprctl monitors -j | jq -c --argjson id "$(jq -r '.monitor' <<<"$1")" 'map(select(.id == $id)) | .[0]'; }

# centred WINDOW MONITOR: {dx, dy, ok} with ok = window centre within 15% of the monitor centre per axis.
centred() {
  jq -nc --argjson w "$1" --argjson m "$2" '
    (($w.at[0] + $w.size[0] / 2) - ($m.x + ($m.width / $m.scale) / 2)) as $dx
    | (($w.at[1] + $w.size[1] / 2) - ($m.y + ($m.height / $m.scale) / 2)) as $dy
    | {dx: $dx, dy: $dy,
       ok: (($dx | fabs) < 0.15 * ($m.width / $m.scale) and (($dy | fabs) < 0.15 * ($m.height / $m.scale)))}'
}

# workarea MONITOR: logical work area {x, y, w, h} from reserved edges.
workarea() {
  jq -c '{x: (.x + (.reserved // [0,0,0,0])[0]),
          y: (.y + (.reserved // [0,0,0,0])[1]),
          w: (.width / .scale - (.reserved // [0,0,0,0])[0] - (.reserved // [0,0,0,0])[2]),
          h: (.height / .scale - (.reserved // [0,0,0,0])[1] - (.reserved // [0,0,0,0])[3])}' <<<"$1"
}

probe_line() { # ID STATUS DETAIL
  say "  [$2] probe $1: $3"
  record "5$1 probe" "$2" "$3"
}

step5_probes() {
  if ! command -v kitty >/dev/null 2>&1; then
    record 5 SKIP "kitty not installed; probes not run"
    say "kitty not installed; probes not run"
    return 0
  fi
  local ws0 w c mon fl addr1="" addr2="" wa first n w2 wsid pid1 pid_macwm t1 t2 pct ta tb
  ws0="$(hyprctl activeworkspace -j | jq -r '.id')"
  say "starting workspace: $ws0"

  # (a) float by default and roughly centred
  kitty --class macwm-probe -e sleep 60 >/dev/null 2>&1 &
  pid1=$!
  if w="$(wait_win macwm-probe)"; then
    addr1="$(jq -r '.address' <<<"$w")"
    mon="$(mon_of "$w")"
    c="$(centred "$w" "$mon")"
    fl="$(jq -r '.floating' <<<"$w")"
    if [[ "$fl" == true && "$(jq -r '.ok' <<<"$c")" == true ]]; then
      probe_line a PASS "floating, centred (dx=$(jq -r '.dx' <<<"$c") dy=$(jq -r '.dy' <<<"$c"))"
    else
      probe_line a FAIL "floating=$fl centred=$c"
    fi
  else
    probe_line a FAIL "probe window never appeared"
  fi

  # (b) snap left: absolute geometry (x at work-area left, width about half)
  if [[ -n "$addr1" ]]; then
    hyprctl dispatch focuswindow "address:$addr1" >/dev/null 2>&1 || true
    if macwmctl snap left >/dev/null 2>&1; then
      sleep 0.6
      w="$(win_by_addr "$addr1")"
      mon="$(mon_of "$w")"
      wa="$(workarea "$mon")"
      if jq -e -n --argjson w "$w" --argjson a "$wa" \
          '(($w.at[0] - $a.x) | fabs) <= 4 and (($w.size[0] - $a.w / 2) | fabs) <= 0.05 * $a.w' >/dev/null; then
        probe_line b PASS "x=$(jq -r '.at[0]' <<<"$w") (work-area left $(jq -r '.x' <<<"$wa")), w=$(jq -r '.size[0]' <<<"$w") (half of $(jq -r '.w' <<<"$wa"))"
      else
        probe_line b FAIL "snap left geometry at=$(jq -c '.at' <<<"$w") size=$(jq -c '.size' <<<"$w") workarea=$wa"
      fi
    else
      probe_line b FAIL "macwmctl snap left returned an error"
    fi
    macwmctl snap restore >/dev/null 2>&1 || say "warning: snap restore failed"
  else
    probe_line b FAIL "skipped: no probe window"
  fi

  # (c) tiling on an empty workspace 9: a new window must be tiled from its first appearance
  n="$(hyprctl workspaces -j | jq -r 'map(select(.id == 9)) | .[0].windows // 0')"
  if [[ "$n" != 0 ]]; then
    probe_line c FAIL "workspace 9 is not empty ($n windows); not run"
  else
    macwmctl toggle-tiling 9 >/dev/null 2>&1 || say "warning: toggle-tiling 9 on"
    hyprctl dispatch exec "[workspace 9 silent] kitty --class macwm-probe2 -e sleep 30" >/dev/null 2>&1 || true
    first=""
    for ((n = 0; n < 60; n++)); do
      w2="$(win_by_class macwm-probe2)"
      if [[ -n "$w2" ]]; then
        first="$(jq -r '.floating' <<<"$w2")"
        addr2="$(jq -r '.address' <<<"$w2")"
        break
      fi
      sleep 0.05
    done
    sleep 1
    w2="$(win_by_class macwm-probe2)"
    wsid="$(jq -r '.workspace.id' <<<"$w2" 2>/dev/null || echo "?")"
    if [[ -n "$w2" && "$first" == false && "$(jq -r '.floating' <<<"$w2")" == false && "$wsid" == 9 ]]; then
      probe_line c PASS "tiled from first sighting (floating:false on ws 9)"
    else
      probe_line c FAIL "first sighting floating=${first:-none}, now floating=$(jq -r '.floating' <<<"$w2" 2>/dev/null || echo none), ws=$wsid"
      say "    journal (tile rule / fallback messages):"
      journalctl --user -u macwm -n 40 --no-pager 2>/dev/null | grep -Ei 'eval failed|batch|fallback' | tail -n 5 || say "    (none)"
    fi
    macwmctl toggle-tiling 9 >/dev/null 2>&1 || say "warning: toggle-tiling 9 off"
  fi

  # (d) close probes
  [[ -n "$addr1" ]] && hyprctl dispatch closewindow "address:$addr1" >/dev/null 2>&1 || true
  [[ -n "$addr2" ]] && hyprctl dispatch closewindow "address:$addr2" >/dev/null 2>&1 || true
  kill "$pid1" 2>/dev/null || true
  sleep 1
  if [[ -z "$(win_by_class macwm-probe)$(win_by_class macwm-probe2)" ]]; then
    probe_line d PASS "both probe windows closed"
  else
    probe_line d FAIL "probe windows still present"
  fi

  # (e) macwm daemon CPU over 60 s (sampled inline from /proc; < 0.3 %)
  pid_macwm="$(systemctl --user show -p MainPID --value macwm.service)"
  if [[ -z "$pid_macwm" || "$pid_macwm" == 0 ]]; then
    probe_line e FAIL "macwm has no MainPID"
  else
    t1="$(sed 's/.*) //' "/proc/$pid_macwm/stat" | awk '{print $12 + $13}')"
    ta="$(date +%s.%N)"
    sleep 60
    tb="$(date +%s.%N)"
    t2="$(sed 's/.*) //' "/proc/$pid_macwm/stat" | awk '{print $12 + $13}')"
    pct="$(awk -v d="$((t2 - t1))" -v c="$(getconf CLK_TCK)" -v a="$ta" -v b="$tb" \
      'BEGIN { printf "%.3f", d / c / (b - a) * 100 }')"
    if awk -v p="$pct" 'BEGIN { exit !(p < 0.3) }'; then
      probe_line e PASS "macwm CPU ${pct}% over 60 s"
    else
      probe_line e FAIL "macwm CPU ${pct}% over 60 s (limit 0.3%)"
    fi
  fi

  hyprctl dispatch workspace "$ws0" >/dev/null 2>&1 || say "warning: could not return to workspace $ws0"
  say "back on workspace $ws0"
}

# ---- step 6: CPU probe and optional perf/qs-idle merge --------------------------------------

step6_cpu() {
  cpu_probe 60
  record 6 "$CPU_STATUS" "qs_cpu_pct=$CPU_NUM (60 s idle probe)"
  if git -C "$REPO" show-ref --verify --quiet refs/heads/perf/qs-idle; then
    say "branch perf/qs-idle exists"
    confirm "Step 6b: merge perf/qs-idle into master (ff-only, qs log check, reset on failure)?"
    if (( CONFIRMED )); then
      if ff_merge_checked perf/qs-idle; then
        record "6b perf/qs-idle" ok "merged, shell reloaded clean"
      else
        record "6b perf/qs-idle" FAILED "reset to pre-merge commit"
        die "perf/qs-idle merge reverted (see above)"
      fi
    else
      record "6b perf/qs-idle" skipped "owner declined"
    fi
  else
    say "no perf/qs-idle branch; no merge offered"
    record "6b perf/qs-idle" SKIP "branch absent"
  fi
}

# ---- step 7: screenshots --------------------------------------------------------------------

step7_shots() {
  mkdir -p "$DOCKQA"
  if ! command -v grim >/dev/null 2>&1; then
    record 7 SKIP "grim not installed"
    return 0
  fi
  if grim -g "1920,960 1920x120" "$DOCKQA/live-dock.png" 2>/dev/null; then
    say "dock screenshot saved: $DOCKQA/live-dock.png"
    record 7 ok "$DOCKQA/live-dock.png"
  else
    record 7 FAILED "grim dock capture failed"
  fi
  if grim -o DP-1 "$DOCKQA/live-full.png" 2>/dev/null; then
    say "full screenshot saved: $DOCKQA/live-full.png"
  else
    say "full-screen capture failed (output DP-1?)"
  fi
}

# ---- rollback -------------------------------------------------------------------------------

rollback() {
  hdr "ROLLBACK"
  local baks=("$HOME/.config/hypr.bak-mac-parity-"*) latest
  (( ${#baks[@]} > 0 )) || die "no ~/.config/hypr.bak-mac-parity-* backup found"
  latest="${baks[-1]}"
  load_old
  say "will restore: $latest -> $HYPR"
  say "will reset master to: $OLD (currently $(git -C "$REPO" rev-parse master))"
  say "will disable: macwm.service, stallmon.service; then hyprctl reload"
  confirm "Proceed with rollback?"
  if (( ! CONFIRMED )); then
    record ROLLBACK skipped "owner declined"
    return 0
  fi
  rm -rf "$HYPR"
  cp -a "$latest" "$HYPR"
  record "rollback hypr" ok "restored $latest"
  git -C "$REPO" reset --keep "$OLD" || die "git reset --keep $OLD failed"
  record "rollback master" ok "master = $OLD"
  systemctl --user disable --now macwm.service stallmon.service >/dev/null 2>&1 \
    || say "warning: disabling services reported an error"
  record "rollback services" ok "macwm + stallmon disabled"
  hyprctl reload >/dev/null 2>&1 || say "warning: hyprctl reload failed"
  record "rollback reload" ok "hyprctl reload issued"
}

# ---- main -----------------------------------------------------------------------------------

main() {
  if (( ROLLBACK )); then
    preflight
    rollback
    summary
    exit 0
  fi

  preflight

  hdr "Step 0: backups, OLD, starting CPU probe"
  say "About to: copy $HYPR -> $BAK, record master as OLD, run the 60 s CPU probe (70 s)."
  confirm "Run step 0?"
  if (( CONFIRMED )); then step0_backup; else record 0 skipped "owner declined"; fi

  hdr "Step 1: verify the repo wiring"
  say "About to: check integrate:hypr/hyprland.lua has require(\"hyprland.mac-windows\") (no change)."
  step1_verify

  hdr "Step 2: shell merge"
  say "About to: git merge --ff-only integrate into $REPO, then poll qs log for a clean reload (15 s)."
  confirm "Run step 2?"
  if (( CONFIRMED )); then step2_merge; else record 2 skipped "owner declined"; fi

  hdr "Step 3: Hyprland config"
  say "About to: copy mac-windows.lua and mac.lua, apply the glass dock hunk and the rules.lua"
  say "phone-airplay-view block, add the require line to live hyprland.lua, then reload and check."
  say "Rollback target if anything fails: $BAK"
  confirm "Run step 3?"
  if (( CONFIRMED )); then step3_hypr; else record 3 skipped "owner declined"; fi

  hdr "Step 4: services"
  say "About to: run tools/stallmon/install.sh and tools/macwm/install.sh, check both are active."
  confirm "Run step 4?"
  if (( CONFIRMED )); then step4_services; else record 4 skipped "owner declined"; fi

  hdr "Step 5: macwm live probes (a-e)"
  say "About to: spawn kitty probe windows, snap, tile workspace 9, close probes, sample macwm CPU."
  say "Keep hands off the keyboard and mouse for about 2 minutes."
  confirm "Run step 5?"
  if (( CONFIRMED )); then step5_probes; else record 5 skipped "owner declined"; fi

  hdr "Step 6: CPU probe"
  say "About to: run tools/perf/qs-cpu-probe.sh 60 and offer the perf/qs-idle merge if that branch exists."
  confirm "Run step 6?"
  if (( CONFIRMED )); then step6_cpu; else record 6 skipped "owner declined"; fi

  hdr "Step 7: screenshots"
  say "About to: grim the dock region and the full DP-1 output into $DOCKQA."
  confirm "Run step 7?"
  if (( CONFIRMED )); then step7_shots; else record 7 skipped "owner declined"; fi

  summary
  say ""
  say "Done. Rollback at any time: bash tools/mac-parity-deploy.sh --rollback"
}

main
