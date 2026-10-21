#!/usr/bin/env bash
# Stop, disable and remove the stall monitor user service.
set -euo pipefail
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
systemctl --user disable --now stallmon.service 2>/dev/null || true
rm -f "$unit_dir/stallmon.service"
systemctl --user daemon-reload
echo "stallmon removed (logs kept in ${XDG_STATE_HOME:-$HOME/.local/state}/qml-rice/)"
