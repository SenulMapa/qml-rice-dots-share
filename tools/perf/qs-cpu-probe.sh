#!/usr/bin/env bash
# qs-cpu-probe.sh [seconds=60]
#
# Read-only idle CPU probe for the live Quickshell shell (`qs -p ./shell.qml`).
# Samples /proc/<pid>/task/*/stat utime+stime deltas. Discards the first 10 s
# (warm-up), then measures over the requested window.
#
# Prints:
#   qs_cpu_pct=<float>          whole-process CPU, % of one core
#   thread <tid> <comm> <pct>   per-thread breakdown (sorted, largest first)
# Exit: 0 if qs_cpu_pct < QS_CPU_BUDGET (default 2.0), 1 otherwise,
#       2 if the shell is not running.
set -u

DUR="${1:-60}"
BUDGET="${QS_CPU_BUDGET:-2.0}"
WARM=10

PID="$(pgrep -f '^qs -p ./shell.qml' | head -n1)"
if [ -z "$PID" ]; then
  echo "qs_cpu_pct=NA (no 'qs -p ./shell.qml' process found)" >&2
  exit 2
fi
CLK="$(getconf CLK_TCK)"

# Emit "<tid> <comm> <utime+stime ticks>" for every live thread of $PID.
snap() {
  local s line tid comm rest f
  for s in /proc/"$PID"/task/*/stat; do
    [ -r "$s" ] || continue
    read -r line < "$s" 2>/dev/null || continue
    tid="${s#/proc/$PID/task/}"; tid="${tid%/stat}"
    comm="${line#*(}"; comm="${comm%) *}"
    rest="${line##*) }"
    read -ra f <<< "$rest"
    # rest[0] is field 3 (state); utime is field 14 -> index 11, stime -> 12.
    echo "$tid $comm $(( f[11] + f[12] ))"
  done
}

sleep "$WARM"
A="$(mktemp)"; B="$(mktemp)"
trap 'rm -f "$A" "$B"' EXIT

t0="$(date +%s.%N)"
snap > "$A"
sleep "$DUR"
snap > "$B"
t1="$(date +%s.%N)"

if ! kill -0 "$PID" 2>/dev/null; then
  echo "qs_cpu_pct=NA (shell pid $PID exited during sample)" >&2
  exit 2
fi

ELAPSED="$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.3f", b-a}')"

# Join the two snapshots by tid; threads that vanished mid-window are skipped.
awk -v clk="$CLK" -v el="$ELAPSED" -v budget="$BUDGET" '
  FNR==NR { before[$1]=$3; next }
  ($1 in before) {
    d = $3 - before[$1]
    if (d < 0) d = 0
    pct = 100.0 * d / (clk * el)
    total += d
    comm[$1] = $2
    tp[$1] = pct
  }
  END {
    for (t in tp) printf "thread %s %.2f %s\n", t, tp[t], comm[t] | "sort -k3 -gr"
    close("sort -k3 -gr")
    qs = 100.0 * total / (clk * el)
    printf "qs_cpu_pct=%.2f\n", qs
    printf "budget=%s window_s=%s\n", budget, el > "/dev/stderr"
    exit (qs < budget) ? 0 : 1
  }
' "$A" "$B"
RC=$?
exit "$RC"
