# love-wasi

**Real LÖVE, compiled to wasm32-wasi, as the in-browser preview engine**

This is a fork of [love2d/love](https://github.com/love2d/love) (the `main` / 12.0-development branch), altered for a WebAssembly/WASI target. Per the zlib license: this is an altered version, plainly marked, and not the original software — LÖVE itself lives upstream (docs at the [LÖVE wiki](https://love2d.org/wiki)), and this fork defers to upstream for everything except its platform target.

**Base pin:** upstream `main` @ `540e681454e1a791294488e66173b48faa40fcc6` (2026-07-05). Rebases onto newer upstream are deliberate, recorded events — next planned at the 12.0 release.

**Status: the LÖVE core boots in a real browser.** Build-order steps 0–3 are done and browser-verified (see the build order below): real `love.math` and `love.data` run under this repo's frame pump over the pinned lua-wasi source drop, and LÖVE 12's own main-loop function executes to its documented stop-line at the `love.filesystem` seam. The tree stays upstream-shaped — the only edit to shared engine source is a small platform seam in `common/config.h` (a three-line `__wasi__` → `LOVE_WASI` guard plus one clause added to the platform sanity-check). Outside `wasi/`, the fork adds only two CI workflows (`.github/workflows/witness.yml` and `.github/workflows/publish-sysroot.yml`), the interactive-session bring-up hook under `.claude/`, a few `.gitignore` lines, and the governance docs (`AGENTS.md`, `CLAUDE.md`).

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

- `clang-20+` + `wasi-libc`, C++ with **`-fwasm-exceptions`** and the *standardized* wasm-EH encoding — matching lua-wasi's toolchain, which is mandatory: the VM and this engine share one EH machinery, so the LLVM major and EH encoding must agree. Caution, probed 2026-07-07: clang-20's bare `-fwasm-exceptions` **defaults to the legacy encoding**; the standardized one needs an explicit `-mllvm -wasm-use-legacy-eh=false`, which is baked into `wasi/toolchain/build-libcxx-eh.sh` and every build script here — and enforced per artifact by `wasi/toolchain/check-eh-encoding.sh` (disassembly must show `try_table` and zero legacy forms; engines accept both encodings, so only a build-time gate can catch a lost flag). LÖVE's own error path requires full C++ EH — typed catches and exception-object destructors — so the build vendors **LLVM libc++ + libc++abi compiled with wasm-EH** (wasi-sdk's stock libc++ is built without exception support).
- **Lua VM:** [Lua2D/lua-wasi](https://github.com/Lua2D/lua-wasi) (Lua 5.4 + selective AOT), consumed as a **source drop at a pinned commit**, compiled in-tree with this build's own flags, with `LUAW_EXTERNAL_EH` so the real libc++abi owns exception dispatch. LÖVE 12 supports Lua 5.4 natively (`LUA_VERSION_NUM >= 504` paths in `love.cpp`, `common/runtime.cpp`); LuaJIT is not an option under wasm (no runtime codegen; no wasm interpreter backend).
- **No Emscripten anywhere.** The browser side is a small hand-written WASI preview1 shim (`fd_write`, clocks, `proc_exit` — a few dozen lines) plus the import surface defined by the seams below.

## The three seams (new code)

LÖVE has always delegated exactly these to the host OS; a browser tab is just a different host:

1. **Graphics/window.** Upstream: SDL3 provides window/context; `graphics/opengl` issues GL calls. Here: no SDL, no EGL — a backend that routes LÖVE's existing render path to **WebGL2 via static wasm imports**. Written against LÖVE 12's own graphics-backend abstraction (the same interface Vulkan and Metal plug into), so it is upstreamable by construction.
2. **Audio.** Upstream: OpenAL device output (plus a mixing/streaming thread). Here: decoded PCM pushed to **WebAudio** via imports; decoding (vorbis, flac, mp3, wav) stays real, in-tree C. The existing `audio/null` backend is the bring-up placeholder.
3. **`love.thread`.** wasm32-wasi is single-threaded; real threading means real **Web Workers** with message-passing. LÖVE's Channel API is share-nothing by design, so semantics mostly survive — but this is an honest, documented behavioral divergence, not a bug to hide.

Everything else the host supplies as imports, which is the same role an OS plays for desktop LÖVE: `love.filesystem` backed by the IDE's project storage (replacing PhysFS), input events forwarded from the DOM into LÖVE's real event queue, and the frame pump driven by `requestAnimationFrame` (the engine runs as a resident coroutine; the host resumes it once per frame — this repo owns its own pump against lua-wasi's embedding surface; lua-wasi's `onelua.c` reactor glue is not used or extended).

## Substitution map — LÖVE 12 desktop vs. this build

| Concern | LÖVE 12 (desktop) | love-wasi (browser) |
|---|---|---|
| Toolchain | system clang/gcc/MSVC per platform | `clang-20+` + `wasi-libc`, target `wasm32-wasi` (standardized wasm-EH encoding, matched with lua-wasi) |
| C runtime | system libc | wasi-libc (+ a few-dozen-line WASI preview1 shim in the host) |
| C++ runtime & exceptions | system libc++/libstdc++, native unwinding | vendored LLVM libc++ + libc++abi built with `-fwasm-exceptions` (wasm-EH) |
| Lua VM | LuaJIT (or vendored `lua53`) | [lua-wasi](https://github.com/Lua2D/lua-wasi) — Lua 5.4 + selective AOT, source-drop at a pinned commit, `LUAW_EXTERNAL_EH` |
| Window & GL context | SDL3 | `<canvas>` + context via host imports; `t.window.*` drives the canvas |
| GL function loading | glad (runtime loader) | none — static WebGL2 import shim *is* the GL surface |
| Graphics API | OpenGL / Vulkan / Metal backends | WebGL2, as a new backend against 12's own graphics-backend abstraction |
| Audio device | OpenAL (+ mixing/streaming thread) | WebAudio via host imports; pump work folded into the frame loop |
| Audio decoding | in-tree `lullaby` (vorbis/flac/mp3/wav) | **unchanged** — same real C code |
| Physics | in-tree Box2D | **unchanged** |
| Font raster & shaping | FreeType + HarfBuzz (external) | same libraries, vendored and compiled to wasm |
| Image codecs | in-tree stb_image, lodepng, ddsparse, tinyexr | **unchanged** |
| Filesystem / `.love` mounting | PhysFS | host-import VFS backed by the IDE's project storage; `t.identity` namespacing preserved |
| Input | SDL3 events | DOM keyboard/mouse/pointer/gamepad events forwarded into LÖVE's real event queue |
| Main loop | SDL-driven `love.run` | resident coroutine resumed once per `requestAnimationFrame` tick (this repo's own pump) |
| Timing | SDL timer | `performance.now()` / rAF timestamps via imports |
| `love.thread` | SDL threads (pthreads) | Web Workers + `postMessage` (message-passing Channels — documented divergence) |
| Networking (`enet`, `luasocket`, `luahttps`) | real sockets | **absent** — no faithful browser primitive; declared divergence |
| Video (`love.video`, Theora) | libtheora | **deferred** (`t.modules.video = false`) |
| Tracker music | ModPlug | **deferred** |
| Microphone | OpenAL capture (`RecordingDevice`) | **deferred** — browser `getUserMedia` is a separate future design |
| Shipped form | per-platform executables + shared libs | one `.js` file, wasm embedded, Workers from Blob URLs |

## conf.lua

`love.conf(t)` is parsed and honored identically to desktop: `t.window.*` drives the canvas and page title; `t.modules.*` gates which subsystems must exist for a given game (so a game with `t.modules.physics = false` previews before the Box2D link lands); `t.identity` namespaces save data. Settings with no browser equivalent (`t.window.display`/`x`/`y`, exclusive fullscreen, multi-window) are explicitly mapped or no-op'd, and documented — never silently faked.

## Dependency disposition (the build map)

**Replaced at the seams (not compiled):** SDL3 · OpenAL · PhysFS (`src/libraries/physfs`) · glad (GL loader — the WebGL import shim takes its place) · LuaJIT / vendored `lua53` (→ lua-wasi 5.4).

**Kept, real, already in-tree:** `box2d` · `dr` (flac/mp3) · `stb` (stb_image) · `lodepng` · `ddsparse` · `tinyexr` · `Wuff` (wav) · `lz4` · `xxHash` · `noise1234` · `utf8` · the `sound/lullaby` decoder layer · `src/scripts` (boot Lua — prime `WASM_AOT` candidates).

**Kept, real, vendored from outside (new):** FreeType · HarfBuzz (LÖVE 12 requires it for text shaping) · libvorbis + libogg · zlib (**landed**: `wasi/vendor/zlib`, PIN + license beside it) · LLVM libc++/libc++abi (wasm-EH build — **landed**: built from source by `wasi/toolchain/build-libcxx-eh.sh`).

**Excluded from the wasi build — but NOT deleted from the tree:** `graphics/vulkan` + `graphics/metal` backends and their support libraries (`volk`, `vulkanheaders`, `vma`, `vk_video`, `spirv_cross`; `glslang` pending link-time verification) · `video/` + Theora (deferred; `t.modules.video = false`) · `enet`, `luasocket`, `luahttps` (networking — no faithful browser primitive; declared divergence) · ModPlug (tracker music — deferred) · `audio/RecordingDevice` (browser microphone is a later, separate design) · `platform/xcode`, `extra/nsis`, `extra/windows` (other platforms' build glue).

Exclusion happens in the build, not with `rm`: deleting upstream files would bloat the diff, poison rebases, and break the "diff is the evidence" rule. The tree stays upstream-shaped; the wasi build compiles the subset.

**Found treasure:** `testing/` is a runnable LÖVE-project test suite — a ready-made conformance corpus. Running it under this build and under desktop LÖVE, and diffing the outcomes, is the parity witness for every claim this README makes.

## Build order

0. Toolchain bring-up: wasm-EH libc++/libc++abi built and witnessed by a trivial typed-catch program. — **Done, browser-verified (2026-07-06):** `wasi/toolchain/build-libcxx-eh.sh` builds both from LLVM 20.1.2 source (plus the `Unwind-wasm.c` personality shim); `wasi/witness/eh-typed-catch.cpp` — typed catch via a base class, `what()` intact, a carried payload surviving the throw, a non-matching `catch` skipped so the outer typed handler wins, and a destructor run during unwind — **PASSes in Chromium 141** through `wasi/witness/run-browser.mjs` (driven by our own WASI preview1 shim — `wasi/host/wasi-shim.mjs`, the seed of the runtime host — which the three browser witnesses share along with their launcher harness, `wasi/host/witness-harness.mjs`), under `node:wasi`, and — cross-checked on an independent non-V8 engine (#5) — in **wasmtime (Cranelift)** via `wasi/witness/run-wasmtime.py`. The whole check is one saved command, `wasi/witness/run.sh` (every leg must pass; the wasmtime leg is skipped only where the runtime is absent), re-run by CI on every push to `wasi` (`.github/workflows/witness.yml`).
1. lua-wasi running standalone in a browser via the minimal WASI shim (proves toolchain + host pump, zero LÖVE). — **Done, browser-verified (2026-07-06), reproduced locally rather than trusted from its CI:** lua-wasi built from source with the same apt clang-20; its official-suite prefix bundle **PASSes in Chromium 141** via its own `browser-witness.mjs`. Same toolchain, same machine, both halves of the future marriage proven separately.
2. This repo's own frame pump against the lua-wasi source drop — one in-slot, one out-slot, LÖVE-specific semantics live here. — **Done, browser-verified (2026-07-07):** lua-wasi vendored verbatim at pin `v0.1.0` (`wasi/lua/upstream/PIN`; provenance CI-diffed against a fresh clone at that commit), built per its `doc/embedding.md` source-drop contract with `LUAW_EXTERNAL_EH` — the step-0 libc++abi owns all exception dispatch, fingerprint-gated. `wasi/pump/pump.cpp` runs Lua as the resident coroutine, resumed once per frame. The witness (`wasi/pump/run.sh`, node + real Chromium on `requestAnimationFrame`, both must pass, CI-enforced): boot to first yield, five frames, a Lua error reported with traceback while the VM survives and re-boots, clean quit, and an EH selftest — a typed C++ catch and a Lua error unwinding through a C++ frame, destructors run in both.
3. LÖVE core boot (`love.boot`, module registration) compiling and linking with `graphics`/`audio`/`window`/`thread` stubbed (`audio/null` pattern) — proves the build/link story. — **Done, browser-verified (2026-07-07):** `common/` + the module registry with the embedded boot scripts + real `love.data` (lz4 and lua53-pack in-tree; zlib vendored at `wasi/vendor/zlib`) + real `love.math` link into one reactor with the pump (`wasi/boot/build.sh`; module selection through `config.h`'s own `HAVE_CONFIG_H` door, `love::thread` primitives as single-threaded exact no-ops, `love.filesystem` a loud seam stub). Found treasure: `boot.lua`'s chunk *returns* LÖVE's main-loop function, which already yields once per frame — upstream's boot control flow is natively pump-shaped. The witness (`wasi/boot/run.sh`, node + Chromium, CI-enforced): `require "love"`, `_version` 12, `love.math` running, a typed `love::Exception` arriving as a Lua error via `luax_catchexcept`, absent modules loudly absent, and LÖVE's real `main()` exiting 1 at the documented `love.filesystem` stop-line.
4. Graphics backend: render path → WebGL2 imports, against 12's backend interface.
5. Audio backend: PCM → WebAudio.
6. Input/window/filesystem imports + `conf.lua`-driven canvas setup.
7. `love.thread` via Workers.
8. LoveIDE integration: replace the love.js preview path; verify the exported `.love` still runs unmodified on desktop LÖVE.

## Reproducing the witnesses

The three witnesses (`wasi/{witness,pump,boot}/run.sh`) are one-command each and run in CI on every push to `wasi` (`.github/workflows/witness.yml`, both legs — `node:wasi` and real Chromium — must pass). They are also reproducible in an interactive session: `.claude/hooks/session-start.sh` brings the toolchain up on session start — `clang-20` from Ubuntu's own repos, Node ≥ 24.15 from the `nodejs.org` tarball (the web sandbox denies `apt.llvm.org` and `deb.nodesource.com`), `playwright-core` over the pre-provisioned Chromium — and fetches the prebuilt wasm-EH sysroot published by `.github/workflows/publish-sysroot.yml`, so the witnesses pass green in-session without a minutes-long from-source sysroot rebuild in every ephemeral container. This is what lets the remaining seams (steps 4–8) be driven and witnessed by hand, not just in CI.

## Upstream relationship — branches, patches, and the 12.0 swap

LÖVE 12 is unreleased but functionally complete (its open milestone items are polish, several in backends this build excludes). This fork does not wait for it, does not finish it, and must be able to adopt the released 12.0 cheaply. The machinery:

**Branch model.** `main` is a pristine mirror of upstream `love2d/love` — never committed to, only fast-forwarded when adopting a new upstream commit. **`wasi` is the working branch and the repo default**; everything this fork adds lives there. At any moment, `git diff main...wasi` is the complete, current answer to "what did this fork touch" — the evidence for the honest claim above.

**Three lanes for changes:**

1. **Wasi-only code** — new backends, build files, the pump. Additive by design (new files, minimal edits to shared code), lives on `wasi` forever, rebases near-conflict-free.
2. **Generic fixes LÖVE needs** — cut a topic branch from the *upstream base commit* (not from `wasi`), PR it to love2d, cherry-pick it into `wasi` meanwhile. When upstream merges, the carried copy is shed automatically at the next rebase (git recognizes already-applied patches). Carried, never kept.
3. **Fork-private edits to shared engine code — not allowed.** If upstream declines a fix this port needs, that becomes a recorded design decision here, never a silent divergence.

**The swap.** Adopting a new upstream — a fresh nightly or the 12.0 release itself — is: fast-forward `main` to the new commit, rebase `wasi` onto it, watch lane-2 patches fall out, update the base pin at the top of this README. Because lane 1 is additive and lane 2 self-sheds, the expected cost is an afternoon, not a migration.

## Constitution

- **One artifact, no parts.** The shipped form is a single `.js` file with the wasm embedded; Workers spawn from Blob URLs. A repo may have a build; its output may not have pieces.
- **Pin-by-commit in both directions.** Upstream base pinned above; lua-wasi pinned in-tree; LoveIDE pins this repo's artifact by commit. Nothing floats.
- **Claims match evidence.** A subsystem "works" when the `testing/` corpus exercises it in a real browser and matches desktop behavior. Anything less is labeled as less.
- **Upstreamable by construction.** The web backend is written against upstream's own abstractions; small generic seams are offered upstream as they arise; the goal-state conversation — a web platform for LÖVE proper — stays open.

## Working agreement

How work is planned, executed, reviewed, and integrated here is governed by [`AGENTS.md`](AGENTS.md) — shared verbatim with [lua-wasi](https://github.com/Lua2D/lua-wasi) (architect/engineer roles, code/doc passes, truth-seeking doc review, claims graded by strength and durability). The one repo-specific mapping (this repo's trunk is `wasi`, because `main` mirrors upstream) lives in [`CLAUDE.md`](CLAUDE.md).

## Credits & license

zlib license, same as upstream (`license.txt`). LÖVE is the work of the LÖVE Development Team — this fork exists to carry it somewhere new, not to claim it. The Lua layer builds on PUC-Rio Lua and Hugo Musso Gualandi's lua-aot research via [Lua2D/lua-wasi](https://github.com/Lua2D/lua-wasi).
