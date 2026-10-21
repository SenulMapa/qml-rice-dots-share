-- macOS-style trackpad gestures and touchpad input defaults.
-- Loaded from hyprland.lua after hyprland.mac-keys, guarded by file existence.
--
-- Gestures are registered only when a touchpad is present (checked via
-- /proc/bus/input/devices: Hyprland 0.56's Lua API has no device enumeration).
-- On a machine without a touchpad, nothing changes.
--
-- Gesture map (3 fingers, Mac-style):
--   horizontal swipe  -> switch workspace      (general.lua keeps 4-finger horizontal)
--   swipe up          -> Mission Control (quickshell:missionControlToggle; no-op if quickshell is absent)
--   pinch             -> fullscreen            (stays in general.lua)
-- The 3-finger "move" swipe that general.lua used to register is re-registered
-- here only when the switch is off, because it would otherwise shadow the
-- workspace swipe (first gesture to begin wins).

-- Master switch: false restores the old behaviour and skips the Mac gestures.
local ENABLED = true

-- True when /proc/bus/input/devices lists a touchpad-like device.
local function hasTouchpad()
    local f = io.open("/proc/bus/input/devices", "r")
    if not f then return false end
    local found = false
    for line in f:lines() do
        local name = line:match('^N: Name="(.*)"')
        if name then
            local n = name:lower()
            if n:find("touchpad", 1, true) or n:find("trackpad", 1, true) or n:find("synaptics", 1, true) then
                found = true
                break
            end
        end
    end
    f:close()
    return found
end

if ENABLED then
    -- Touchpad defaults (no-ops without a touchpad). Loaded after shellOverrides,
    -- so these win over its natural_scroll = false.
    hl.config({
        input = {
            touchpad = {
                natural_scroll = true,
                tap_to_click = true,
            },
        },
    })
end

if ENABLED and hasTouchpad() then
    hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
    hl.gesture({
        fingers = 3,
        direction = "up",
        -- Overview hook: the repo's overview is the quickshell one. If quickshell
        -- is not running, the global dispatch does nothing.
        action = function()
            hl.dispatch(hl.dsp.global("quickshell:missionControlToggle"))
        end,
    })
else
    -- Original general.lua gesture, kept for the switch-off and no-touchpad cases.
    hl.gesture({ fingers = 3, direction = "swipe", action = "move" })
end
