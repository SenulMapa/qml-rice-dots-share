#!/usr/bin/env bash
# Validate the theme. Usage: check.sh [THEME_DIR]   (default ~/.local/share/icons/qml-rice-mac)
# Tests build into a temp dir:  check.sh --selftest
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
if [ "${1:-}" = "--selftest" ]; then
    T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
    python3 -I "$D/tests/test_safe_fetch.py"
    python3 -I "$D/scan.py" >/dev/null
    python3 -I "$D/build_theme.py" --offline --target "$T/qml-rice-mac" | tail -1
    exec python3 -I "$D/check_theme.py" "$T/qml-rice-mac"
fi
exec python3 -I "$D/check_theme.py" "${1:-$HOME/.local/share/icons/qml-rice-mac}"
