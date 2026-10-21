-- Glass shell blur (shell/docs/superpowers/specs/2026-10-06-glass-redesign-design.md).
-- Loaded from hyprland.lua AFTER hyprland/shellOverrides/main.lua: that
-- shell-managed file pins blur size 1, which flattens the glass to tinted
-- plastic, and it may be rewritten by a settings UI, so the glass values
-- live here instead of being edited into it.

-- Runtime profile (AGENTS.md: machine differences are profiles): a battery
-- means the laptop, which gets a lighter blur.
local hasBattery = (function()
    for _, name in ipairs({ "BAT0", "BAT1", "BAT" }) do
        local f = io.open("/sys/class/power_supply/" .. name .. "/type", "r")
        if f then f:close(); return true end
    end
    return false
end)()

hl.config({ decoration = { blur = {
    enabled = true,
    size = hasBattery and 10 or 12,
    passes = hasBattery and 3 or 4,
    -- Lowered contrast pulls extreme backdrops toward the middle (darks
    -- lift, whites dim) so glass text stays readable without darkening the
    -- glass into a black slab. shell/services/AdaptiveColor.qml mirrors
    -- this contrast in its maths; change both together.
    brightness = 0.96,
    contrast = 0.78,
    vibrancy = 0.2,
    noise = 0.015,
} } })

-- Dock (shell/dock, namespace qml-rice:dock): the shelf, hover label and
-- context menu are painted with a near-clear tint (alpha >= 0.30) and the
-- compositor blurs what is behind them. Own rule block, not part of the
-- shared glassLayers regex in rules.lua, so GlassBlurProfile's battery
-- xray trade-off does not touch it. no_anim: the shell slides the dock
-- itself for autohide; Hyprland's layer fade on top would double up.
-- mac-dock:begin
-- Dock + every non-island floating menu share the macOS material (MacMaterial.qml):
-- qml-rice:dock (shelf, hover label, dock menu) and impasto-desktop-menu (desktop context menu).
local macGloss = "^(qml-rice:dock|impasto-desktop-menu)$"
hl.layer_rule({ match = { namespace = macGloss }, blur = true })
hl.layer_rule({ match = { namespace = macGloss }, xray = false })
-- 0.19 sits above the dock's 0.12 white tint, so Hyprland skips the dock's blur on purpose:
-- blur + white tint over a busy wallpaper reads as a flat beige slab (owner, 19 Oct). The dock's
-- real glass comes from tools/glass-plugin, not from Hyprland's plain blur.
hl.layer_rule({ match = { namespace = macGloss }, ignore_alpha = 0.19 })
hl.layer_rule({ match = { namespace = "^qml-rice:dock$" }, no_anim = true })
-- mac-dock:end

-- mac-style:begin
-- Tahoe ("mac") surfaces: shell/mac, every layer namespace "qml-rice:mac-<kind>"
-- (mac/TahoeSurface.qml). Blur is the compositor's job, same as the dock. The
-- body is a white TahoeGlass tint at alpha 0.12 (mac/MacTokens.qml,
-- surfaceTintAlpha). ignore_alpha must stay BELOW that tint or Hyprland skips
-- the blur entirely, so keep 0.06 < 0.12 when either value changes.
local macSurfaces = "^qml-rice:mac-.*$"
-- GLASS_PLUGIN_ACTIVE: set true ONLY when tools/glass-plugin (qmlrice-glass) is loaded
-- in the compositor. The plugin draws the mac glass in alpha-mask mode, so Hyprland's
-- blur must be off for these namespaces or it frosts the whole layer rect as a slab.
-- Same flag as the dock block above (ported from glass-mac).
-- Active iff the plugin is installed on this machine (tools/glass-plugin); a machine
-- without it keeps Hyprland's blur. The plugin refuses to start on a Hyprland build
-- mismatch, in which case mac surfaces just lose glass until it is rebuilt.
local GLASS_SO = (os.getenv("HOME") or "") .. "/.local/lib/qmlrice-glass/qmlrice-glass-rim.so"
local glassSo = io.open(GLASS_SO, "r")
local GLASS_PLUGIN_ACTIVE = glassSo ~= nil
if glassSo then glassSo:close() end
-- Tuned live on 20 Oct (owner present). Plugin config only exists once it is loaded,
-- so load it at start and apply the values in the same step.
-- Re-apply the plugin settings on EVERY config load when the plugin is already
-- loaded: a reload (any saved hypr file) otherwise resets them and the glass goes
-- off. This Lua runs inside Hyprland, so its own memory map lists loaded plugins
-- (hyprctl cannot answer while Hyprland is loading this config). At login the
-- plugin is not loaded yet and the start hook below applies them instead.
local function glassLoaded()
    local m = io.open("/proc/self/maps", "r")
    if not m then return false end
    local out = m:read("*a") or ""
    m:close()
    return out:find("qmlrice%-glass[^/]*%.so") ~= nil
end
if GLASS_PLUGIN_ACTIVE and glassLoaded() then
    hl.config({ plugin = { qmlrice_glass = {
        enabled = true, shape = "alpha", namespaces = "^qml-rice:mac-(?!banner$).*$",
        rimWidth = 22, refraction = 0.8, specular = 1.0, blur = 20, radius = 16,
        lightAngle = 100, dispersion = 0.5,
    } } })
end
if GLASS_PLUGIN_ACTIVE then
    hl.on("hyprland.start", function ()
        hl.exec_cmd([[sh -c 'sleep 2; hyprctl plugin load "$HOME/.local/lib/qmlrice-glass/qmlrice-glass-rim.so" && hyprctl eval "hl.config({ plugin = { qmlrice_glass = { enabled = true, shape = \"alpha\", namespaces = \"^qml-rice:mac-(?!banner$).*\$\", rimWidth = 22, refraction = 0.8, specular = 1.0, blur = 20, radius = 16, lightAngle = 100, dispersion = 0.5 } } })"']])
    end)
end
hl.layer_rule({ match = { namespace = macSurfaces }, blur = not GLASS_PLUGIN_ACTIVE })
hl.layer_rule({ match = { namespace = macSurfaces }, xray = false })
hl.layer_rule({ match = { namespace = macSurfaces }, ignore_alpha = 0.06 })
-- Notification Center backdrop and top-right hot corner: never Hyprland-blurred, the glass plugin feathers the backdrop instead.
hl.layer_rule({ match = { namespace = "^qml-rice:mac-nc-(backdrop|corner)$" }, blur = false })
-- The backdrop fades with the NC slide and the corner is invisible, so they never get a window animation.
hl.layer_rule({ match = { namespace = "^qml-rice:mac-nc-(backdrop|corner)$" }, no_anim = true })
-- mac-style:end
