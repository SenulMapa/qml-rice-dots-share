-- macOS Cmd-style shortcuts: Super acts as Cmd.
-- Loaded from hyprland.lua after hyprland.mac, guarded by file existence.
--
-- Conflict audit (21 Oct 2026). Every Super+key below that is already bound
-- by keybinds.lua, mac.lua, mac-windows.lua (dormant), webapps.lua or the
-- qml-rice-binds heredoc in install.sh is LEFT ALONE. Those keys stay with
-- the shell or window management:
--   Super+C  code editor (keybinds)         Super+V  clipboard (shell / fuzzel)
--   Super+X  text editor (keybinds)         Super+A  left sidebar (shell)
--   Super+F  fullscreen (keybinds)          Super+S  scratchpad (keybinds)
--   Super+T  terminal (keybinds)            Super+W  wallpaper picker (qml-rice-binds)
--   Super+N  notification centre (shell)    Super+R  spotlight (shell)
--   Super+L  lock (keybinds)                Super+P  pin window (keybinds)
--   Super+Left/Right/Up/Down  focus (keybinds)
--   Super+Q  already window close (keybinds), so not re-bound
--   Super+1..0 workspaces, Super+Period/Slash/Semicolon/Apostrophe etc. are taken too.
-- Not implemented because the keys are owned: Ctrl+Shift+C/V terminal
-- mapping (needs Super+C/V), and Super+Left/Right (Home/End) and
-- Super+Up/Down (Ctrl+Home/End), which are the focus keys.
--
-- Super+Z, Super+Shift+Z, Super+Comma, Super+Backspace were free and are bound.
-- Alt+Left/Right word jumps are left to the apps (already Linux-compatible).

-- Master switch: false = no Cmd shortcuts at all (nothing is bound).
local ENABLED = true

if ENABLED then
    -- Sends a shortcut to the focused window via hl.send_shortcut
    -- (top-level Lua function in Hyprland 0.56). mods is a space-separated string.
    local function send(mods, key)
        return function()
            hl.send_shortcut({ mods = mods, key = key })
        end
    end

    -- Cmd+Z undo, Cmd+Shift+Z redo
    hl.bind("SUPER + Z", send("CTRL", "z"), { description = "Mac keys: Undo (Cmd+Z)" })
    hl.bind("SUPER + SHIFT + Z", send("CTRL SHIFT", "z"), { description = "Mac keys: Redo (Cmd+Shift+Z)" })

    -- Cmd+, app preferences
    hl.bind("SUPER + Comma", send("CTRL", "comma"), { description = "Mac keys: Preferences (Cmd+,)" })

    -- Cmd+Backspace: delete to start of line = select to line start, then delete.
    hl.bind("SUPER + BackSpace", function()
        hl.send_shortcut({ mods = "SHIFT", key = "Home" })
        hl.send_shortcut({ key = "BackSpace" })
    end, { description = "Mac keys: Delete to line start (Cmd+Backspace)" })
end
