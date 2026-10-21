#!/usr/bin/env bash
# End-to-end smoke test. Starts the shell, exercises every IPC surface a user
# can reach from a keybind, checks it is still alive, and reports resource use.
# Exits non-zero if anything fails, so it is usable in CI or a pre-commit hook.
set -uo pipefail
cd "$(dirname "$0")"
QS="qs -p ./shell.qml"
started=0
fail=0

if ! pgrep -f '^qs -p ./shell.qml' >/dev/null; then
  nohup $QS > /tmp/qml-rice-smoke.log 2>&1 &
  started=1
  sleep 8
fi
# Anchored with ^qs: an unanchored pattern also matches any shell whose
# command line CONTAINS the string -- including the one running this script
# -- so the RSS budget and survival checks were measuring a wrapper process
# (observed: "RSS 4 MB"). The budget check is only meaningful against qs.
pid=$(pgrep -f '^qs -p ./shell.qml' | head -1)
if [ -z "$pid" ]; then echo "FAIL: shell did not start"; exit 1; fi
echo "PASS  shell running (pid $pid)"

# audio increment is immediately followed by a matching decrement: this test
# runs against the user's REAL session, and an unpaired increment raised their
# volume by 3% on every run (observed climbing 75% -> 96%). A verification
# step must leave the machine exactly as it found it.
for t in "control-center toggle" "launcher toggle" "notifications toggle" \
         "clipboard toggle" "settings open" "session-page open" \
         "audio increment 3" "audio decrement 3" "settings wallpaper" \
         "settings dashboard" "settings media" "power cycle" \
         "control-center section wifi" "control-center close"; do
  # Unquoted $t on purpose: bash word-splits it into (target, function),
  # which is what `qs ipc call` expects. Note this script must stay bash --
  # the interactive shell here is zsh, which does NOT word-split unquoted
  # parameters, and a single-argument call fails with the misleading
  # "Function required to send message".
  r=$($QS ipc call $t 2>&1 | head -1)
  if [[ "$r" == *SUCCESS* ]]; then echo "PASS  ipc $t"
  else echo "FAIL  ipc $t -> $r"; fail=1; fi
  $QS ipc call ${t%% *} close >/dev/null 2>&1
done

sleep 1
if ! kill -0 "$pid" 2>/dev/null; then echo "FAIL  shell died during IPC"; exit 1; fi
echo "PASS  shell survived all IPC"

rss=$(awk '/^VmRSS/{printf "%.0f", $2/1024}' /proc/$pid/status)
a=$(awk '{print $14+$15}' /proc/$pid/stat); sleep 5; b=$(awk '{print $14+$15}' /proc/$pid/stat)
cpu=$(echo "scale=1; ($b-$a)/$(getconf CLK_TCK)/5*100" | bc)
echo "INFO  RSS ${rss} MB, CPU ${cpu}%"
[ "$rss" -lt 500 ] && echo "PASS  RSS under 500 MB budget" || { echo "FAIL  RSS over budget"; fail=1; }

[ "$started" = "1" ] && kill "$pid" 2>/dev/null
exit $fail
