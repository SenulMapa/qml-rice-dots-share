#!/usr/bin/env bash
# Install macwm as a user service: daemon -> ~/.local/share/qml-rice/macwm,
# CLI -> ~/.local/bin/macwmctl, unit -> ~/.config/systemd/user. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARE="$HOME/.local/share/qml-rice/macwm"
UNITS="$HOME/.config/systemd/user"

mkdir -p "$SHARE" "$HOME/.local/bin" "$UNITS"
install -m644 "$HERE/macwm.py" "$SHARE/macwm.py"
install -m755 "$HERE/macwmctl" "$HOME/.local/bin/macwmctl"
install -m644 "$HERE/macwm.service" "$UNITS/macwm.service"
systemctl --user daemon-reload
systemctl --user enable --now macwm.service
echo "macwm installed; status: systemctl --user status macwm"
