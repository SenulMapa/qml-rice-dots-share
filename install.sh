#!/usr/bin/env bash
# qml-rice-dots installer -- Arch Linux only.
#
# Installs a Quickshell shell, a cleaned Hyprland Lua config, and a set of
# opt-in "dots/" modules (terminal, shell, fonts/theming) that together
# reproduce the qml-rice desktop look on a fresh machine. Backs up anything
# it would overwrite, and installs the `qml-rice` updater TUI.
#
# Usage: ./install.sh [--dry-run] [--yes] [--no-deps] [--all]
#                      [--modules m1,m2,...] [-h|--help]
#   --dry-run          Print every action without touching the filesystem or
#                       running pacman/paru/go/chsh/sudo. Safe to run
#                       repeatedly.
#   --yes              Don't ask for confirmation (assume yes to prompts).
#                       Without --modules/--all, this selects the default
#                       module set (everything except `sddm`).
#   --no-deps          Skip package installation (assume dependencies are
#                       present).
#   --all              Select every module, including `sddm`.
#   --modules m1,m2    Comma-separated module list; skips the interactive
#                       checklist. See MODULE list below for valid names.
set -euo pipefail

# --------------------------------------------------------------- modules --
# Order matters only for display. `sddm` needs sudo to write /etc and is
# excluded from the default set -- it's opt-in even with --yes.
ALL_MODULES=(hypr shell fonts fontconfig kitty zsh fastfetch gtk qt macapps macicons mactheme matugen thunar wallpapers webapps sddm)
DEFAULT_MODULES=(hypr shell fonts fontconfig kitty zsh fastfetch gtk qt macapps macicons mactheme matugen thunar wallpapers webapps)

module_desc() {
    case "$1" in
        hypr)       echo "Hyprland Lua config (compositor, binds, rules)" ;;
        shell)      echo "Quickshell shell (bar, launcher, control centre)" ;;
        fonts)      echo "every font family the shell/dots reference (vendored OFL faces + Nerd/Material Symbols packages)" ;;
        fontconfig) echo "macOS-like text rendering + system-ui/-apple-system aliases" ;;
        kitty)      echo "kitty terminal config + colour scheme" ;;
        zsh)        echo "zsh config, starship prompt, fzf/zoxide integration" ;;
        fastfetch)  echo "fastfetch config + ASCII logo, wired into zsh" ;;
        gtk)        echo "GTK 3/4 theme, icon theme, cursor theme, fonts" ;;
        qt)         echo "qt5ct/qt6ct + Kvantum so Qt apps match GTK" ;;
        macapps)    echo "native-Wayland Slack/Discord/Spotify flags, macOS cursor theme, one Qt/GTK icon+font set (tools/mac-apps)" ;;
        matugen)    echo "matugen templates: wallpaper colours -> terminal/GTK/Hyprland borders" ;;
        thunar)     echo "Thunar file manager + generic bookmarks" ;;
        wallpapers) echo "fallback wallpaper + Pictures/wallpapers seeding" ;;
        webapps)    echo "web-app overlays: Gemini as a floating Brave app window on a global key (needs brave-bin)" ;;
        macicons)   echo "qml-rice-mac macOS-style icon theme built from tools/mac-icons/picks.json (no downloads needed)" ;;
        mactheme)   echo "WhiteSur dark macOS look for GTK3/GTK4/libadwaita + Qt/Kvantum from pinned prebuilt files (tools/mac-theme; downloads, sha256-verified)" ;;
        sddm)       echo "SDDM login theme (writes /etc/sddm.conf.d, needs sudo)" ;;
        *)          echo "" ;;
    esac
}

is_valid_module() {
    local m
    for m in "${ALL_MODULES[@]}"; do [ "$m" = "$1" ] && return 0; done
    return 1
}

has_module() {
    local m
    for m in "${SELECTED_MODULES[@]}"; do [ "$m" = "$1" ] && return 0; done
    return 1
}

# ---------------------------------------------------------------- args ----
DRY_RUN=0
ASSUME_YES=0
NO_DEPS=0
MODULES_ARG=""
ALL_FLAG=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --yes) ASSUME_YES=1 ;;
        --no-deps) NO_DEPS=1 ;;
        --all) ALL_FLAG=1 ;;
        --modules=*) MODULES_ARG="${arg#--modules=}" ;;
        --modules)
            echo "--modules requires a value, e.g. --modules=kitty,zsh" >&2
            exit 1
            ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

HERE="$(cd "$(dirname "$0")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
HYPR_CFG="$CFG/hypr"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALL_DIR="$DATA/qml-rice"
SHELL_DIR="$INSTALL_DIR/shell"
FONT_DIR="$DATA/fonts/qml-rice"
BIN_DIR="$HOME/.local/bin"
PICTURES_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}"
STAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '  %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
act()  {
    # act <description> -- <command...>
    local desc="$1"; shift
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  [dry-run] %s\n' "$desc"
        return 0
    fi
    say "$desc"
    "$@"
}

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ "$DRY_RUN" -eq 1 ] && return 0
    read -r -p "  $1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ------------------------------------------------------------- safety -----
step "Preflight checks"

if [ "$(id -u)" -eq 0 ]; then
    echo "Do not run this installer as root." >&2
    exit 1
fi

if [ ! -f /etc/arch-release ] && ! grep -qi '^ID=arch' /etc/os-release 2>/dev/null && ! grep -qi 'ID_LIKE=.*arch' /etc/os-release 2>/dev/null; then
    echo "This installer only supports Arch Linux (and derivatives)." >&2
    exit 1
fi
say "Arch Linux detected, running as $(whoami)"
[ "$DRY_RUN" -eq 1 ] && say "DRY RUN: no files will be written, no packages/sudo/chsh invoked"

# ------------------------------------------------------- module select ----
step "Modules"

declare -a SELECTED_MODULES=()
if [ -n "$MODULES_ARG" ]; then
    IFS=',' read -r -a REQUESTED <<< "$MODULES_ARG"
    for m in "${REQUESTED[@]}"; do
        if ! is_valid_module "$m"; then
            echo "Unknown module: $m (valid: ${ALL_MODULES[*]})" >&2
            exit 1
        fi
        SELECTED_MODULES+=("$m")
    done
elif [ "$ALL_FLAG" -eq 1 ]; then
    SELECTED_MODULES=("${ALL_MODULES[@]}")
elif [ "$ASSUME_YES" -eq 1 ] || [ "$DRY_RUN" -eq 1 ] || [ ! -t 0 ]; then
    SELECTED_MODULES=("${DEFAULT_MODULES[@]}")
else
    echo "  Pick modules to install (space-separated numbers, or 'all', or Enter for the default set):"
    i=1
    for m in "${ALL_MODULES[@]}"; do
        default_mark=""
        for d in "${DEFAULT_MODULES[@]}"; do [ "$d" = "$m" ] && default_mark=" (default)"; done
        printf '    %2d) %-11s -- %s%s\n' "$i" "$m" "$(module_desc "$m")" "$default_mark"
        i=$((i + 1))
    done
    read -r -p "  > " picks
    if [ -z "$picks" ]; then
        SELECTED_MODULES=("${DEFAULT_MODULES[@]}")
    elif [ "$picks" = "all" ]; then
        SELECTED_MODULES=("${ALL_MODULES[@]}")
    else
        # shellcheck disable=SC2086 # intentional word-splitting of a
        # space-separated list of numbers the user typed.
        for n in $picks; do
            if ! [[ "$n" =~ ^[0-9]+$ ]]; then
                echo "Ignoring invalid selection: $n" >&2
                continue
            fi
            if [ "$n" -ge 1 ] && [ "$n" -le "${#ALL_MODULES[@]}" ]; then
                SELECTED_MODULES+=("${ALL_MODULES[$((n - 1))]}")
            else
                echo "Ignoring invalid selection: $n" >&2
            fi
        done
    fi
fi
say "Selected: ${SELECTED_MODULES[*]}"
if has_module sddm; then
    say "sddm module selected -- this writes /etc/sddm.conf.d and needs sudo"
fi

# ------------------------------------------------------------ packages ----
if [ "$NO_DEPS" -eq 1 ]; then
    step "Skipping dependency installation (--no-deps)"
else
    step "Dependencies"

    AUR_HELPER=""
    if command -v paru >/dev/null 2>&1; then
        AUR_HELPER="paru"
    elif command -v yay >/dev/null 2>&1; then
        AUR_HELPER="yay"
    fi

    if [ -z "$AUR_HELPER" ]; then
        say "No AUR helper found (checked paru, yay)."
        if confirm "Install paru from the AUR now?"; then
            # shellcheck disable=SC2016 # intentional: vars expand inside the bash -c subshell, not here
            act "clone and build paru into a temp dir, then 'makepkg -si'" \
                bash -c '
                    set -e
                    tmp="$(mktemp -d)"
                    git clone --depth=1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
                    (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
                    rm -rf "$tmp"
                '
            AUR_HELPER="paru"
        else
            say "Skipping AUR packages; install them yourself from packages/aur.txt"
        fi
    else
        say "Using AUR helper: $AUR_HELPER"
    fi

    ARCH_PKGS_FILES=("$HERE/packages/arch.txt")
    AUR_PKGS_FILES=("$HERE/packages/aur.txt")
    for m in "${SELECTED_MODULES[@]}"; do
        [ -f "$HERE/packages/modules/$m.arch.txt" ] && ARCH_PKGS_FILES+=("$HERE/packages/modules/$m.arch.txt")
        [ -f "$HERE/packages/modules/$m.aur.txt" ] && AUR_PKGS_FILES+=("$HERE/packages/modules/$m.aur.txt")
    done

    mapfile -t ARCH_PKGS < <(grep -hvE '^\s*(#|$)' "${ARCH_PKGS_FILES[@]}" | sort -u)
    ARCH_PKGS_REL=("${ARCH_PKGS_FILES[@]/#"$HERE"\//}")
    say "${#ARCH_PKGS[@]} package(s) from: ${ARCH_PKGS_REL[*]}"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  [dry-run] would run: sudo pacman -S --needed %s\n' "${ARCH_PKGS[*]}"
    else
        sudo pacman -S --needed --noconfirm "${ARCH_PKGS[@]}"
    fi

    if [ -n "$AUR_HELPER" ]; then
        mapfile -t AUR_PKGS < <(grep -hvE '^\s*(#|$)' "${AUR_PKGS_FILES[@]}" | sort -u)
        AUR_PKGS_REL=("${AUR_PKGS_FILES[@]/#"$HERE"\//}")
        say "${#AUR_PKGS[@]} package(s) from: ${AUR_PKGS_REL[*]}"
        if [ "$DRY_RUN" -eq 1 ]; then
            printf '  [dry-run] would run: %s -S --needed %s\n' "$AUR_HELPER" "${AUR_PKGS[*]}"
        else
            "$AUR_HELPER" -S --needed --noconfirm "${AUR_PKGS[@]}"
        fi
    fi
fi

# -------------------------------------------------------------- backup ----
step "Backing up existing config"

if has_module hypr && [ -d "$HYPR_CFG" ] && [ ! -L "$HYPR_CFG" ]; then
    BACKUP="$CFG/hypr.backup-$STAMP"
    act "back up $HYPR_CFG -> $BACKUP" cp -a "$HYPR_CFG" "$BACKUP"
else
    say "no existing $HYPR_CFG to back up"
fi

# ------------------------------------------------------- install clone ----
step "Install location: $INSTALL_DIR"

if [ "$HERE" = "$INSTALL_DIR" ]; then
    say "already running from $INSTALL_DIR"
elif [ -d "$INSTALL_DIR/.git" ]; then
    say "$INSTALL_DIR already exists; leaving it (use 'qml-rice update' to update it)"
else
    ORIGIN="$(git -C "$HERE" remote get-url origin 2>/dev/null || true)"
    SRC="${ORIGIN:-$HERE}"
    act "git clone $SRC -> $INSTALL_DIR" mkdir -p "$(dirname "$INSTALL_DIR")"
    act "git clone $SRC -> $INSTALL_DIR" git clone "$SRC" "$INSTALL_DIR"
fi
REPO="$INSTALL_DIR"
[ "$DRY_RUN" -eq 1 ] && [ ! -d "$INSTALL_DIR" ] && REPO="$HERE"

# --------------------------------------------------- generic dots deploy --
# Mirrors dots/<module>/ onto $HOME, backing up any existing file whose
# content differs from what we're about to install. Used by the modules
# that are plain file trees (kitty, fastfetch, gtk, qt, matugen); zsh,
# thunar, wallpapers and sddm have their own sections below because they
# need more than a file copy.
deploy_dots_module() {
    local mod="$1" src="$REPO/dots/$1"
    [ -d "$src" ] || { say "dots/$mod not present in repo, skipping"; return 0; }
    while IFS= read -r -d '' file; do
        local rel="${file#"$src"/}"
        local target="$HOME/$rel"
        if [ -e "$target" ] && ! cmp -s "$file" "$target"; then
            act "back up $target -> $target.bak-$STAMP" cp -a "$target" "$target.bak-$STAMP"
        fi
        act "install $rel" install -m644 -D "$file" "$target"
    done < <(find "$src" -type f -print0)
}

# ------------------------------------------------------------- hypr/ ------
if has_module hypr; then
    step "Hyprland config -> $HYPR_CFG"

    act "mkdir -p $HYPR_CFG" mkdir -p "$HYPR_CFG"

    # Managed files: always refreshed from the repo (already backed up above).
    for f in hyprland.lua hypridle.conf; do
        act "install $f" install -m644 -D "$REPO/hypr/$f" "$HYPR_CFG/$f"
    done
    act "sync hyprland/ (managed)" bash -c "mkdir -p '$HYPR_CFG/hyprland' && cp -a '$REPO/hypr/hyprland/.' '$HYPR_CFG/hyprland/'"

    # User-owned / generated files: only seed if missing, never clobber.
    for f in monitors.lua hyprlock.conf; do
        if [ -e "$HYPR_CFG/$f" ]; then
            say "keep existing $f"
        else
            act "seed $f" install -m644 -D "$REPO/hypr/$f" "$HYPR_CFG/$f"
        fi
    done
    if [ -e "$HYPR_CFG/hyprlock/colors.conf" ]; then
        say "keep existing hyprlock/colors.conf"
    else
        act "seed hyprlock/colors.conf" install -m644 -D "$REPO/hypr/hyprlock/colors.conf" "$HYPR_CFG/hyprlock/colors.conf"
    fi

    # custom/ overrides: seed each *.example as *.lua only if not already present.
    act "mkdir -p $HYPR_CFG/custom/scripts" mkdir -p "$HYPR_CFG/custom/scripts"
    for ex in "$REPO"/hypr/custom/*.lua.example; do
        base="$(basename "$ex" .example)"
        if [ -e "$HYPR_CFG/custom/$base" ]; then
            say "keep existing custom/$base"
        else
            act "seed custom/$base" install -m644 -D "$ex" "$HYPR_CFG/custom/$base"
        fi
    done
    act "sync custom/scripts" bash -c "cp -a '$REPO/hypr/custom/scripts/.' '$HYPR_CFG/custom/scripts/'"
else
    step "hypr module not selected, skipping Hyprland config"
fi

# --------------------------------------------------------------- fonts ----
# Vendored OFL faces this repo ships directly (fonts/<Family>/*.ttf --
# Bitcount Single, Fraunces, Instrument Serif, Newsreader; see README's
# "Fonts" section for sources/licences). Gamja Flower, Geist and Geist Mono
# come from AUR (packages/modules/fonts.aur.txt) and Nerd Font / Material
# Symbols glyphs from the official repos (packages/modules/fonts.arch.txt).
if has_module fonts; then
    step "Fonts -> $FONT_DIR"
    if [ -d "$HERE/fonts" ]; then
        act "mkdir -p $FONT_DIR" mkdir -p "$FONT_DIR"
        act "copy vendored fonts" bash -c "find '$HERE/fonts' -type f \( -iname '*.ttf' -o -iname '*.otf' \) -exec cp -f {} '$FONT_DIR/' \;"
        act "fc-cache -f $FONT_DIR" bash -c "fc-cache -f '$FONT_DIR' >/dev/null 2>&1 || true"
    else
        say "no fonts/ directory in repo, skipping vendored fonts"
    fi
    act "fetch SF Pro (Apple; Inter fallback if unavailable)" bash -c "bash '$HERE/tools/mac-text/fetch-sf-pro.sh' || true"
else
    step "fonts module not selected, skipping vendored + Nerd/Material Symbols fonts"
fi

# ---------------------------------------------------------- fontconfig -----
if has_module fontconfig; then
    step "fontconfig drop-in -> ~/.config/fontconfig/conf.d"
    deploy_dots_module fontconfig
    act "fc-cache" bash -c "fc-cache -f >/dev/null 2>&1 || true"
fi

# Also pick up shell/assets/fonts once shell/ is vendored into this repo, in
# case it ever carries a face this module doesn't (belt and suspenders; the
# copy above already covers Bitcount/Fraunces/Instrument Serif/Newsreader).
if has_module shell && [ -d "$SHELL_DIR/assets/fonts" ]; then
    step "Shell-bundled fonts -> $FONT_DIR"
    act "mkdir -p $FONT_DIR" mkdir -p "$FONT_DIR"
    act "copy shell-bundled fonts" bash -c "cp -f '$SHELL_DIR'/assets/fonts/*.ttf '$FONT_DIR/' 2>/dev/null || true"
    act "fc-cache -f $FONT_DIR" bash -c "fc-cache -f '$FONT_DIR' >/dev/null 2>&1 || true"
fi

# ----------------------------------------------------------- keybinds -----
if has_module hypr; then
    step "qml-rice keybinds -> $HYPR_CFG/qml-rice-binds.lua"
    BINDS_CONTENT='-- qml-rice keybinds (managed by install.sh; re-run it to refresh).
-- Delete this file to remove them; hyprland.lua loads it conditionally.
-- Absolute path: the Hyprland exec PATH usually lacks ~/.local/bin, so a bare
-- `qml-rice` fails with "command not found" and the bind silently does nothing.
local qr = function(cmd) return hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/qml-rice ipc " .. cmd) end

hl.bind("SUPER + SHIFT + A",      qr("control-center toggle"), { description = "qml-rice: Control centre" })
hl.bind("SUPER + SHIFT + Space",  qr("launcher toggle"),       { description = "qml-rice: App launcher" })
hl.bind("SUPER + CTRL + N",       qr("notifications toggle"),  { description = "qml-rice: Notifications" })
hl.bind("SUPER + SHIFT + V",      qr("clipboard toggle"),      { description = "qml-rice: Clipboard history" })
hl.bind("SUPER + SHIFT + P",      qr("session-page open"),     { description = "qml-rice: Power menu" })
hl.bind("SUPER + SHIFT + Comma",  qr("settings open"),         { description = "qml-rice: Settings" })
hl.bind("SUPER + W",              qr("insights wallpaperToggle"), { description = "qml-rice: Wallpaper picker" })
hl.bind("SUPER + SHIFT + W",      qr("settings wallpaper"),    { description = "qml-rice: Wallpapers" })
hl.bind("ALT + Tab",         qr("switcher next"),   {description = "qml-rice: Switch apps"})
hl.bind("ALT + SHIFT + Tab", qr("switcher prev"),   {description = "qml-rice: Switch apps (back)"})
hl.bind("ALT + Escape",      qr("switcher cancel"), {description = "qml-rice: Cancel app switch"})
hl.bind("ALT_L", qr("switcher commit"), { ignore_mods = true, transparent = true, release = true, description = "qml-rice: Switch apps (release)" })

hl.bind("XF86AudioRaiseVolume", qr("audio increment 3"), { locked = true, repeating = true, description = "qml-rice: Volume up" })
hl.bind("XF86AudioLowerVolume", qr("audio decrement 3"), { locked = true, repeating = true, description = "qml-rice: Volume down" })
hl.bind("XF86AudioMute",        qr("audio mute"),        { locked = true, description = "qml-rice: Mute" })
'
    if [ "$DRY_RUN" -eq 1 ]; then
        say "[dry-run] would write $HYPR_CFG/qml-rice-binds.lua"
    else
        printf '%s' "$BINDS_CONTENT" > "$HYPR_CFG/qml-rice-binds.lua"
        say "wrote $HYPR_CFG/qml-rice-binds.lua"
    fi
fi

# -------------------------------------------------------------- kitty -----
if has_module kitty; then
    step "kitty -> ~/.config/kitty"
    deploy_dots_module kitty
fi

# ---------------------------------------------------------- fastfetch -----
if has_module fastfetch; then
    step "fastfetch -> ~/.config/fastfetch"
    deploy_dots_module fastfetch
fi

# ---------------------------------------------------------- webapps -----
# Layer 6: web-app overlays generated from tools/mac-webapps/webapps.json.
# The Hyprland rules live in hypr/hyprland/webapps.lua (copied by the hypr
# module and loaded from hyprland.lua only when present).
if has_module webapps; then
    step "web-app launchers -> ~/.local/bin, ~/.local/share/applications"
    if [ -d "$REPO/dots/webapps" ]; then
        while IFS= read -r -d '' file; do
            rel="${file#"$REPO/dots/webapps"/}"
            target="$HOME/$rel"
            mode=644
            case "$rel" in .local/bin/*) mode=755 ;; esac
            if [ -e "$target" ] && ! cmp -s "$file" "$target"; then
                act "back up $target -> $target.bak-$STAMP" cp -a "$target" "$target.bak-$STAMP"
            fi
            act "install $rel" install -m "$mode" -D "$file" "$target"
        done < <(find "$REPO/dots/webapps" -type f -print0)
    else
        say "dots/webapps not present in repo, skipping"
    fi
else
    step "webapps module not selected, skipping web-app launchers"
fi

# ------------------------------------------------------------------ gtk ---
if has_module gtk; then
    step "GTK theme/icons/cursor -> ~/.config/gtk-{3,4}.0"
    deploy_dots_module gtk
    if command -v gsettings >/dev/null 2>&1; then
        act "gsettings: gtk-theme"    gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"
        act "gsettings: icon-theme"   gsettings set org.gnome.desktop.interface icon-theme "Papirus-Dark"
        act "gsettings: cursor-theme" gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Modern-Classic"
        act "gsettings: font-name"    gsettings set org.gnome.desktop.interface font-name "system-ui 11"
        act "gsettings: font-antialiasing" gsettings set org.gnome.desktop.interface font-antialiasing "grayscale"
        act "gsettings: font-hinting"      gsettings set org.gnome.desktop.interface font-hinting "slight"
        act "gsettings: monospace-font"    gsettings set org.gnome.desktop.interface monospace-font-name "JetBrains Mono 11"
        act "gsettings: color-scheme" gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    else
        say "gsettings not found (needs a dconf/gsettings-schemas provider); settings.ini alone still applies to GTK apps"
    fi
fi

# ------------------------------------------------------------------- qt ---
if has_module qt; then
    step "Qt theming -> ~/.config/qt5ct, qt6ct, Kvantum"
    deploy_dots_module qt
    if command -v kwriteconfig6 >/dev/null 2>&1; then
        act "kdeglobals: font"     kwriteconfig6 --file kdeglobals --group General --key font     "system-ui,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
        act "kdeglobals: menuFont" kwriteconfig6 --file kdeglobals --group General --key menuFont "system-ui,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    fi
fi

# ------------------------------------------------------------ macapps ---
# Repo copies of the flag files and desktop overrides, then tools/mac-apps/apply.sh
# to merge the same settings into whatever is already on disk (backed up first).
if has_module macapps; then
    step "mac-apps: Electron Wayland flags, macOS cursor, consistent Qt/GTK"
    deploy_dots_module macapps
    act "apply mac-apps (targeted, backed up)" bash "$REPO/tools/mac-apps/apply.sh"
fi

# ------------------------------------------------------------- macicons ---
if has_module macicons; then
    step "macOS-style icon theme -> ~/.local/share/icons/qml-rice-mac"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  [dry-run] would run: %s/tools/mac-icons/apply.sh\n' "$REPO"
    elif [ -x "$REPO/tools/mac-icons/apply.sh" ]; then
        "$REPO/tools/mac-icons/apply.sh" || say "macicons: apply.sh failed (needs python-pillow + librsvg); theme not applied"
    fi
fi

# ------------------------------------------------------------- mactheme ---
if has_module mactheme; then
    step "macOS (WhiteSur dark) GTK + Qt theme -> ~/.themes, ~/.config/gtk-4.0, ~/.config/Kvantum"
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '  [dry-run] would run: %s/tools/mac-theme/apply.sh\n' "$REPO"
    elif [ -x "$REPO/tools/mac-theme/apply.sh" ]; then
        "$REPO/tools/mac-theme/apply.sh" || say "mactheme: apply.sh failed (needs network + glib2 gresource); theme not applied"
    fi
fi

# -------------------------------------------------------------- matugen ---
if has_module matugen; then
    step "matugen templates -> ~/.config/matugen"
    deploy_dots_module matugen
fi

# --------------------------------------------------------------- thunar ---
if has_module thunar; then
    step "Thunar bookmarks -> ~/.config/gtk-3.0/bookmarks"
    TEMPLATE="$REPO/dots/thunar/.config/gtk-3.0/bookmarks.template"
    TARGET="$HOME/.config/gtk-3.0/bookmarks"
    if [ -f "$TEMPLATE" ]; then
        RENDERED="$(sed "s#{{HOME}}#$HOME#g" "$TEMPLATE")"
        if [ -e "$TARGET" ] && [ "$(cat "$TARGET" 2>/dev/null || true)" != "$RENDERED" ]; then
            act "back up $TARGET -> $TARGET.bak-$STAMP" cp -a "$TARGET" "$TARGET.bak-$STAMP"
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            say "[dry-run] would write $TARGET"
        else
            mkdir -p "$(dirname "$TARGET")"
            printf '%s\n' "$RENDERED" > "$TARGET"
            say "wrote $TARGET"
        fi
    fi
fi

# ------------------------------------------------------------ wallpapers --
if has_module wallpapers; then
    step "Wallpapers -> $PICTURES_DIR/wallpapers"
    WP_DIR="$PICTURES_DIR/wallpapers"
    act "mkdir -p $WP_DIR" mkdir -p "$WP_DIR"
    if [ "$DRY_RUN" -eq 0 ] && [ -z "$(find "$WP_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print -quit 2>/dev/null)" ]; then
        FALLBACK="$WP_DIR/fallback-gradient.png"
        act "generate fallback wallpaper -> $FALLBACK" "$REPO/scripts/generate-fallback-wallpaper.sh" "$FALLBACK"
        if has_module matugen && command -v matugen >/dev/null 2>&1; then
            act "seed matugen colours from fallback wallpaper" matugen image "$FALLBACK"
        fi
    elif [ "$DRY_RUN" -eq 1 ]; then
        say "[dry-run] would generate a fallback wallpaper into $WP_DIR if it's empty, then run matugen against it"
    else
        say "$WP_DIR already has wallpapers, leaving it alone"
    fi
    say "add your own wallpapers to $WP_DIR (see wallpapers/README.md in the repo)"
fi

# ------------------------------------------------------------------ zsh ---
if has_module zsh; then
    step "zsh -> ~/.zshrc, ~/.config/starship.toml"
    deploy_dots_module zsh

    CURRENT_SHELL="$(getent passwd "$(whoami)" 2>/dev/null | cut -d: -f7 || echo "$SHELL")"
    if command -v zsh >/dev/null 2>&1 && [ "$(basename "$CURRENT_SHELL")" != "zsh" ]; then
        if confirm "Change your login shell to zsh now (chsh, no sudo)?"; then
            act "chsh -s \$(command -v zsh)" chsh -s "$(command -v zsh)"
        else
            say "leaving login shell as $CURRENT_SHELL; change later with: chsh -s \$(command -v zsh)"
        fi
    else
        say "login shell is already zsh (or zsh isn't installed yet)"
    fi
fi

# ----------------------------------------------------------------- sddm ---
if has_module sddm; then
    step "SDDM theme -> /etc/sddm.conf.d (sudo)"
    if confirm "Write /etc/sddm.conf.d/qml-rice-theme.conf with sudo? This changes your login screen."; then
        SDDM_TARGET="/etc/sddm.conf.d/qml-rice-theme.conf"
        if [ "$DRY_RUN" -eq 1 ]; then
            say "[dry-run] would sudo-backup $SDDM_TARGET (if present) and install $REPO/dots/sddm/theme.conf -> $SDDM_TARGET"
        else
            if [ -f "$SDDM_TARGET" ]; then
                sudo cp -a "$SDDM_TARGET" "$SDDM_TARGET.bak-$STAMP"
                say "backed up $SDDM_TARGET -> $SDDM_TARGET.bak-$STAMP"
            fi
            sudo install -m644 -D "$REPO/dots/sddm/theme.conf" "$SDDM_TARGET"
            say "wrote $SDDM_TARGET (theme: ltmnight, from the ltmnight-sddm-theme AUR package)"
        fi
    else
        say "skipped SDDM theme; the package (if installed) is unused until you set Current= in /etc/sddm.conf.d"
    fi
fi

# ------------------------------------------------------------- tui/go -----
step "qml-rice TUI"
if command -v go >/dev/null 2>&1; then
    act "mkdir -p $BIN_DIR" mkdir -p "$BIN_DIR"
    if [ "$DRY_RUN" -eq 1 ]; then
        say "[dry-run] would run: go build -o $BIN_DIR/qml-rice ./cmd/qml-rice (in $REPO/tui)"
    else
        (cd "$REPO/tui" && go build -o "$BIN_DIR/qml-rice" ./cmd/qml-rice)
        say "built $BIN_DIR/qml-rice"
    fi
else
    say "WARNING: 'go' not found (pacman -Q go: $(pacman -Q go 2>&1 || echo 'not installed'))."
    say "Install go and re-run, or build tui/ manually: (cd tui && go build -o ~/.local/bin/qml-rice ./cmd/qml-rice)"
fi

# ------------------------------------------------------------ finish ------
step "Done"
echo
echo "Modules installed : ${SELECTED_MODULES[*]}"
echo "Shell install dir : $SHELL_DIR"
echo "Hyprland config   : $HYPR_CFG (backup: $CFG/hypr.backup-$STAMP if one was made)"
echo "Updater           : qml-rice   (run it for the interactive TUI)"
echo "Non-interactive   : qml-rice status | qml-rice doctor | qml-rice update --yes"
echo
echo "Reload Hyprland (hyprctl reload) or log out/in to pick up the new config."
echo "Uninstall with: $HERE/uninstall.sh"
