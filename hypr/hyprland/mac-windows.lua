-- macOS window behaviour (P1): per-workspace float/tile, focus, snapping.
-- Tiling is the default (owner, 19 Oct) until drag-to-snap, snap layouts and an overview exist:
-- every macwm_tile rule below starts enabled, and Super+Alt+T turns a workspace floating.
-- Companion daemon: tools/macwm (macwm.py + macwmctl). Loaded after mac.lua, before gaming.lua.

local macwmctl = HOME .. "/.local/bin/macwmctl"

-- Float by default, new floats centred.
hl.window_rule({ match = { class = ".*" }, float = true, center = true })

-- The blanket float above is loaded after rules.lua and gaming.lua, so it would override
-- their tile rules. Re-assert every class they tile here (grep: `tile = true` in hypr/).
hl.window_rule({ match = { class = "^dev\\.warp\\.Warp$" }, tile = true })
for _, class in ipairs({ "^cs2$", "^steam_app_.*$", "^gamescope$" }) do
    hl.window_rule({ match = { class = class }, tile = true })
end

-- Per-workspace tile rules, enabled by default (so windows tile even if macwm is down).
-- An enabled rule makes a window opened on that workspace tile at open (no float-then-jump). macwm drives them with
-- `hyprctl eval 'macwm_tile[N]:set_enabled(true|false)'` and re-syncs all of them on connect.
_G.macwm_tile = _G.macwm_tile or {}
for ws = 1, 10 do
    macwm_tile[ws] = hl.window_rule({
        name = "macwm-tile-" .. ws,
        match = { workspace = "^" .. ws .. "$" },
        tile = true,
        enabled = true,
    })
end

-- Floating is a per-workspace toggle (Super+T is the terminal, so Super+Alt+T).
hl.bind("SUPER + ALT + T", hl.dsp.exec_cmd(macwmctl .. " toggle-tiling"),
    { description = "Window: Toggle tiling on this workspace" })

-- Click to focus: the pointer does not steal focus on hover (follow_mouse 2 = click only),
-- and an app that activates itself comes forward (macOS behaviour; no typing guard, see the P1 plan).
hl.config({
    input = { follow_mouse = 2 },
    misc  = { focus_on_activate = true },
})

-- Keyboard snapping. Super+Ctrl+arrows are already workspace focus, so these live on Super+Alt.
-- Left/right = half of the work area, Up = fill, Down = back to the geometry before the first snap.
local snaps = {
    { "Left",  "left",    "Window: Snap left half" },
    { "Right", "right",   "Window: Snap right half" },
    { "Up",    "fill",    "Window: Fill work area" },
    { "Down",  "restore", "Window: Restore pre-snap size" },
}
for _, s in ipairs(snaps) do
    hl.bind("SUPER + ALT + " .. s[1], hl.dsp.exec_cmd(macwmctl .. " snap " .. s[2]), { description = s[3] })
end

-- App-level hide and cycle (Task 4). Routed through the shell's IPC like the qml-rice binds
-- (`qml-rice ipc apps ...` -> ShellActions.appsIpc -> RunningApps). Super+H and Super+` were free.
local qr = function(cmd) return hl.dsp.exec_cmd("qml-rice ipc " .. cmd) end
hl.bind("SUPER + H",     qr("apps hideFocused"), { description = "Window: Hide app" })
hl.bind("SUPER + grave", qr("apps cycle"),        { description = "Window: Cycle app windows" })
