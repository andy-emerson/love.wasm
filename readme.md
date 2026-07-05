# love-wasi

**Real LÖVE, compiled to wasm32-wasi, as the in-browser preview engine for [LoveIDE](https://github.com/andy-emerson/LoveIDE).**

This is a fork of [love2d/love](https://github.com/love2d/love) (the `main` / 12.0-development branch), altered for a WebAssembly/WASI target. Per the zlib license: this is an altered version, plainly marked, and not the original software — LÖVE itself lives upstream (docs at the [LÖVE wiki](https://love2d.org/wiki)), and this fork defers to upstream for everything except its platform target.

**Base pin:** upstream `main` @ `540e681454e1a791294488e66173b48faa40fcc6` (2026-07-05). Rebases onto newer upstream are deliberate, recorded events — next planned at the 12.0 release.

**Status: design stage.** This README is the contract; nothing wasi-specific has been built yet.

---

## Mission

Compile LÖVE's actual C++ engine — real bindings, real Box2D, real decoders, real font stack — to `wasm32-wasi`, so that a browser can run a LÖVE project with engine behavior that *is* desktop LÖVE's, not an imitation of it. The artifact must:

- **Run real LÖVE source.** Not a JS reimplementation of the `love.*` API. A reimplementation was considered and rejected: multi-year effort, and never bit-exact. The fidelity bar is concrete — e.g. every Lua-facing engine call funnels through `luax_catchexcept`'s typed C++ exception handling (145 call sites); imitations get details like this subtly wrong forever.
- **Need no Emscripten, no pthreads, no SharedArrayBuffer, no COOP/COEP headers.** The IDE must be able to run its preview on any static host. (love.js requires cross-origin isolation because its engine build bakes in `-pthread`; that is unremovable by swapping the Lua VM — it's why this project exists.)
- **Keep the project tree `.love`-compatible.** The same game source runs unmodified on desktop LÖVE. This build powers the browser *preview only*; it has zero involvement in export. (Web *shipping* — a fused per-game web artifact — is deferred, not precluded: deliberate descope.)
- **Prefer faithful primitives over emulation** where the browser has the real thing (real Web Workers for `love.thread`, not coroutines pretending to be threads).

## What stays real, what gets touched — the honest claim

The semantically hard code stays verbatim: physics, decoders, render math, module logic, the Lua bindings. The platform-adjacent plumbing gets touched: backend selection, internal thread usage (audio pump, timers) massaged into a single-threaded frame-pump model, and the build system. Expect the diff against upstream to be the evidence — small, seam-shaped, and reviewable — rather than a "95% unmodified" slogan.

## Toolchain

- `clang-19` + `wasi-libc`, C++ with **`-fwasm-exceptions`** (the wasm exception-handling proposal). LÖVE's own error path requires full C++ EH — typed catches and exception-object destructors — so the build vendors **LLVM libc++ + libc++abi compiled with wasm-EH** (wasi-sdk's stock libc++ is built without exception support).
- **Lua VM:** [Lua2D/lua-wasm](https://github.com/Lua2D/lua-wasm) (Lua 5.4 + selective AOT), consumed as a **source drop at a pinned commit**, compiled in-tree with this build's own flags, with `LUAW_EXTERNAL_EH` so the real libc++abi owns exception dispatch. LÖVE 12 supports Lua 5.4 natively (`LUA_VERSION_NUM >= 504` paths in `love.cpp`, `common/runtime.cpp`); LuaJIT is not an option under wasm (no runtime codegen; no wasm interpreter backend).
- **No Emscripten anywhere.** The browser side is a small hand-written WASI preview1 shim (`fd_write`, clocks, `proc_exit` — a few dozen lines) plus the import surface defined by the seams below.

## The three seams (new code)

LÖVE has always delegated exactly these to the host OS; a browser tab is just a different host:

1. **Graphics/window.** Upstream: SDL3 provides window/context; `graphics/opengl` issues GL calls. Here: no SDL, no EGL — a backend that routes LÖVE's existing render path to **WebGL2 via static wasm imports**. Written against LÖVE 12's own graphics-backend abstraction (the same interface Vulkan and Metal plug into), so it is upstreamable by construction.
2. **Audio.** Upstream: OpenAL device output (plus a mixing/streaming thread). Here: decoded PCM pushed to **WebAudio** via imports; decoding (vorbis, flac, mp3, wav) stays real, in-tree C. The existing `audio/null` backend is the bring-up placeholder.
3. **`love.thread`.** wasm32-wasi is single-threaded; real threading means real **Web Workers** with message-passing. LÖVE's Channel API is share-nothing by design, so semantics mostly survive — but this is an honest, documented behavioral divergence, not a bug to hide.

Everything else the host supplies as imports, which is the same role an OS plays for desktop LÖVE: `love.filesystem` backed by the IDE's project storage (replacing PhysFS), input events forwarded from the DOM into LÖVE's real event queue, and the frame pump driven by `requestAnimationFrame` (the engine runs as a resident coroutine; the host resumes it once per frame — this repo owns its own pump against lua-wasm's embedding surface; lua-wasm's `onelua.c` reactor glue is not used or extended).

## conf.lua

`love.conf(t)` is parsed and honored identically to desktop: `t.window.*` drives the canvas and page title; `t.modules.*` gates which subsystems must exist for a given game (so a game with `t.modules.physics = false` previews before the Box2D link lands); `t.identity` namespaces save data. Settings with no browser equivalent (`t.window.display`/`x`/`y`, exclusive fullscreen, multi-window) are explicitly mapped or no-op'd, and documented — never silently faked.

## Dependency disposition (the build map)

**Replaced at the seams (not compiled):** SDL3 · OpenAL · PhysFS (`src/libraries/physfs`) · glad (GL loader — the WebGL import shim takes its place) · LuaJIT / vendored `lua53` (→ lua-wasm 5.4).

**Kept, real, already in-tree:** `box2d` · `dr` (flac/mp3) · `stb` (stb_image) · `lodepng` · `ddsparse` · `tinyexr` · `Wuff` (wav) · `lz4` · `xxHash` · `noise1234` · `utf8` · the `sound/lullaby` decoder layer · `src/scripts` (boot Lua — prime `WASM_AOT` candidates).

**Kept, real, vendored from outside (new):** FreeType · HarfBuzz (LÖVE 12 requires it for text shaping) · libvorbis + libogg · zlib · LLVM libc++/libc++abi (wasm-EH build).

**Excluded from the wasi build — but NOT deleted from the tree:** `graphics/vulkan` + `graphics/metal` backends and their support libraries (`volk`, `vulkanheaders`, `vma`, `vk_video`, `spirv_cross`; `glslang` pending link-time verification) · `video/` + Theora (deferred; `t.modules.video = false`) · `enet`, `luasocket`, `luahttps` (networking — no faithful browser primitive; declared divergence) · ModPlug (tracker music — deferred) · `audio/RecordingDevice` (browser microphone is a later, separate design) · `platform/xcode`, `extra/nsis`, `extra/windows` (other platforms' build glue).

Exclusion happens in the build, not with `rm`: deleting upstream files would bloat the diff, poison rebases, and break the "diff is the evidence" rule. The tree stays upstream-shaped; the wasi build compiles the subset.

**Found treasure:** `testing/` is a runnable LÖVE-project test suite — a ready-made conformance corpus. Running it under this build and under desktop LÖVE, and diffing the outcomes, is the parity witness for every claim this README makes.

## Build order

0. Toolchain bring-up: wasm-EH libc++/libc++abi built and witnessed by a trivial typed-catch program.
1. lua-wasm running standalone in a browser via the minimal WASI shim (proves toolchain + host pump, zero LÖVE).
2. This repo's own frame pump against the lua-wasm source drop — one in-slot, one out-slot, LÖVE-specific semantics live here.
3. LÖVE core boot (`love.boot`, module registration) compiling and linking with `graphics`/`audio`/`window`/`thread` stubbed (`audio/null` pattern) — proves the build/link story.
4. Graphics backend: render path → WebGL2 imports, against 12's backend interface.
5. Audio backend: PCM → WebAudio.
6. Input/window/filesystem imports + `conf.lua`-driven canvas setup.
7. `love.thread` via Workers.
8. LoveIDE integration: replace the love.js preview path; verify the exported `.love` still runs unmodified on desktop LÖVE.

## Constitution

- **One artifact, no parts.** The shipped form is a single `.js` file with the wasm embedded; Workers spawn from Blob URLs. A repo may have a build; its output may not have pieces.
- **Pin-by-commit in both directions.** Upstream base pinned above; lua-wasm pinned in-tree; LoveIDE pins this repo's artifact by commit. Nothing floats.
- **Claims match evidence.** A subsystem "works" when the `testing/` corpus exercises it in a real browser and matches desktop behavior. Anything less is labeled as less.
- **Upstreamable by construction.** The web backend is written against upstream's own abstractions; small generic seams are offered upstream as they arise; the goal-state conversation — a web platform for LÖVE proper — stays open.

## Credits & license

zlib license, same as upstream (`license.txt`). LÖVE is the work of the LÖVE Development Team — this fork exists to carry it somewhere new, not to claim it. The Lua layer builds on PUC-Rio Lua and Hugo Musso Gualandi's lua-aot research via [Lua2D/lua-wasm](https://github.com/Lua2D/lua-wasm).
