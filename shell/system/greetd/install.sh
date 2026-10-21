#!/usr/bin/env bash
# install.sh -- installs the qml-rice ASCII greetd greeter. Run as root:
#
#   sudo bash <repo>/shell/system/greetd/install.sh [user]
#
# What this does:
#   1. Copies the shell repo (excluding .git, tools/.venv, test-*.qml,
#      render-*.qml) to /usr/share/qml-rice-greeter/shell -- greeter.qml
#      loads lock/AsciiLockSurface.qml from there at runtime.
#   2. NEVER copies FakeGreetdContext.qml or greeter-test.qml -- test mode
#      is physically absent from the installed tree, not just env-gated
#      (see greeter.qml's and FakeGreetdContext.qml's own headers for why
#      this is the stronger of the two options considered).
#   3. Snapshots the handful of JSON files Theme.qml/DeskSettings.qml read
#      from the target user's home (odyssey/settings.json, odyssey/palette.json,
#      qml-rice/desktop.json, qml-rice/palette.json fallback) into
#      /usr/share/qml-rice-greeter/{state,cache} -- greeter-launch.sh points
#      XDG_STATE_HOME/XDG_CACHE_HOME at these for the greeter's own process
#      only, so colours/fonts match the live lock screen WITHOUT the
#      `greeter` user ever reading the target user's home (mode 700, unreadable
#      to it anyway).
#   4. Installs greeter-launch.sh (this directory) to
#      /usr/share/qml-rice-greeter/greeter-launch.sh, root:root 0755.
#   5. chown -R root:root and chmod go-w the entire installed tree -- a
#      compromised target user account must not be able to modify anything the
#      login screen executes or loads (that would let it capture the next
#      login's password). World-READABLE (o+rX) so the unprivileged
#      `greeter` user can still load it.
#   6. Backs up /etc/greetd/config.toml, then rewrites ONLY its `command =`
#      line to point at the installed greeter-launch.sh. Never touches
#      /etc/greetd/quickshell-greeter/ (niri-greeter.kdl is reused as-is,
#      and shell.qml there is greeter-launch.sh's fallback target).
#
# Idempotent: safe to re-run. Each run makes a fresh timestamped backup of
# config.toml but only ever rewrites the `command` line, and file copies
# are plain overwrites (rsync --delete keeps the installed shell tree in
# sync with the source, including removals).
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
    echo "install.sh must be run as root (sudo)." >&2
    exit 1
fi

TARGET_USER="${1:-${SUDO_USER:-}}"
if [[ -z "${TARGET_USER}" ]]; then
    echo "error: no user specified. usage: sudo bash install.sh [user]" >&2
    echo "       (defaults to \$SUDO_USER if not provided)" >&2
    exit 1
fi
if [[ "${TARGET_USER}" == "root" ]]; then
    echo "error: install.sh must not be run for root." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_SRC="$(cd "${SCRIPT_DIR}/../.." && pwd)"

INSTALL_ROOT="/usr/share/qml-rice-greeter"
SHELL_DEST="${INSTALL_ROOT}/shell"
STATE_DEST="${INSTALL_ROOT}/state"
CACHE_DEST="${INSTALL_ROOT}/cache"
WRAPPER_DEST="${INSTALL_ROOT}/greeter-launch.sh"

GREETD_CONFIG="/etc/greetd/config.toml"
OLD_GREETER_DIR="/etc/greetd/quickshell-greeter"

# Resolve the target user's home via getent rather than $HOME/$SUDO_USER
# since this always runs as root via sudo.
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ -z "${TARGET_HOME}" ]]; then
    echo "error: could not resolve $TARGET_USER's home directory via getent." >&2
    exit 1
fi
SRC_STATE_HOME="${TARGET_HOME}/.local/state"
SRC_CACHE_HOME="${TARGET_HOME}/.cache"

echo "==> Source shell tree: ${SHELL_SRC}"
echo "==> Install root:      ${INSTALL_ROOT}"

if [[ ! -f "${SHELL_SRC}/shell.qml" ]]; then
    echo "error: ${SHELL_SRC}/shell.qml not found -- SCRIPT_DIR resolution is wrong." >&2
    exit 1
fi

# --- 1 & 2: copy the shell tree, excluding dev/test cruft and BOTH
# test-mode files (FakeGreetdContext.qml, greeter-test.qml) -- the
# "physically absent from production" guarantee. rsync is NOT installed on
# this system, so this uses plain tar (always present) piped between a
# tar-cf on the source and a tar-xf into a freshly emptied destination --
# the fresh `rm -rf` before extracting gives the same "delete anything no
# longer in source" idempotency rsync --delete would have given. -------
rm -rf "${SHELL_DEST}"
mkdir -p "${SHELL_DEST}"
tar -C "${SHELL_SRC}" \
    --exclude='.git' \
    --exclude='tools/.venv' \
    --exclude='test-*.qml' \
    --exclude='render-*.qml' \
    --exclude='system/greetd/FakeGreetdContext.qml' \
    --exclude='system/greetd/greeter-test.qml' \
    --exclude='system/greetd/install.sh' \
    --exclude='system/greetd/greeter-launch.sh' \
    --exclude='system/greetd/README.md' \
    -cf - . | tar -C "${SHELL_DEST}" -xf -

if [[ -f "${SHELL_DEST}/system/greetd/FakeGreetdContext.qml" ]] \
        || [[ -f "${SHELL_DEST}/system/greetd/greeter-test.qml" ]]; then
    echo "error: test-mode files leaked into the installed tree, aborting." >&2
    exit 1
fi
echo "==> Copied shell tree (test-mode files excluded, verified absent)"

# --- Substitute target user into the installed GreetdContext.qml. ---
sed -i "s/@GREETER_USER@/$TARGET_USER/g" "${SHELL_DEST}/system/greetd/GreetdContext.qml"
echo "==> Substituted target user '$TARGET_USER' into GreetdContext.qml"

# --- 3: snapshot runtime state Theme.qml/DeskSettings.qml read from
# the target user's home, into a root-owned location the `greeter` user can read. ---
mkdir -p "${STATE_DEST}/odyssey" "${STATE_DEST}/qml-rice" "${CACHE_DEST}/qml-rice"

copy_if_exists() {
    local src="$1" dest="$2"
    if [[ -f "$src" ]]; then
        cp -f "$src" "$dest"
        echo "==> Snapshotted $src -> $dest"
    else
        echo "==> (skip) $src does not exist yet, greeter will use defaults"
    fi
}

copy_if_exists "${SRC_STATE_HOME}/odyssey/settings.json" "${STATE_DEST}/odyssey/settings.json"
copy_if_exists "${SRC_STATE_HOME}/odyssey/palette.json" "${STATE_DEST}/odyssey/palette.json"
copy_if_exists "${SRC_STATE_HOME}/qml-rice/desktop.json" "${STATE_DEST}/qml-rice/desktop.json"
copy_if_exists "${SRC_CACHE_HOME}/qml-rice/palette.json" "${CACHE_DEST}/qml-rice/palette.json"

# --- 3b: greeter media (glass greeter). ---------------------------------
# The glass greeter plays the owner's current wallpaper itself and shows
# their avatar. The greeter user can't read the owner's home, so copy them
# into the install root, world-readable. A still wallpaper becomes
# wallpaper-still.png; a video becomes wallpaper.mp4 plus a first-frame
# still for the instant before playback starts.
# Reads go through the TARGET user (runuser), never root: the wallpaper
# path comes from a file that user controls, and copying it as root would
# let it name any root-readable file and land it world-readable here.
MEDIA_DEST="${INSTALL_ROOT}/media"
rm -rf "${MEDIA_DEST}"
mkdir -p "${MEDIA_DEST}"
as_user_cat() { runuser -u "$TARGET_USER" -- cat -- "$1"; }
CURRENT_WP="$(as_user_cat "${SRC_STATE_HOME}/odyssey/current-wallpaper" 2>/dev/null | head -n1 || true)"
if [[ -n "$CURRENT_WP" ]]; then
    case "${CURRENT_WP,,}" in
        *.mp4|*.webm|*.mkv|*.mov)
            if as_user_cat "$CURRENT_WP" > "${MEDIA_DEST}/wallpaper.mp4" 2>/dev/null; then
                # Decoding untrusted media is a parser attack surface, so
                # ffmpeg runs as the target user (never root), reading the
                # user's own file and writing the PNG to stdout.
                command -v ffmpeg >/dev/null && runuser -u "$TARGET_USER" -- \
                    ffmpeg -loglevel error -i "$CURRENT_WP" -frames:v 1 -f image2pipe -c:v png - \
                    > "${MEDIA_DEST}/wallpaper-still.png" 2>/dev/null \
                    || rm -f "${MEDIA_DEST}/wallpaper-still.png"
            else
                rm -f "${MEDIA_DEST}/wallpaper.mp4"
            fi ;;
        *)
            as_user_cat "$CURRENT_WP" > "${MEDIA_DEST}/wallpaper-still.png" 2>/dev/null \
                || rm -f "${MEDIA_DEST}/wallpaper-still.png" ;;
    esac
fi
as_user_cat "${TARGET_HOME}/.face" > "${MEDIA_DEST}/avatar" 2>/dev/null || rm -f "${MEDIA_DEST}/avatar"
chmod -R a+rX "${MEDIA_DEST}"
echo "==> Greeter media: $(ls "${MEDIA_DEST}" | tr '\n' ' ')"

# --- 4: install the wrapper. -------------------------------------------
install -m 0755 -o root -g root "${SCRIPT_DIR}/greeter-launch.sh" "${WRAPPER_DEST}"
echo "==> Installed wrapper: ${WRAPPER_DEST}"

# --- 5: lock down ownership/permissions -- root-owned, not writable by
# the target user, world-readable so the unprivileged `greeter` user can load it. ---
chown -R root:root "${INSTALL_ROOT}"
chmod -R go-w "${INSTALL_ROOT}"
find "${INSTALL_ROOT}" -type d -exec chmod a+rx {} +
find "${INSTALL_ROOT}" -type f -exec chmod a+r {} +
chmod 0755 "${WRAPPER_DEST}"
echo "==> chown/chmod: ${INSTALL_ROOT} is root-owned, world-readable, not writable by the target user"

# --- 6: back up and rewrite ONLY the command line in config.toml. ------
if [[ ! -f "${GREETD_CONFIG}" ]]; then
    echo "error: ${GREETD_CONFIG} not found." >&2
    exit 1
fi

BACKUP="${GREETD_CONFIG}.bak-$(date +%Y%m%d%H%M%S)"
cp -a "${GREETD_CONFIG}" "${BACKUP}"
echo "==> Backed up ${GREETD_CONFIG} -> ${BACKUP}"

if [[ ! -d "${OLD_GREETER_DIR}" ]]; then
    echo "error: ${OLD_GREETER_DIR} not found -- greeter-launch.sh's fallback" \
        "target would be missing. Refusing to install." >&2
    exit 1
fi

python3 - "$GREETD_CONFIG" "$WRAPPER_DEST" <<'PYEOF'
import re
import sys

config_path, wrapper_path = sys.argv[1], sys.argv[2]
with open(config_path, "r") as f:
    text = f.read()

new_line = f'command = "{wrapper_path}"'
pattern = re.compile(r'^command\s*=.*$', re.MULTILINE)
if pattern.search(text):
    text = pattern.sub(new_line, text, count=1)
else:
    raise SystemExit(f"error: no `command = ...` line found in {config_path}")

with open(config_path, "w") as f:
    f.write(text)
PYEOF

echo "==> Rewrote ${GREETD_CONFIG}'s command line to launch ${WRAPPER_DEST}"
echo
echo "==> Done. greetd will use the new greeter on next login/restart."
echo "==> Rollback command:"
echo "      sudo cp ${BACKUP} ${GREETD_CONFIG}"
