#!/usr/bin/env bash
# Remove macwm. Leaves ~/.local/state/qml-rice/macwm.json (remembered placement) in place.
set -euo pipefail
systemctl --user disable --now macwm.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/macwm.service" "$HOME/.local/bin/macwmctl"
rm -rf "$HOME/.local/share/qml-rice/macwm"
systemctl --user daemon-reload
echo "macwm removed"
