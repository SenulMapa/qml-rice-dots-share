# Loading qmlrice-glass (owner present)

The plugin is never loaded by an agent or by a script. Load it with you at the keyboard, in
case the compositor has to be recovered. The plugin is not in the Hyprland config, so a
crash or a reboot leaves the session exactly as it is today.

Feather build (feather mode, `featherNamespaces` / `featherGain`): `/tmp/qmlrice-glass-feather-build/qmlrice-glass-feather.so`
(configured with `-DQMLRICE_GLASS_OUTPUT_NAME=qmlrice-glass-feather`, same Hyprland pin). It is not loaded or installed by
the build; the owner loads it at the keyboard.

Built file: `/tmp/qmlrice-glass-build/qmlrice-glass-dma.so` (built with
`-DQMLRICE_GLASS_OUTPUT_NAME=qmlrice-glass-dma`, against Hyprland v0.56.2, commit efb50993). The name is new
on purpose: dlopen reuses a library already loaded from the same path. Alpha mode handles SHM and DMA-buf
surfaces (Quickshell on NVIDIA commits DMA-buf). `/tmp` is cleared on reboot. To keep a copy:
`install -Dm755 /tmp/qmlrice-glass-build/qmlrice-glass-dma.so ~/.local/lib/qmlrice-glass/qmlrice-glass-dma.so`
and use that path below.

## 0. Preconditions

1. The running Hyprland still matches the pin (read-only):
   `hyprctl version -j | grep -o '"commit": "[^"]*"'` must print `efb50993780079460b0cbed1363e2166a2de1d9f`.
   If it does not, do not load. The plugin would refuse and post a notification anyway.
2. The blur toggle is off in the live config, so nothing is double-blurred. It is
   `GLASS_PLUGIN_ACTIVE = false` in `hypr/hyprland/glass.lua`. Leave it false until step 4.

## 1. Load

```
hyprctl plugin load /tmp/qmlrice-glass-build/qmlrice-glass-dma.so
```

Expect no red notification. A notification starting `[qmlrice-glass] Hyprland build mismatch`
means the plugin refused to start: nothing was hooked, unload is not needed.

## 2. Enable the glass (session only, not written to config)

```
hyprctl keyword plugin:qmlrice_glass:enabled true
```

Nothing is drawn until this is set. Defaults for the rest are in `README.md`.

## 3. Verify

- Plugin is listed: `hyprctl plugins list` shows `qmlrice-glass` (version 0.1).
- Hook is live: no notification `could not hook renderLayer, glass is inert`.
- Shader is live: no notification `shader compile failed` or `glass disabled for this session`.
- Look: open a mac surface (banner, nc, cc, spotlight) or the dock. The rim should show a
  top-lit edge and a frosted body. Compare with `.superpowers/tahoe-ref/crops/` in
  `~/qml-rice-dots`.
- Shape: glass should sit on each painted module or card only. Control Center's gaps and the
  banner's shadow margin must be clear. If a surface should be glassed as one rounded box instead
  (its window is exactly its shape), set `plugin:qmlrice_glass:shape = "rect"` for that session.
  Keys: `shape` (default `alpha`), `alphaThreshold` (default `0.02`).
- Optional capture: `grim -g "$(slurp)" /tmp/glass-live.png` (the owner runs this, not an agent).

## 4. Remove Hyprland's blur from the glass namespaces (after step 3 passes)

Edit `hypr/hyprland/glass.lua` (the live copy) and set `GLASS_PLUGIN_ACTIVE = true`, then
reload the config. Reloading is a live change, so do it with the owner present:

```
hyprctl reload
```

Without this step, Hyprland's blur is drawn under the plugin's rim. Set the flag back to
`false` and reload to undo it.

## 5. Unload

Turn the glass off first, so no draw runs while the plugin is removed:

```
hyprctl keyword plugin:qmlrice_glass:enabled false
hyprctl plugin unload /tmp/qmlrice-glass-build/qmlrice-glass-dma.so
```

If `GLASS_PLUGIN_ACTIVE` was set to true, set it back to false and run `hyprctl reload`.
Unloading runs `PLUGIN_EXIT`, which removes the hook before any teardown.

## 6. Recovery if the session crashes

- Log back in. The plugin is not in the Hyprland config, so it does not load again on its own.
- Nothing in `~/.config` was changed by loading it. The only config flag is
  `GLASS_PLUGIN_ACTIVE` in `glass.lua`. If that was true, the next session starts without
  the plugin and Hyprland's blur is off for the glass namespaces. Set it to false to restore
  the normal look.
- If Hyprland itself hangs at login, use a TTY (`Ctrl+Alt+F2`), kill the compositor, and
  log in again. Do not retry the load until the cause is known.
