# qmlrice-glass

An Apple-style liquid-glass render effect for **selected layer-shell surfaces** of the
qml-rice shell, as a Hyprland plugin. Normal windows are never touched.

What it draws, behind a matching layer surface (the surface itself is drawn on top by
the shell, so its own tint/content is unchanged). The rim model is the owner's WebGL
liquid-glass (`~/liquid-glass-build/liquid-glass-webgl/liquid-glass.js`), ported to one layer.

**The shape is the surface's own alpha (`shape = "alpha"`, default).** A mac layer's window is
often bigger than what it paints: Control Center is one window holding many floating modules,
Notification Center is a column of cards, a banner has a shadow margin. Glass is therefore drawn
only where the surface paints:

- **Coverage**: the layer's own texture is read at each pixel. Nothing is glassed where its alpha is
  below `alphaThreshold` (default 0.02), and nothing on the soft side of the 50% alpha contour, so a
  drop shadow (alpha under about 0.35) and any gap between modules stay clear.
- **Edge distance and normal**: the surface alpha is drawn into a padded half-res target and
  Gaussian-blurred (sigma = 0.4 x bezel, 3..16 px). For a blurred step, `Phi(d / sigma)`, so the
  edge distance is `d = sigma * logit(blurred / local alpha) / 1.702`, and the normal is the
  negated gradient of the blurred alpha. Each module or card gets its own rim, highlight and
  refraction, and the rim follows its rounded corners (approximately; corners are slightly
  underestimated, so their rim is a touch wider).
- The refraction model below is unchanged, driven by that per-pixel distance and normal.

`shape = "rect"` keeps the old behaviour: the box with a `radius` rounded-rect SDF. Use it only
for a surface whose window is exactly the shape.

With the shape known, the rest of the model (both modes):

- **Body**: a frosted, undistorted blur (`blur`, default 28 px) of what is behind the surface.
  The sample copies are padded by 2 x blur, because the two separable blur passes compound.
  A smaller pad lets the clamped edge smear vertical streaks through the body.
- **Rim lens**: within `rimWidth` (the bezel, default 22 px) of the edge, the backdrop sample is
  taken `shift = refraction * bezel/2 * (1-t)^2` px further inside, along the inward normal,
  with `t` the normalised depth. The derivative of the sample position is `1 - refraction*(1-t)`,
  so it never folds for `refraction` <= 1: content inside the bezel is compressed, never mirrored.
  The shift is zero (value and slope) where the rim meets the body, so text over the body is never
  warped. The earlier Snell/squircle shift (ior, thickness) was dropped: it folds inside the bezel.
- **Rim sharpness**: the rim is at most 35% sharp backdrop at the very edge and blends to the
  blurred copy inward, so the bezel reads as light, not as a legible folded copy of the text.
- **Chromatic dispersion** only on the outer 40% of the bezel, fading in to the edge
  (`dispersion`, 0.35 default; 1 = a 0.22 / 0.11 red / green split).
- **Rim light** (Tahoe-style): a crisp ~1 px top-lit line along the edge facing `lightAngle` (above by
  default), falling off around the sides, a softer spill inward over the top, and a thin bright lip all
  round the outer edge. A faint darker band sits just inside the edge (thickness). The body is lifted
  +6% luminance and x1.15 saturation. Nothing is tinted or rainbow-coloured beyond the dispersion.
- No tint, no dark fill, no drop shadow (the shell owns those).

In alpha mode a layer whose box is larger than what it paints gets glass only on the painted
parts. In rect mode it gets glass over the whole box.

The `qml-rice:mac-*` namespaces (banner, nc, cc, spotlight, call) are in the default
`namespaces` regex.

## Feather mode (progressive backdrop blur)

A layer whose namespace fully matches `featherNamespaces` (default `^qml-rice:mac-nc-backdrop$`)
gets a feathered blur instead of glass. It has no lens, no rim, no refraction, no specular, no
dispersion and no 50% contour cut-off. The surface alpha is a soft blur weight:

- `weight = clamp(surfaceAlpha * featherGain, 0, 1)`
- output = `blurred backdrop * weight`, composited over the sharp backdrop

So where the surface alpha is 0 the screen stays exactly sharp, and the blur rises smoothly with
the alpha. The default `featherGain` of 4.5 makes alpha 0.22 (the top of a 0 to 0.22 gradient) a
weight of 0.99, i.e. full blur. The layer's own pixels are drawn by Hyprland on top, as usual.

Feather wins over normal glass: a layer matching both regexes gets only the feather treatment. A
feather layer always runs the alpha path (it needs the exact per-pixel alpha), whatever `shape` says.
Layers matching neither get nothing. Normal glass is unchanged. The master `enabled` switch covers both.
The offline check is `test/feather_check.py` (run with the render test binary, env `GLASS_FEATHER=1`).

## Target

Hyprland **v0.56.2, commit efb50993780079460b0cbed1363e2166a2de1d9f**, only. `PLUGIN_INIT`
checks the running commit, the commit of the headers it was built against, and the pin; on
any difference it posts a notification and throws, so nothing is hooked and Hyprland
unloads the plugin. There is no override.

## Build (never installs anything)

```
cmake -S tools/glass-plugin -B /tmp/qmlrice-glass-build
nice -n 19 ionice -c3 cmake --build /tmp/qmlrice-glass-build -j2
```

Output: `/tmp/qmlrice-glass-build/qmlrice-glass.so`. To build under another file name (a rebuilt
plugin that must be loaded again in a session needs a new path, because dlopen keeps a library that is
already loaded from the same path), configure with `-DQMLRICE_GLASS_OUTPUT_NAME=qmlrice-glass-dma`, which
gives `qmlrice-glass-dma.so`. Offline shader check:
`cmake --build /tmp/qmlrice-glass-build --target check-shaders` (needs `glslangValidator`).
Headers come from `pkg-config --cflags hyprland`.

Headless render check (software GL, no Hyprland), see `test/glass_render_test.cpp`: it runs
the two shaders through the same sample, downscale, blur, glass pipeline over a raw RGBA backdrop.
Build: `g++ -std=c++23 -O2 test/glass_render_test.cpp -lEGL -lGLESv2 -o /tmp/glassqa/glass_render_test`.
Arguments are listed in the source header. Rect mode is argc 17. Alpha mode adds two arguments,
the surface RGBA raw (box-sized, premultiplied) and `shaders/glass_alpha.frag`, so argc 19. Env:
`GLASS_BLUR` (body blur px, default 28) and `GLASS_THRESHOLD` (alpha gate, default 0.02). Each run is one
panel, so chain runs by feeding each output back in as the next backdrop.

The alpha fixture is written by `python3 -I test/make_alpha_fixture.py <outdir>`: a 560 x 600
backdrop (stripes and text-like bars) and a 420 x 520 Control-Center-like surface (five rounded modules
with gaps, plus a soft shadow under alpha 0.3). The run checks: no change to the backdrop where the
surface alpha is below 0.02 or in the shadow band or in a gap, and every solid module pixel
glassed. Tuned look for alpha mode: `specular 0.6`, `dispersion 0.5` (the plugin defaults are left
at 0.4 and 0.35, the values the owner tuned for rect mode).

## Config

Same mechanism as hyprbars: values registered under `plugin:qmlrice_glass:*`, set from the
Lua config with `hl.config({ plugin = { qmlrice_glass = { ... } } })`.

| key | default | meaning |
| --- | --- | --- |
| `enabled` | `false` | master switch |
| `namespaces` | `^(qml-rice:dock\|qml-rice:menu\|qml-rice:osd\|qml-rice:notif.*\|qml-rice:launcher\|qml-rice:mac-.*)$` | ECMAScript regex, full match against the layer namespace. Read at load and on config reload. An invalid regex matches nothing |
| `rimWidth` | `22` | refracting bezel width, logical px |
| `radius` | `22` | corner radius, logical px (rect mode only) |
| `refraction` | `1.0` | rim lens shift as a fraction of bezel/2, 0..1 (above 1 folds the sample position) |
| `dispersion` | `0.35` | rim RGB split, 0..2, outer 40% of the bezel only (replaces `chroma`) |
| `specular` | `0.4` | rim highlight strength 0..1 |
| `lightAngle` | `100` | degrees counter-clockwise from +x; 90 is straight above |
| `blur` | `28` | frosted body blur radius, logical px |
| `shape` | `alpha` | `alpha`: glass where the surface paints (default). `rect`: the box with `radius` corners. Any other value is treated as `alpha` |
| `alphaThreshold` | `0.02` | alpha mode: surface alpha below this gets no glass, 0..1. Shadows are excluded by the 50% contour, not by this value |
| `featherNamespaces` | `^qml-rice:mac-nc-backdrop$` | ECMAScript regex, full match. Feather mode (see above), wins over `namespaces`. Read at load and on config reload. An invalid regex matches nothing |
| `featherGain` | `4.5` | feather blur weight = clamp(surface alpha x gain, 0, 100 in the plugin) to 0..1 |

The matching layers must **not** also carry a Hyprland `blur` layer rule: Hyprland's own
blur is drawn when the surface is, after the glass, and would paint over the rim. With the
plugin active, `hypr/hyprland/glass.lua` has a marked toggle (`GLASS_PLUGIN_ACTIVE`) that drops
that rule for the glass namespaces.

## Hooks and failure modes

| what | public? | why | failure mode |
| --- | --- | --- | --- |
| `HyprlandAPI::addConfigValueV2` (bool/string/float values) | public plugin API | tunables | n/a |
| `Event::bus()->m_events.layer.closed`, `config.reloaded` | public event bus | drop per-layer match cache; rebuild namespace regex | n/a |
| `g_pHyprRenderer->m_renderPass.add(...)` with our own `IPassElement` | public (render pass API, same as hyprbars) | queue the glass draw | n/a |
| `Render::IHyprRenderer::renderLayer(PHLLS, PHLMONITOR, const steady_tp&, bool, bool)` via `createFunctionHook` | **private**, resolved by exact mangled name with `dlsym`, accepted only if the address is inside the Hyprland executable | the only place that can queue an element immediately before a layer's own surface elements | symbol missing or `hook()` fails: hook removed, notification, plugin inert (no glass, no crash). Hook body is wrapped in `try/catch`; any exception falls through to the original call. If trampoline or state is gone the hook does nothing |
| `ls->m_layerSurface->m_surface->m_current.texture` (layer surface's committed texture, alpha mode), `ITexture::ok()`, `bind()`, `unbind()`, `m_type` | exported internals, not PluginAPI | the surface's own alpha is the shape. The texture is read through Hyprland's texture object, so SHM (2D) and DMA-buf (`GL_TEXTURE_EXTERNAL_OES`) both work | field renamed or moved: the build fails (no silent use). A null or broken texture: no glass for that layer this frame |
| GL calls from the pass element (`useShader`, `createFB`, `projectBoxToTarget`, `scissor`, `setViewport`, `blend`, `glBlitFramebuffer`) | exported internals, not PluginAPI | the draw | covered by the exact-commit guard. Shader compile failure, a non-GL framebuffer backend or an exception in `draw()` disables glass for the session with a notification |

Version guard: first thing in `PLUGIN_INIT`, before any Hyprland-layout-dependent call. No
environment variable or option skips it.

Skipped on purpose: popups, lockscreen layers, closing-layer snapshots, foreign renders
(screencopy replays, overview-style render modifiers), rotated monitors, unmapped or
fully transparent layers, and in alpha mode any layer whose surface texture is missing or
broken. A DMA-buf layer is drawn through the external-target shader; if the driver rejects that
shader, DMA-buf layers get no glass (one notice) and SHM layers are unaffected.

Allocations: one small pass element per matching layer per frame, which is how any pass
element works. Sample framebuffers are reused and only reallocated when the layer size or
the monitor format changes. No full-screen passes: everything is the layer box plus a small
rim margin.

Cost in alpha mode, per matching layer per frame: one box-sized draw of the surface alpha (the
silhouette), one half-res draw of that into the padded target, and one half-res blur pass pair (the same
blur as the body), plus about twice the texture fetches in the glass shader (the edge gradient is only read
on the rim). It stays inside the layer box. The
body blur and the alpha blur are both at half resolution. Layers with alpha at or below 0.004 are
skipped before any of this. Layers without a usable surface texture are skipped too.

## Not verified live

Everything above compiles and the shader renders correctly headless. What cannot be proven
without loading it into a compositor: the framebuffer row orientation assumption (sample
copy row index equals Hyprland y, same as hyprglass assumes), live damage behaviour at 240 Hz,
and interaction with the shell's real layers. Alpha mode adds the following things only the compositor can
show. DMA-buf: the external-target shader compiles on the owner's NVIDIA driver, and the external texture
bind/unbind (through `ITexture`) gives the right alpha at the box's own UV (offline, only the SHM path is
run). Also: that the layer's committed texture is row 0 = top (it is sampled at the box's own UV, the same
convention as the backdrop copy), that the surface alpha matches what is on screen (premultiplied SHM
buffers assumed), and that the frame cost stays inside budget with a real Quickshell layer set. The
offline test shows the shape and gap behaviour only. That is the owner's first test, see
`.superpowers/sdd/glass-plugin-report.md` for the exact commands and recovery.

## TODO (shell side, not done here)

`shell/core/Config.qml` now has `Config.glass.compositor` (default `false`, setting
`glass.compositor`). One-line hook-up still to do once `TahoeGlass` lands on `dock-tahoe`:
in `TahoeGlass`, bind the fake rim's `visible` to `!Config.glass.compositor`.

## Licence

Plugin plumbing adapted from hyprglass keeps its BSD 3-Clause notice, see `THIRD_PARTY.md`.
