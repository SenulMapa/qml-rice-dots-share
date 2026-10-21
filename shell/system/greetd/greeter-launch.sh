#!/usr/bin/env bash
# greeter-launch.sh -- greetd `command` entry point (runs as user `greeter`).
#
# greetd's config.toml `command` field is shell-word-split and exec'd
# directly, NOT run through /bin/sh -c -- so it can only ever be one
# executable + fixed args. This script is that one executable: it launches
# the new qml-rice ASCII greeter (niri + quickshell), waits for a readiness
# MARKER FILE that greeter.qml itself only writes after AsciiLockSurface has
# actually rendered a frame (not a blind timeout on process start -- a
# black/hung greeter looks identical to a starting one from the outside),
# and falls back to the untouched previous greeter command
# (/etc/greetd/quickshell-greeter/{niri-greeter.kdl,shell.qml}, which
# install.sh NEVER modifies or deletes) if the marker never appears or the
# new greeter exits non-zero. Falls straight back to the old greeter for
# the rest of THIS boot if it has already fallen back twice (tracked in
# $XDG_RUNTIME_DIR, which is tmpfs and clears every boot) -- avoids
# hammering a broken new greeter across every VT-respawn.
#
# Overridable via env, purely so this script can be exercised standalone
# (see the test invocations in the greeter's own commit/report) without
# touching greetd or niri:
#   QMLRICE_NEW_CMD, QMLRICE_OLD_CMD  -- bash arrays via `declare -a` in the
#                                        environment is not portable, so
#                                        these are read as NUL-free strings
#                                        and split with `eval` ONLY when the
#                                        override env var is explicitly set
#                                        (never on the real installed path).
#   QMLRICE_READY_FILE                -- default $XDG_RUNTIME_DIR/qmlrice-greeter.ready
#   QMLRICE_READY_TIMEOUT             -- default 20 (seconds)
#   QMLRICE_RUNTIME_DIR               -- default $XDG_RUNTIME_DIR, falls back to /tmp
set -euo pipefail

runtime_dir="${QMLRICE_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}}"
ready_file="${QMLRICE_READY_FILE:-${runtime_dir}/qmlrice-greeter.ready}"
timeout_s="${QMLRICE_READY_TIMEOUT:-20}"
fallback_count_file="${runtime_dir}/qmlrice-greeter.fallback-count"

# Belt-and-suspenders: test mode must be structurally impossible in
# production (greeter.qml never even references this env var, and
# greeter-test.qml/FakeGreetdContext.qml are never installed -- see both
# files' headers), but strip it anyway in case something upstream leaked it
# into this process's environment.
unset QMLRICE_GREETER_TEST || true

log() {
    logger -t qmlrice-greeter -- "$1" || true
    echo "qmlrice-greeter: $1" >&2
}

read_fallback_count() {
    if [[ -f "$fallback_count_file" ]]; then
        cat "$fallback_count_file" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

bump_fallback_count() {
    local n
    n=$(read_fallback_count)
    n=$((n + 1))
    echo "$n" > "$fallback_count_file" 2>/dev/null || true
}

# The snapshot install.sh takes of Theme/DeskSettings runtime state (see
# install.sh's own header) -- pointed to via XDG_STATE_HOME/XDG_CACHE_HOME
# ONLY for the new greeter's own process environment (not exported into
# this script's environment), so the fallback path below is completely
# unaffected. Overridable so this script's own test invocations don't need
# a real installed snapshot on disk.
state_dir="${QMLRICE_STATE_DIR:-/usr/share/qml-rice-greeter/state}"
cache_dir="${QMLRICE_CACHE_DIR:-/usr/share/qml-rice-greeter/cache}"

default_new_cmd=(/usr/bin/niri --session
    --config /etc/greetd/quickshell-greeter/niri-greeter.kdl
    -- /usr/bin/quickshell -p /usr/share/qml-rice-greeter/shell/system/greetd/greeter.qml)
default_old_cmd=(/usr/bin/niri --session
    --config /etc/greetd/quickshell-greeter/niri-greeter.kdl
    -- /usr/bin/quickshell -p /etc/greetd/quickshell-greeter/shell.qml)

if [[ -n "${QMLRICE_NEW_CMD:-}" ]]; then
    eval "new_cmd=(${QMLRICE_NEW_CMD})"
else
    new_cmd=("${default_new_cmd[@]}")
fi
if [[ -n "${QMLRICE_OLD_CMD:-}" ]]; then
    eval "old_cmd=(${QMLRICE_OLD_CMD})"
else
    old_cmd=("${default_old_cmd[@]}")
fi

run_old_greeter() {
    local reason="$1"
    log "falling back to previous greeter: ${reason}"
    exec "${old_cmd[@]}"
}

existing_fallbacks=$(read_fallback_count)
if [[ "$existing_fallbacks" -ge 2 ]]; then
    run_old_greeter "already fell back ${existing_fallbacks} times this boot, skipping new greeter"
fi

rm -f -- "$ready_file"

XDG_STATE_HOME="$state_dir" XDG_CACHE_HOME="$cache_dir" "${new_cmd[@]}" &
new_pid=$!

waited=0
marker_seen=0
while (( waited < timeout_s )); do
    if [[ -f "$ready_file" ]]; then
        marker_seen=1
        break
    fi
    if ! kill -0 "$new_pid" 2>/dev/null; then
        # Process already exited before producing a marker.
        break
    fi
    sleep 1
    waited=$((waited + 1))
done

if [[ "$marker_seen" -eq 1 ]]; then
    log "new greeter reported ready after ${waited}s, handing off"
    # Now just wait for it like a normal foreground command would.
    set +e
    wait "$new_pid"
    exit_code=$?
    set -e
    if [[ "$exit_code" -ne 0 ]]; then
        bump_fallback_count
        run_old_greeter "new greeter exited with status ${exit_code} after having reported ready"
    fi
    exit "$exit_code"
fi

# No marker within the timeout (or the process died first). Kill it and
# fall back.
if kill -0 "$new_pid" 2>/dev/null; then
    kill "$new_pid" 2>/dev/null || true
    wait "$new_pid" 2>/dev/null || true
    bump_fallback_count
    run_old_greeter "no readiness marker within ${timeout_s}s"
else
    set +e
    wait "$new_pid"
    exit_code=$?
    set -e
    bump_fallback_count
    run_old_greeter "new greeter exited immediately with status ${exit_code}"
fi
