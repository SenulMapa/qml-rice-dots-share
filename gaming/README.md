# gaming/

Hyprland latency settings and a Steam/CS2 launch setup for NVIDIA. Tuned for
one NVIDIA box (RTX 5060, driver 610.x, two monitors). Adjust for your
hardware.

## Files

| File | Goes to | Purpose |
|---|---|---|
| `hypr/gaming.lua` | `~/.config/hypr/gaming.lua` | Tearing, direct scanout, and window rules for games |
| `hypr/monitors.example.lua` | `~/.config/hypr/monitors.lua` (after editing) | Monitor layout, refresh rates, VRR |
| `bin/game-launch` | `~/.local/bin/game-launch` | Steam launch wrapper (gamescope + cache setup) |
| `steam/steam_dev.cfg` | `~/.local/share/Steam/steam_dev.cfg` | Steam developer settings (shader thread count) |

## Hyprland latency

`gaming.lua` does the following:

- `render.direct_scanout = 2` (auto). Direct scanout is used only for
  surfaces tagged `content = "game"`.
- Window rules for classes `^(cs2)$`, `^(steam_app_.*)$` and `^(gamescope)$`:
  `immediate`, `content = "game"`, no blur, no shadow, no animation, no
  rounding, fullscreen on workspace 10.
- Workspace 10 is pinned to DP-1. Workspace 1 is the default for DP-1.
- `vrr = 2` is the tuned VRR setting. The monitor example file sets
  `vrr = 0`, so change it to `2` if your monitor supports VRR.
- `allow_tearing = true` is set in `hyprland/general.lua` in the base config.
  The `immediate` rule needs it.

Window rules apply when a window opens. If you change rules, restart the
game. CS2 native runs as class `cs2` under XWayland.

### Install

1. Copy `hypr/gaming.lua` to `~/.config/hypr/`.
2. Add `require("gaming")` to `~/.config/hypr/hyprland.lua`.
3. Copy `hypr/monitors.example.lua` to `~/.config/hypr/monitors.lua` and edit
   it for your outputs: connector names (`hyprctl monitors`), mode and
   refresh rate, position, and VRR.
4. Copy `bin/game-launch` to `~/.local/bin/` and run
   `chmod +x ~/.local/bin/game-launch`.

`gaming.lua` assumes an output named `DP-1` for workspace 10. Change the
`workspace_rule` lines if your game monitor has a different name.

## CS2 Steam launch options

Set the CS2 launch options in Steam to:

```
game-launch %command%
```

Stretched 4:3 through gamescope (1280x960 rendered, shown on 1920x1080):

```
gamescope -w 1280 -h 960 -W 1920 -H 1080 -r 240 -S stretch -F linear -f -- %command%
```

- `-S stretch` stretches the image to fill the output. `-S fit` letterboxes.
- On RTX 5060 with driver 610.x, `-F nis` and `-F fsr` segfaulted.
  `-F linear` is stable.

`game-launch` runs the command through gamescope if it is installed. Without
gamescope it starts the game directly.

## NVIDIA shader cache

Steam's merged NVIDIA shader cache breaks past 4 GiB
([ValveSoftware/steam-for-linux#13622](https://github.com/ValveSoftware/steam-for-linux/issues/13622)).
`game-launch` avoids this for CS2 (app 730):

- Gives CS2 its own `__GL_SHADER_DISK_CACHE_PATH` under `~/.cache/nvidia-cs2`.
  The cache is seeded once from Steam's cache, which is only read.
- Sets `__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1` and
  `__GL_SHADER_DISK_CACHE_SIZE` to 16 GiB.

Turn **Shader Pre-Caching** off in Steam settings.

In `steam_dev.cfg`, `unShaderBackgroundProcessingThreads N` sets the number
of background shader threads. Set N to roughly your CPU thread count minus 2.
The file in this repo uses 10.
