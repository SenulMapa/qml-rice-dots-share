-- put former exec-once commands inside the func and former exec commands outside
hl.on("hyprland.start", function ()

    -- Wallpaper first: awww-daemon restores each output's last image from its
    -- cache, so there's no gray gap before the shell starts. The shell's
    -- wallpaperctl bootstrap finds this daemon (same namespace) and reuses it.
    hl.exec_cmd("awww-daemon --namespace qml-rice --quiet")

    hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")

    -- nwg-displays live-apply watcher: makes its "Apply" button take effect
    -- immediately (a Lua config reload does not re-apply monitor rules to
    -- outputs that are already connected).
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/nwg-monitor-apply.sh")

    -- qml-rice shell, started from its install directory so the process line
    -- is exactly `qs -p ./shell.qml`, which is what its restart tooling and
    -- keybinds match against.
    hl.exec_cmd("cd " .. (os.getenv("QML_RICE_HOME") or "$HOME/.local/share/qml-rice/shell") .. " && qs -p ./shell.qml")

    -- Core components (authentication, lock screen, notification daemon)
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("dbus-update-activation-environment --all")
    hl.exec_cmd("sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP") -- Some fix idk

    -- Audio
    hl.exec_cmd("easyeffects --hide-window --service-mode")

    -- Clipboard: history (refreshes the qml-rice clipboard page after each store)
    local shellDir = os.getenv("QML_RICE_HOME") or "$HOME/.local/share/qml-rice/shell"
    hl.exec_cmd("wl-paste --type text --watch bash -c 'cliphist store && cd " .. shellDir .. " && qs -p ./shell.qml ipc call cliphistService update'")
    hl.exec_cmd("wl-paste --type image --watch bash -c 'cliphist store && cd " .. shellDir .. " && qs -p ./shell.qml ipc call cliphistService update'")

    -- Cursor
    hl.exec_cmd("hyprctl setcursor macOS 20")
end)

-- Screen shader: vibrance, always (if hyprshade is installed). Outside the start hook on
-- purpose: any config reload clears decoration:screen_shader, so reapply on every load.
hl.exec_cmd("command -v hyprshade >/dev/null && sleep 1 && hyprshade on vibrance")
