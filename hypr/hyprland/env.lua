local home_dir = os.getenv("HOME")

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("FREETYPE_PROPERTIES", "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0")

-- Applications
local xdg_data_dirs_old = os.getenv("XDG_DATA_DIRS") or ""
hl.env("XDG_DATA_DIRS", home_dir .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share:" .. xdg_data_dirs_old)

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- Virtual environment used by qml-rice's helper scripts (matugen, cava, etc.)
hl.env("QML_RICE_VIRTUAL_ENV", home_dir .. "/.local/state/quickshell/.venv")

-- >>> mac-apps cursor (tools/mac-apps/apply.sh) >>>
hl.env("XCURSOR_THEME", "macOS")
hl.env("XCURSOR_SIZE", "20")
-- <<< mac-apps cursor <<<
