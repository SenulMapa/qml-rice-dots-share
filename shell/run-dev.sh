#!/usr/bin/env bash
# Run the shell against a sandboxed XDG root so it can never write to real
# user config. Wallpaper bootstrap stays off in dev: it starts awww and
# changes the desktop wallpaper, which is not something a dev run should do.
set -euo pipefail
cd "$(dirname "$0")"
SANDBOX="${TMPDIR:-/tmp}/qml-rice-dev"
mkdir -p "$SANDBOX"/{config,state,cache}
export XDG_CONFIG_HOME="$SANDBOX/config"
export XDG_STATE_HOME="$SANDBOX/state"
export XDG_CACHE_HOME="$SANDBOX/cache"
exec qs -p ./shell.qml "$@"
