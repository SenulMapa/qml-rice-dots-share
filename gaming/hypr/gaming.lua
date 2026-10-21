-- Gaming latency fixes carried over from the impasto modules/ (22 Sep 2026).
-- allow_tearing is already on in hyprland/general.lua.

-- 2 = auto: direct scanout only for surfaces tagged content = "game".
hl.config({ render = { direct_scanout = 2 } })

local games = {
    "^(cs2)$",              -- Counter-Strike 2, native Linux (XWayland)
    "^(steam_app_.*)$",     -- anything under Proton
    "^(gamescope)$",
}

for _, class in ipairs(games) do
    hl.window_rule({ match = { class = class }, immediate = true })
    hl.window_rule({ match = { class = class }, content   = "game" })
    hl.window_rule({ match = { class = class }, no_blur   = true })
    hl.window_rule({ match = { class = class }, no_shadow = true })
    hl.window_rule({ match = { class = class }, no_anim   = true })
    hl.window_rule({ match = { class = class }, rounding  = 0 })
    -- Straight onto workspace 10 (pinned to DP-1 below), already fullscreen.
    hl.window_rule({ match = { class = class }, workspace  = "10" })
    hl.window_rule({ match = { class = class }, fullscreen = true })
end

-- Games still land on 10 on DP-1, but 10 is not DP-1's *default* -- that made DP boot onto 10.
hl.workspace_rule({ workspace = "10", monitor = "DP-1" })
hl.workspace_rule({ workspace = "1",  monitor = "DP-1", default = true })
