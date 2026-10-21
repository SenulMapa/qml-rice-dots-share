-- macOS-for-Hyprland, Layer 4: layout, window chrome, motion, traffic lights.
-- Loaded from hyprland.lua LAST (after hyprland.shellOverrides.main and
-- hyprland.glass), because the shell-managed overrides file pins
-- general.layout = "dwindle", rounding 14 and gaps 8/10 and would win over
-- anything loaded earlier (general.lua included). Everything Mac-specific lives
-- here so the drifted/managed files never have to be edited.
--
-- Precedence recap (later wins): general.lua -> shellOverrides/main.lua
-- (layout, rounding, gaps, border) -> glass.lua (blur) -> mac.lua (this file).

local scripts = "$HOME/.config/hypr/hyprland/scripts"

-- ###### Layout: master (one tall main on the left, subs stacked right) ######
hl.config({
    general = { layout = "master" },
    master = {
        mfact = 0.62,
        orientation = "left",
        new_status = "slave",      -- new windows join the right-hand stack
        new_on_top = false,
        new_on_active = "none",
        allow_small_split = false,
        always_keep_position = false, -- lone window must fill the screen
        smart_resizing = true,
    },
})

-- A lone window fills the screen (reads as maximised): no gaps, no rounding.
-- "w[tv1]" = exactly one tiled-visible window on the workspace.
pcall(function()
    -- (removed) lone windows keep gaps, rounding and shadow so they float under the island like a Mac window
    hl.workspace_rule({ workspace = "f[1]", gaps_in = 0, gaps_out = 0, no_rounding = true, no_shadow = true })
end)

-- keybinds.lua resizes the split with dwindle's "splitratio"; master wants "mfact".
pcall(function()
    hl.unbind("SUPER + Semicolon")
    hl.unbind("SUPER + Apostrophe")
    hl.bind("SUPER + Semicolon", hl.dsp.layout("mfact -0.05"), { repeating = true })
    hl.bind("SUPER + Apostrophe", hl.dsp.layout("mfact +0.05"), { repeating = true })
end)

-- ###### Chrome: Mac radius + big soft downward shadow ######
hl.config({
    general = { border_size = 0 },
    decoration = {
        rounding = 11,
        shadow = {
            enabled = true,
            range = 48,
            render_power = 2,
            offset = { 0, 16 },
            scale = 0.97,
            color = "rgba(00000066)",          -- focused
            color_inactive = "rgba(00000026)", -- unfocused: lighter
        },
    },
})

-- ###### Motion ######
hl.curve("macOut",    { type = "bezier", points = { { 0.16, 1.00 }, { 0.30, 1.00 } } }) -- ease-out, no overshoot
hl.curve("macIn",     { type = "bezier", points = { { 0.40, 0.00 }, { 0.68, 0.06 } } }) -- fast exit
hl.curve("macSpring", { type = "bezier", points = { { 0.34, 1.32 }, { 0.64, 1.00 } } }) -- slight overshoot = spring-ish
hl.curve("macLinear", { type = "bezier", points = { { 0.00, 0.00 }, { 1.00, 1.00 } } })

hl.animation({ leaf = "windowsIn",   enabled = true, speed = 2.0, bezier = "macOut", style = "popin 94%" }) -- ~200ms
hl.animation({ leaf = "fadeIn",      enabled = true, speed = 2.0, bezier = "macOut" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 1.3, bezier = "macIn",  style = "popin 96%" }) -- faster
hl.animation({ leaf = "fadeOut",     enabled = true, speed = 1.3, bezier = "macIn" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2.6, bezier = "macOut" })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 3.5, bezier = "macSpring", style = "slide" }) -- ~350ms horizontal
-- Minimise parks the window on special:minimized: fade, not the vertical scratchpad slide.
-- (Also affects the Super+S scratchpad, which shares these leaves.)
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 2.5, bezier = "macOut", style = "fade" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 1.8, bezier = "macIn",  style = "fade" })

-- ###### Minimise contract (shared with the dock) ######
-- Super+Ctrl+M           minimise active window -> special:minimized
-- Super+Ctrl+Shift+M     restore most recent minimised window to this workspace
-- (plain Super+M = media controls, Super+Shift+M / Alt+M = mute: left alone)
hl.bind("SUPER + CTRL + M",         hl.dsp.exec_cmd(scripts .. "/mac-minimize.sh"), { description = "Window: Minimise" })
hl.bind("SUPER + CTRL + SHIFT + M", hl.dsp.exec_cmd(scripts .. "/mac-restore.sh"),  { description = "Window: Restore minimised" })

-- ###### Traffic lights (hyprbars) ######
-- Plugin is optional. Install: tools/mac-windows/install-hyprbars.sh. The plugin
-- calls reloadConfig() when it loads, so this block re-runs with it present;
-- until then it is skipped and the config loads cleanly without it.
-- hyprpm doesn't know about the hand-built copy (~/hypr-plugins, 13 Oct), so it
-- loaded once by hand and was gone after the next reboot. Fall back to that .so;
-- Hyprland itself refuses it if the build no longer matches.
hl.on("hyprland.start", function()
    hl.exec_cmd('hyprpm reload -n; hyprctl plugin list | grep -q hyprbars || { so="$HOME/hypr-plugins/hyprland-plugins/hyprbars/hyprbars.so"; [ -f "$so" ] && hyprctl plugin load "$so"; }')
end)

local function hasHyprbars()
    local ok, v = pcall(function() return hl.plugin.hyprbars ~= nil end)
    return ok and v
end

if hasHyprbars() then
    pcall(function()
        hl.config({ plugin = { hyprbars = {
            enabled = true,
            bar_height = 28,
            bar_color = "rgba(26262899)",
            bar_blur = true,
            bar_part_of_window = true,
            bar_precedence_over_border = true,
            bar_padding = 12,
            bar_button_padding = 8,           -- gap between circles
            bar_buttons_alignment = "left",
            bar_title_enabled = true,
            bar_text_align = "center",
            bar_text_font = "system-ui",
            bar_text_size = 13,
            bar_text_weight = "semibold",
            ["col.text"] = "rgba(ffffffd9)",
            inactive_button_color = "rgba(5a5a5eff)", -- grey lights when unfocused
            icon_on_hover = true,              -- x / - / + glyphs only on hover
            on_double_click = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })'",
        } } })

        -- First button added = leftmost (alignment left).
        hl.plugin.hyprbars.add_button({
            bg_color = "rgb(FF5F57)", fg_color = "rgba(4c0000cc)", size = 12, icon = "x",
            action = "hyprctl dispatch 'hl.dsp.window.close()'",
        })
        hl.plugin.hyprbars.add_button({
            bg_color = "rgb(FEBC2E)", fg_color = "rgba(5a3a00cc)", size = 12, icon = "-",
            action = "$HOME/.config/hypr/hyprland/scripts/mac-minimize.sh",
        })
        hl.plugin.hyprbars.add_button({
            bg_color = "rgb(28C840)", fg_color = "rgba(004d00cc)", size = 12, icon = "+",
            action = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })'",
        })

        -- Bars ONLY on apps that draw no window controls of their own (allowlist);
        -- everything else (GTK header bars, Electron/CSD apps, games, web apps) keeps its own.
        hl.window_rule({ match = { class = ".*" }, ["hyprbars:no_bar"] = true })
        hl.window_rule({
            match = { class = "^(kitty|[Ss]potify|[Tt]hunar|mpv|foot|Alacritty|imv|org\\.pulseaudio\\.pavucontrol|pavucontrol|nm-connection-editor|qalculate-gtk|zen|zen-browser|[Ss]lack)$" },
            ["hyprbars:no_bar"] = false,
        })
        -- Bar colour = the app's own background, so bar + body read as one rounded window (macOS).
        local function kittyBg()
            local f = io.open(os.getenv("HOME") .. "/.config/kitty/qml-rice-palette.conf", "r")
            if not f then return nil end
            local bg
            for line in f:lines() do
                local hex = line:match("^%s*background%s+#(%x%x%x%x%x%x)")
                if hex then bg = hex end
            end
            f:close()
            return bg
        end
        local kb = kittyBg()
        if kb then hl.window_rule({ match = { class = "^kitty$" }, ["hyprbars:bar_color"] = "rgba(" .. kb .. "d9)" }) end
        hl.window_rule({ match = { class = "^[Ss]potify$" }, ["hyprbars:bar_color"] = "rgb(121212)" })
        hl.window_rule({ match = { class = "^[Ss]lack$" }, ["hyprbars:bar_color"] = "rgb(1a1d21)" })
    end)
end

-- mac-blur:begin
-- ###### Vibrancy (tools/mac-blur) ######
-- macOS-style: translucent surfaces over a saturated, slightly bright blur.
-- Overrides glass.lua's values (this file loads last). Contrast is global, so
-- shell/services/AdaptiveColor.qml blurContrast mirrors it (0.74).
-- Battery profile is kept: the laptop gets a lighter blur (8 / 2 vs 10 / 3).
local onBattery = (function()
    for _, name in ipairs({ "BAT0", "BAT1", "BAT" }) do
        local f = io.open("/sys/class/power_supply/" .. name .. "/type", "r")
        if f then f:close(); return true end
    end
    return false
end)()

hl.config({ decoration = { blur = {
    enabled = true,
    size = onBattery and 8 or 10,
    passes = onBattery and 2 or 3,
    brightness = 1.0,
    contrast = 0.74,
    vibrancy = 0.45,
    vibrancy_darkness = 0.3,
    noise = 0.01,
} } })

-- Window blur: rules.lua's blanket `class ".*" no_blur` is gone; the explicit
-- no_blur = false below also wins over it on a drifted rules.lua (later rule
-- wins). Opt-outs after it: games, video, PiP, anything fullscreen.
pcall(function()
    hl.window_rule({ match = { class = ".*" }, no_blur = false })
    -- xwayland context menus / empty-class popups stay unblurred
    hl.window_rule({ match = { class = "^()$", title = "^()$" }, no_blur = true })
    hl.window_rule({ match = { class = "^(mpv|vlc|steam_app_.*|gamescope|cs2|org\\.libretro\\..*|[Ss]team_[Pp]roton.*)$" }, no_blur = true })
    hl.window_rule({ match = { title = "^([Pp]icture[- ]in[- ][Pp]icture)$" }, no_blur = true })
    -- Performance guard: a fullscreen window (every game, gamemode or not)
    -- never pays for window blur.
    hl.window_rule({ match = { fullscreen = true }, no_blur = true })
end)

-- Per-app translucency: only apps whose UI suits it. Browsers, Slack, Discord,
-- Code stay opaque. "active inactive"; no dimming (Mac doesn't dim).
pcall(function()
    hl.window_rule({
        match = { class = "^([Tt]hunar|org\\.gnome\\.Nautilus|org\\.kde\\.dolphin|pavucontrol|org\\.pulseaudio\\.pavucontrol|nm-connection-editor|blueman-manager)$" },
        opacity = "0.94 0.90",
    })
end)
-- mac-blur:end

-- mac-moveto:begin
-- SUPER + SHIFT + 1..0: move the focused window to that workspace and follow it
-- (SUPER + ALT + n stays the silent "send" variant from keybinds.lua).
for i = 1, 10 do
    hl.bind("SUPER + SHIFT + " .. (i % 10), function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = true }))
    end, { description = "Window: Move to workspace " .. i .. " (follow)" })
end
-- mac-moveto:end
