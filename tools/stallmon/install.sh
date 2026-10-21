#!/usr/bin/env bash
# Install and start the stall monitor as a systemd user service.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$unit_dir"
install -m 0644 "$here/stallmon.service" "$unit_dir/stallmon.service"
systemctl --user daemon-reload
systemctl --user enable --now stallmon.service
systemctl --user is-active stallmon.service
