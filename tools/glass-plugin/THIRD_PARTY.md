# Third-party notices

## hyprglass (BSD 3-Clause)

qmlrice-glass was written as an independent plugin and its shaders are original.
Some plugin plumbing follows the approach of hyprglass
(https://github.com/hyprnux/hyprglass, `hyprland-0.56` / `main` v0.10.0):

- `src/main.cpp`: resolving the private `renderLayer` symbol by exact mangled name
  with `dlsym` and a `dladdr` check that it lives in the Hyprland executable, and
  the hook / remove-on-failure sequence around `createFunctionHook`.
- `src/GlassPass.cpp`: the foreign-render guard in `Glass::renderAllowed()`
  (`mainFB != currentFB`, render modifier set), the scissor reset before
  `glBlitFramebuffer`, the clamped-source blit with a pre-clear, the 3x3 fullscreen
  projection used for the blur passes, and the pass-element contract
  (`needsLiveBlur` agreeing with `boundingBox`).

Those parts are adapted from, or derived by reading, hyprglass and so carry its notice:

```
BSD 3-Clause License

Copyright (c) 2025, Jeremy Trufier

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Hyprland / hyprbars

The config-value registration and plugin entry-point conventions follow
hyprland-plugins' `hyprbars` (BSD 3-Clause, Copyright (c) 2023 Vaxry). Only the
pattern is reused, no code is copied.
