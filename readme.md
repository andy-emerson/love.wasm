# love.wasm

**Real LÖVE, compiled to wasm32-wasi — a browser-native runtime for LÖVE games, and a high-fidelity desktop preview**

This is a fork of [love2d/love](https://github.com/love2d/love) (the `main` / 12.0-development branch), altered for a WebAssembly/WASI target. Per the zlib license: this is an altered version, plainly marked, and not the original software — LÖVE itself lives upstream (docs at the [LÖVE wiki](https://love2d.org/wiki)), and this fork defers to upstream for everything except its platform target.

**Base pin:** upstream `main` @ `81eb4dbcaf2f1d31c10268340e995a5c4a8270af` (2026-07-18) — reached via a GitHub *sync-merge* of `love2d/love:main` into `wasi`, not the deliberate rebase the swap below describes. It pulled in the QOI image format plus minor fixes with no seam conflicts, and the witnesses stayed green. Previous base: `540e681` (2026-07-05). The clean, rebase-based adoption (which flattens this sync-merge away and sheds the lane-2 patches) remains planned for the 12.0 release; base bumps stay deliberate, recorded events.

**Status — what runs today.** Real LÖVE, compiled to `wasm32-wasi`, runs an actual game end to end in real Chromium: `conf.lua` sizes the canvas, `love.window.setMode` opens a real WebGL2 context, `love.load` decodes and plays an Ogg asset read through `love.filesystem` and builds a physics world, and `love.update`/`love.draw` step and draw it once per `requestAnimationFrame` tick. Graphics, filesystem (read, write, enumerate), event/keyboard/mouse, joystick, touch, timer, system, audio, sound and physics are all real engine code over browser seams. `love.thread` is the one major module still stubbed — build-order step 7. Every behavioral claim below carries a witness, and CI re-runs them on every push to `wasi` — with one deliberate exception, `wasi/games/run.sh`, which depends on a third party's repository staying reachable and so is run on demand rather than in the per-push gate. The corpus witness (`wasi/corpus/run.sh`) has no such dependency — `testing/` is upstream's own suite, in this repository — and at ~18s on a reused artifact it runs in the same per-push gate.

There is an **interactive shell**: a page that loads a LÖVE project from disk, runs it on `requestAnimationFrame`, forwards real keyboard, mouse and touch events into `love.event`, and applies a module edit to the running game without a reload (`wasi/shell/`, witnessed by `wasi/shell/run.sh`). It is a game player, not an editor — the downstream consumer this engine is built for is a separate concern.

**A third-party game runs.** [Legend of Lua](https://github.com/challacade/legend-of-lua), an open-source game written for LÖVE 11.5 and **not bundled here**, boots from its own `conf.lua`, opens a 1920x1080 canvas and plays — tilemap, sprites, shadows, UI and text. Every LÖVE feature it uses works; what it needed was a Lua 5.1 → 5.4 port, and nothing else (see **The Lua dialect**). Re-runnable: `wasi/games/run.sh` clones the pinned commit into a scratch directory, applies `wasi/games/legend-of-lua.patch` — 59 lines, our port, the only part of this that lives in the repository — plays it in real Chromium and asserts. Evidence: **observed**, on one game — one case is what one game earns.

**Corpus parity — CI-enforced.** LÖVE's own `testing/` conformance corpus runs under this build on every push (`witness.yml`): **306 pass / 34 fail / 15 skip** across 21 suites, up from 236/92 on its first run, deterministic across repeated runs and ~18s on a reused artifact. Every failure is classified in `wasi/COMPATIBILITY.md` and, executably, in `wasi/corpus/expected.txt` — **30 are features a browser does not have**, 2 need a user gesture no test can supply, and **2 are real gaps** — the Screen Wake Lock, implementable and unbuilt. `wasi/corpus/run.sh` is the witness, and the *comparison* is what it asserts: it fails when a passing test breaks, when a test on the expected-fail list starts **passing** (the classification is stale — an unearned divergence is a lie), and when a failure is classified nowhere. All three are demonstrated able to fail. It is the only witness here measured by somebody else's tests.

**Modules a game may use.** LÖVE enables all twenty modules by default and `boot.lua` hard-errors on a missing one, so a build shipping a subset has to answer for the rest. The union artifact links nineteen — everything except `video` and `thread`. Those two are supplied by the boot wrapper (`wasi/platform/witness-frame.lua`) as absent modules: `require` succeeds so a game boots, `love.<name>` stays `nil` exactly as it is on desktop with `t.modules.<name> = false`, and reading it emits one `[love.wasm preview]` notice naming the module. A game therefore needs no `conf.lua` edit to boot, and a game that genuinely uses one of the two says so in the log rather than failing anonymously.

**Eleven guarded seams.** Edits to shared engine source are eleven small guarded seams, each byte-unchanged for default builds and shaped to be offered upstream. Everything else this fork adds lives outside `src/`.

| Seam | Shared source it touches | What the guard selects |
|---|---|---|
| Platform | `common/config.h` | `__wasi__` → `LOVE_WASM`, plus one clause in the platform sanity-check |
| Audio backend | `modules/audio/wrap_Audio.cpp` | WebAudio vs OpenAL vs null |
| Graphics | `modules/graphics/opengl/OpenGL.cpp`, `opengl/StreamBuffer.cpp` | one `LOVE_GRAPHICS_GL_STATIC_IMPORTS` macro: static WebGL2 imports instead of the SDL proc-address loader, `glBufferSubData` vertex streaming because WebGL2 forbids client-side arrays and buffer mapping, and LA8 reported unsupported so the font atlas falls back to RGBA8 |
| Filesystem | `modules/filesystem/wrap_Filesystem.cpp`, `filesystem/Filesystem.cpp` | the host-import VFS backend instead of PhysFS, the native-C `require` searcher guarded off since a browser cannot `dlopen`, and `getExecutablePath`/`canonicalizeRealPath` routed around the wasm libc++'s absent `<filesystem>` |
| Window | `modules/window/wrap_Window.cpp` | the host-import `love.window` backend instead of SDL |
| Input | `modules/event/wrap_Event.cpp`, `keyboard/wrap_Keyboard.cpp`, `mouse/wrap_Mouse.cpp` | the host-import backends instead of SDL, plus a version-guarded `lua_cpcall`→`lua_pcall` shim (Lua 5.2 removed `lua_cpcall`) |
| Joystick | `modules/joystick/wrap_JoystickModule.cpp` | the browser Gamepad API backend instead of SDL's controller subsystem |
| Sensor | `modules/sensor/wrap_Sensor.cpp` | the preview-limited warned stub instead of SDL (issue #27) |
| Touch | `modules/touch/wrap_Touch.cpp` | the browser TouchEvent backend instead of SDL; touch rides the existing `love_input` record, so it adds no host import |
| Timer | `modules/timer/Timer.cpp` | a `LOVE_WASM` arm of the POSIX `#if` — `clock_gettime(CLOCK_MONOTONIC)`/`gettimeofday` — and an honest no-op `love::sleep`, since the main thread must not block |
| System | `modules/system/System.cpp`, `system/wrap_System.cpp` | `getOS()` returning `"Web"`, and the host-import `love.system` backend instead of SDL |

Two portability fixes to the vendored `glslang` are carried patches offered upstream, not fork seams. Outside `wasi/`, the fork adds two CI workflows, the interactive-session hook and settings under `.claude/`, a few `.gitignore` lines, and the governance documents (`AGENTS.md`, `CONTRIBUTING.md`, `CLAUDE.md`).

---

## Mission

Compile LÖVE's actual C++ engine — real bindings, real Box2D, real decoders, real font stack — to `wasm32-wasi`, so that a browser can run a LÖVE project with engine behavior that *is* desktop LÖVE's, not an imitation of it. The artifact must:

- **Run real LÖVE source.** Not a JS reimplementation of the `love.*` API. A reimplementation was considered and rejected: multi-year effort, and never bit-exact. The fidelity bar is concrete — e.g. every Lua-facing engine call funnels through `luax_catchexcept`'s typed C++ exception handling (145 call sites); imitations get details like this subtly wrong forever.
- **Need no Emscripten, no pthreads, no SharedArrayBuffer, no COOP/COEP headers.** The IDE must be able to run its preview on any static host. (love.js requires cross-origin isolation because its engine build bakes in `-pthread`; that is unremovable by swapping the Lua VM — it's why this project exists.)
- **Keep the project tree `.love`-compatible.** The same game source runs unmodified on desktop LÖVE — a game made in the browser can go to desktop and back. The **primary target is a LÖVE game that runs natively in the browser**, and a high-fidelity **desktop preview** is the second, valued use of the same engine. The fused per-game artifact for standalone shipping is a later packaging step (#7).
- **Prefer faithful primitives over emulation** where the browser has the real thing (real Web Workers for `love.thread`, not coroutines pretending to be threads).

## The fidelity standard — browser-native correctness first

Two use-cases share this one engine, and they set the priority order every seam decision is measured against:

1. **A correct browser game — the must-hit bar.** As a *browser* game, the engine must be complete and correct; this is achievable and held to 100%.
2. **`.love` source-compatibility — a pillar.** The same source runs unmodified on desktop LÖVE.
3. **Desktop *behavioral* parity — aspirational, the reference, not the pass/fail line.** The browser genuinely cannot match desktop 100% (async-storage durability, HRTF, mic rates, threading), and nobody expects it to; every gap is **declared, never faked**.

So each decision is judged by *"what does a correct browser game do?"*, not *"does it byte-match desktop?"* — desktop is the reference, browser-native correctness is the standard. This generalizes the audio seam's principle (`wasi/audio/DESIGN.md`, Decision 3: *"the bar is device-agnostic fidelity, not desktop parity"*) to the whole engine.

**`wasi/COMPATIBILITY.md` is that standard written out one feature at a time** — every LÖVE feature against desktop and against this build, marked ✓ where the browser has it and we do it, ✗ where the browser has it and we do not, and blank where the browser does not have it at all. A blank is a declared divergence, not a gap: it is the difference between "`love.window.setPosition` is broken" and "a page cannot move its window". Read it before reading a failure count.

## What stays real, what gets touched — the honest claim

The semantically hard code stays verbatim: physics, decoders, render math, module logic, the Lua bindings. The platform-adjacent plumbing gets touched: backend selection, internal thread usage (audio pump, timers) massaged into a single-threaded frame-pump model, and the build system. Expect the diff against upstream to be the evidence — small, seam-shaped, and reviewable — rather than a "95% unmodified" slogan.

## The Lua dialect

Desktop LÖVE 12 runs **Lua 5.1** — LuaJIT 2.1 by default, or PUC Lua 5.1 with `LOVE_JIT=OFF`, which is the default on macOS (`CMakeLists.txt:214`). LuaJIT cannot target wasm, so this build runs **PUC Lua 5.4**, deliberately: it is the current reference interpreter, it compiles cleanly under this toolchain's wasm-EH, and it pairs with LÖVE 12 on the same reasoning — both chosen forward. Recorded as D8 in `wasi/platform/DESIGN.md`.

The engine is unaffected: LÖVE's C++ carries the `LUA_VERSION_NUM >= 504` branches it needs, and the `love.*` modules behave identically. Game *Lua* is where the dialect shows. A game written for 5.1 can need edits — that is a language port, not a lost LÖVE feature, and a ported game is still a LÖVE game. **The compatibility question this project measures is whether a LÖVE feature works, not how a game's Lua was wired up.**

**Three standard-library names moved, and one value rule tightened.** That is what a port has to deal with — and note that none of the four is a LÖVE change: all are PUC Lua 5.1→5.4 language changes, so an 11.5 game needed **no** `love.*` edits to run on 12. Observed running one 11.5 game (Legend of Lua) to a playable state — **41 call sites** across the game and the four libraries it vendors, plus 8 font sizes:

| 5.1 idiom | Under 5.4 | Portable form — runs on both |
|---|---|---|
| `unpack(t)` | removed in 5.2, it is `table.unpack` | `unpack = unpack or table.unpack` |
| `table.getn(t)` | removed in 5.2, it is `#t` | `table.getn = table.getn or function(t) return #t end` |
| `math.atan2(y, x)` | removed in 5.3, it is `math.atan(y, x)` | `math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end` |
| `newFont(path, 4.5*scale)` | errors, "number has no integer representation": LÖVE takes sizes with `luaL_optinteger`, which truncates under 5.1's single number type and raises under 5.3+'s integer subtype | `newFont(path, math.floor(4.5*scale))` |

The right-hand column is the point: each portable form runs under 5.1 *and* 5.4, so porting a game forward costs it nothing on desktop — the source still runs there, and the `.love` pillar holds.

Scale matters more than count. The three *names* were 41 call sites, 29 of them inside vendored libraries (hump, windfield, sti, mlib) — so the port restores the names once in a small prelude (`lua54.lua`, three assignments) rather than forking four third-party libraries. Only the font sizes need editing where they are written, because a wrong *value* has no prelude fix. `wasi/games/legend-of-lua.patch` is the whole port, and it is 59 lines.

**The port is not a fork, and the ported game is not a love.wasm build of it.** Every line of the prelude is `x = x or <the 5.4 spelling>`, so under 5.1 it keeps what is already there and does nothing; `math.floor` on a font size is a no-op where the value was already integral. The patched game therefore runs on desktop LÖVE 11.5 exactly as the original does — the patch is an upstreamable portability fix that costs the game nothing, and the only reason it ships as a `.patch` is that no game is bundled in this repository.

**Evidence: observed**, on one game. This is not a survey of the 5.1↔5.4 delta, and the list should be expected to grow as more games run.

## Toolchain

- `clang-20+` + `wasi-libc`, C++ with **`-fwasm-exceptions`** and the *standardized* wasm-EH encoding — matching lua.wasm's toolchain, which is mandatory: the VM and this engine share one EH machinery, so the LLVM major and EH encoding must agree. Caution, probed 2026-07-07: clang-20's bare `-fwasm-exceptions` **defaults to the legacy encoding**; the standardized one needs an explicit `-mllvm -wasm-use-legacy-eh=false`, which is baked into `wasi/toolchain/build-libcxx-eh.sh` and every build script here — and enforced per artifact by `wasi/toolchain/check-eh-encoding.sh` (disassembly must show `try_table` and zero legacy forms; engines accept both encodings, so only a build-time gate can catch a lost flag). LÖVE's own error path requires full C++ EH — typed catches and exception-object destructors — so the build vendors **LLVM libc++ + libc++abi compiled with wasm-EH** (wasi-sdk's stock libc++ is built without exception support). Wasm `setjmp`/`longjmp` — which Ubuntu's `wasi-libc` omits entirely but FreeType needs — is vendored into the same sysroot (`wasi/toolchain/setjmp`, from wasi-libc); on wasm it is implemented *on top of* wasm-EH, so it rides on the one encoding and needs only the per-TU flag `-mllvm -wasm-enable-sjlj` (single-sourced as `$SJLJ_FLAGS`).
- **Lua VM:** [andy-emerson/lua.wasm](https://github.com/andy-emerson/lua.wasm) (the stock Lua 5.4 reference interpreter — formerly Lua2D/lua-wasi; 0.2.0 sunset the earlier selective-AOT path, which this build never linked), consumed as a **source drop at a pinned commit**, compiled in-tree with this build's own flags, with `LUAW_EXTERNAL_EH` so the real libc++abi owns exception dispatch. LuaJIT is not an option under wasm (no runtime codegen; no wasm interpreter backend), so 5.4 is the deliberate choice — see **The Lua dialect** below and D8 in `wasi/platform/DESIGN.md`. What upstream provides is *build-time* portability: `LUA_VERSION_NUM >= 504` branches in `src/love.cpp` and `common/runtime.cpp` let the engine compile against 5.4, which is what this build stands on.
- **No Emscripten anywhere.** The browser side is a small hand-written WASI preview1 shim (`fd_write`, clocks, `proc_exit` — a few dozen lines) plus the import surface defined by the seams below.

## The three seams (new code)

LÖVE has always delegated exactly these to the host OS; a browser tab is just a different host:

1. **Graphics/window.** Upstream: SDL3 provides the window and GL context, and `graphics/opengl` issues GL calls. Here: no SDL, no EGL. Because WebGL2 *is* OpenGL ES 3.0 — which LÖVE's `opengl` backend already targets — the backend is **reused, not rewritten**: only its GL loader is reseamed, to static WebGL2 imports, so the host's WebGL2 context *is* the GL surface. Two WebGL2 restrictions the desktop paths don't have shape the seam: client-side vertex arrays and buffer mapping are forbidden, so vertex streaming selects `glBufferSubData`; and there is no texture swizzle, so LA8 is reported unsupported and the font atlas falls back to RGBA8. `love.window` is a host-import backend whose `setMode` creates the real `<canvas>` and context, which is what makes `present()` — and with it `captureScreenshot` — real.
2. **Audio.** Upstream: OpenAL device output, plus a mixing and streaming thread. Here: per-source PCM pushed to **WebAudio** through imports — the host mixes and resamples, so love.wasm owns no DSP — on a `webaudio` backend covering both playback and microphone, with `audio/null` as the always-linked fallback. Decoding stays real, in-tree C: the lullaby Wave/Vorbis/FLAC/MP3/ModPlug decoders are compiled into the build.
3. **`love.thread`.** wasm32-wasi is single-threaded; real threading means real **Web Workers** with message-passing. LÖVE's Channel API is share-nothing by design, so semantics mostly survive — but this is an honest, documented behavioral divergence, not a bug to hide.

Everything else the host supplies as imports, which is the same role an OS plays for desktop LÖVE: `love.filesystem` backed by the IDE's project storage (replacing PhysFS), input events forwarded from the DOM into LÖVE's real event queue, and the frame pump driven by `requestAnimationFrame` (the engine runs as a resident coroutine; the host resumes it once per frame — this repo owns its own pump against lua.wasm's embedding surface; lua.wasm's `onelua.c` reactor glue is not used or extended).

## Substitution map — LÖVE 12 desktop vs. this build

| Concern | LÖVE 12 (desktop) | love.wasm (browser) |
|---|---|---|
| Toolchain | system clang/gcc/MSVC per platform | `clang-20+` + `wasi-libc`, target `wasm32-wasi` (standardized wasm-EH encoding, matched with lua.wasm) |
| C runtime | system libc | wasi-libc (+ a few-dozen-line WASI preview1 shim in the host) |
| C++ runtime & exceptions | system libc++/libstdc++, native unwinding | vendored LLVM libc++ + libc++abi built with `-fwasm-exceptions` (wasm-EH) |
| Lua VM | LuaJIT 2.1, or PUC Lua 5.1 with `LOVE_JIT=OFF` — both Lua 5.1 | [lua.wasm](https://github.com/andy-emerson/lua.wasm) — stock Lua 5.4 reference interpreter, source-drop at a pinned commit, `LUAW_EXTERNAL_EH` |
| Window & GL context | SDL3 | `<canvas>` + WebGL2 context via host imports (`love_win`), created by `love.window.setMode`; `t.window.*` drives the canvas |
| GL function loading | glad (runtime loader) | none — static WebGL2 import shim *is* the GL surface |
| Graphics API | OpenGL / Vulkan / Metal backends | WebGL2 — the `opengl` backend **reused**, its GL loader reseamed to static imports (not a new backend; only the loader changes) |
| Audio device | OpenAL (+ mixing/streaming thread) | WebAudio via host imports; pump work folded into the frame loop |
| Audio decoding | in-tree `lullaby` (vorbis/flac/mp3/wav) | the same code, compiled — the lullaby Wave/Vorbis/FLAC/MP3/ModPlug decoders link into the build |
| Physics | in-tree Box2D | the same code, linked — real `love.physics` |
| Font raster & shaping | FreeType + HarfBuzz (external) | same libraries, vendored and compiled to wasm |
| Image codecs | in-tree stb_image, lodepng, ddsparse, tinyexr | **unchanged** |
| Filesystem / `.love` mounting | PhysFS | host-import VFS (`love_fs`) backed by the host's project storage, with `t.identity` namespacing preserved. Read, write and enumerate are real: a separate writable save namespace sits beside the read-only project (D2 rules it OPFS-backed in the browser; that host is unbuilt, #55 — today every host is in-memory and saves do not survive a reload), and reads resolve save-first so a written file shadows a project file without mutating it. Runtime archive/`.love` mounting is a **declared divergence** — D7 closed as deliberately not built (#48); a `.love` as the *boot source* needs it anyway, since the seam takes files and a host unzips in its own JS |
| Input | SDL3 events | DOM keyboard/mouse/pointer/gamepad events forwarded into LÖVE's real event queue |
| Main loop | SDL-driven `love.run` | resident coroutine resumed once per `requestAnimationFrame` tick (this repo's own pump) |
| Timing | SDL timer | `performance.now()` / rAF timestamps via imports |
| `love.thread` | SDL threads (pthreads) | Web Workers + `postMessage` (message-passing Channels — documented divergence) |
| Networking (`enet`, `luasocket`, `luahttps`) | real sockets | **absent** — no faithful browser primitive; declared divergence |
| Video (`love.video`, Theora) | libtheora | **deferred** (`t.modules.video = false`) |
| Tracker music | ModPlug | **vendored** (`wasi/vendor/libmodplug`, decode witnessed in wasm) |
| Microphone | OpenAL capture (`RecordingDevice`) | WebAudio capture via host imports (`getUserMedia` → AudioWorklet). A runtime capability check reports the host's actual mic rate rather than resampling in wasm; rate faithfulness is cross-checked in CI on Chromium and Firefox, and on WebKit when its browser install succeeds (#33). Permission-deny is not auto-witnessed |
| Shipped form | per-platform executables + shared libs | the `love.wasm` engine artifact, with the JS host riding in the deployment page; final delivery (embedded vs fetched-by-URL) is #7, open pending measurement, recommended shape recorded there |

## conf.lua

`love.conf(t)` is parsed and honored identically to desktop: `t.window.*` drives the canvas and page title; `t.modules.*` gates which subsystems must exist for a given game (so a game with `t.modules.physics = false` previews before the Box2D link lands); `t.identity` namespaces save data. Settings with no browser equivalent (`t.window.display`/`x`/`y`, exclusive fullscreen, multi-window) are explicitly mapped or no-op'd, and documented — never silently faked.

## Dependency disposition (the build map)

**Replaced at the seams (not compiled):** SDL3 · OpenAL · PhysFS (`src/libraries/physfs` — replaced by the host-import VFS backend `wasi/platform/fs-backend.cpp`; read path landed at step 6.2, write + save-dir path at step 6.7) · glad (GL loader — the WebGL import shim takes its place) · LuaJIT (→ lua.wasm 5.4) · `lua53/lutf8lib` (5.4 has `utf8` natively). Note `lua53/lstrlib` **is** compiled: `love.data.pack`/`unpack`/`getPackedSize` call into it unconditionally.

**Kept, real, already in-tree:** `box2d` · `dr` (flac/mp3) · `stb` (stb_image) · `lodepng` · `ddsparse` · `tinyexr` · `Wuff` (wav) · `lz4` · `xxHash` · `noise1234` · `utf8` · `glslang` (LÖVE's GLSL parser + shader reflector, used by `graphics/Shader.cpp` for all backends — **compiled into the wasi graphics build** with two carried portability patches; see step 4) · the `sound/lullaby` decoder layer · `src/scripts` (boot Lua).

**Vendored from outside, real, compiled to wasm.** Each is pinned with its license beside it, and each carries a witness of its own.

| Dependency | Version | Why it is here |
|---|---|---|
| FreeType | 2.13.3, TTF/OTF subset | glyph rasterisation behind `love.font` |
| HarfBuzz | 14.2.1 amalgamation, with hb-ft | text shaping, which LÖVE 12 requires |
| libvorbis | 1.3.7, decode subset | Ogg Vorbis decoding |
| libogg | 1.3.6 | the framing layer under Vorbis |
| libmodplug | — | tracker music |
| zlib | — | compression behind `love.data` |
| LLVM libc++ / libc++abi | 20.1.2, wasm-EH build | wasi-sdk's stock libc++ ships without exception support, and LÖVE's error path needs full C++ EH |
| wasi-libc `setjmp`/`longjmp` | — | Ubuntu's wasi-libc omits it entirely and FreeType needs it |

**Excluded from the wasi build — but NOT deleted from the tree:** `graphics/vulkan` + `graphics/metal` backends and their support libraries (`volk`, `vulkanheaders`, `vma`, `vk_video`, `spirv_cross`) · `video/` + Theora (deferred; `t.modules.video = false`) · `enet`, `luasocket`, `luahttps` (networking — no faithful browser primitive; declared divergence) · `platform/xcode`, `extra/nsis`, `extra/windows` (other platforms' build glue).

Exclusion happens in the build, not with `rm`: deleting upstream files would bloat the diff, poison rebases, and break the "diff is the evidence" rule. The tree stays upstream-shaped; the wasi build compiles the subset.

**Module disposition — the declared end state (issue #27).** The module set grows incrementally in each build's `config.h`; this states the *intended* disposition of every `love.*` module so the end state is declared, not implied. Three tiers:

| Tier | Meaning | Modules |
|---|---|---|
| **Kept + seamed (real)** | real engine code over a browser seam | `data`, `math`, `filesystem` (read 6.2, write + save-dir 6.7, enumerate via `fs_list`), `graphics` (4), `window` (6.3), `event`/`keyboard`/`mouse` (6.4), `joystick`/`gamepad` (browser Gamepad API, 6.5), `touch` (browser TouchEvent, on the `love_input` record), `timer`/`system` (6.6), `image`, `font`, `audio` (5), `sound` (lullaby decoders linked), `physics` (Box2D, linked); and — faithful, link/seam pending — `thread` (Web Workers, step 7) |
| **Warned stub (preview-limited, non-fatal)** | no faithful browser primitive; **first use** emits a one-time `[love.wasm preview] …` notice and never a silent wrong answer. Two mechanisms, same contract: a *compiled* module warns from C++ (`preview_warn_once`, `wasi/platform/preview-warn.{h,cpp}`) and returns a safe default; a module not compiled at all is supplied by the boot wrapper, which satisfies `require` and reports on the read of `love.<name>` | **`sensor`** (accelerometer/gyro — compiled and linked, #27), **networking** (`enet`/`luasocket`/`luahttps` — no raw TCP/UDP in a browser), **`video`** (Theora dropped — CPU-decoding single-threaded in wasm would stutter, which is *lower* fidelity than a clean "not in preview" notice; a future `<video>` seam is the right path) |
| **Fatal until ported** | essential; a loud hard error at the seam until built — a transient tier | *(empty; `filesystem` was the last to leave it)* |

The warned-stub tier is the graphics ceiling's cousin (#36): report unsupported honestly, never emulate. Keeping `love.sensor` enabled as a warned stub also moots the upstream joystick/sensor `#ifdef` bug (#23) by config — and is why the union build links `sensor` alongside `joystick` rather than leaving either to the boot wrapper: stubbing a module whose backend exists and is CI-enforced would hide a working feature.

**Found treasure:** `testing/` is a runnable LÖVE-project test suite — a ready-made conformance corpus. Running it under this build and under desktop LÖVE, and diffing the outcomes, is the parity witness for every claim this README makes.

## Build order

Each step is done when a witness proves it, not when the code compiles. Sub-step detail lives in each witness script's own header; how each step was reached lives in the commit log.

| Step | What | State |
|---|---|---|
| 0 | Toolchain bring-up — wasm-EH libc++/libc++abi built from LLVM source | **Done.** Typed catch through a base class with `what()` intact, a payload surviving the throw, a destructor run during unwind, and wasm `setjmp`/`longjmp` coexisting with wasm-EH in one module — on node:wasi, Chromium, and Firefox/SpiderMonkey, the non-V8 cross-check (#5) |
| 1 | lua.wasm standalone in a browser over the minimal WASI shim | **Done.** Built from source with the same clang-20 and reproduced locally rather than trusted from its CI; its official-suite bundle passes in Chromium |
| 2 | This repo's own frame pump against the lua.wasm source drop | **Done.** Lua runs as a resident coroutine resumed once per frame; a Lua error is reported with traceback while the VM survives and re-boots. Pinned at lua.wasm `0.2.0`, provenance CI-diffed against a fresh clone |
| 3 | LÖVE core boot — `love.boot`, module registration, real `love.data` and `love.math` | **Done.** `require "love"`, `_version` 12, a typed `love::Exception` arriving as a Lua error through `luax_catchexcept`, absent modules loudly absent. Found treasure: `boot.lua` returns a main loop that already yields once per frame, so upstream's control flow is natively pump-shaped |
| 4 | Graphics — render path onto WebGL2 imports | **Done.** The `opengl` backend **reused**, only its GL loader reseamed. Primitives, textures, user shaders, off-screen canvases, FreeType text, blend/scissor/stencil, Mesh/SpriteBatch/ParticleSystem, transforms, multiple render targets, MSAA resolve, the engine's own readback, GraphicsBuffer, instancing, depth test, ImageFont. The WebGL2 ceiling — compute, SSBO, indirect draw, genuinely absent on ES 3.0 — is reported unsupported and rejected catchably, a declared divergence (#36) |
| 5 | Audio — render path onto WebAudio | **Done.** Per-source PCM pushed to WebAudio voices; the host mixes and resamples, so love.wasm owns no DSP. Playback and microphone both real, a 440 Hz tone recovered through a real `OfflineAudioContext` and from the game-facing `SoundData`. Permission-deny is not auto-witnessed |
| 6 | The SDL-shaped platform seam — filesystem, window, input, joystick, timer/system, and the embedding contract | **Done.** Ordered filesystem-first because LÖVE reads `conf.lua` before it opens a window. Its capstone is the embedding contract: the filesystem write path with a separate writable save namespace beside the read-only project, and a host-callable `pump_invalidate()` so write → invalidate → re-require composes into live edit. Design and open decisions in `wasi/platform/DESIGN.md`; the host-import surface a consumer fulfills in `wasi/platform/EMBEDDING.md` |
| 7 | `love.thread` via real Web Workers | **Not started.** Design-doc-first. Message-passing Channels are the only faithful option, since the no-COOP/COEP pillar rules out `SharedArrayBuffer`; LÖVE's Channel API is share-nothing by design, so semantics mostly survive. Sequenced after games actually run, because most `.love` games do not use it |
| 8 | Packaging | **Not started.** The recommended shape is recorded on #7 — one product file (`love.wasm`) with the host inline in the deployment page — leaving embedded-vs-fetched-by-URL to be decided by measuring cold and warm load in LoveIDE rather than by argument |

Modules with no faithful browser primitive are declared, not faked: networking (`enet`/`luasocket`/`luahttps`) is absent, `love.video` dropped Theora because CPU-decoding it single-threaded would stutter — lower fidelity than an honest notice — and runtime archive/`.love`-zip mounting stays unbuilt by decision (D7, #48): neither rebuilding PhysFS's zip archiver in wasm nor unzipping host-side earns its cost against the demand, and a `.love` as the boot source never needed it.

The **IDE itself** (LoveIDE: editor, git-wasm-backed save flow, agent live-edit UX) is **not a step here** — it is a downstream repo that *consumes* the step-6.7 embedding contract (documented in `wasi/platform/EMBEDDING.md`). love.wasm's responsibility ends at shipping and documenting that contract; the consumer's roadmap belongs to the consumer.

## Reproducing the witnesses

Every witness is one command. It needs `PREFIX` pointing at a step-0 wasm-EH sysroot, Node ≥ 24.15, and `playwright-core` with Chromium; it builds what it needs and exits non-zero if its claim is false.

```sh
PREFIX=/path/to/wasi-eh wasi/platform/run-game.sh
```

Each runs every engine it can reach, and every leg must pass. A Chromium-only witness is one that needs a real WebGL2 context, which node has no equivalent for. All of them run in CI on every push or pull request to `wasi` (`.github/workflows/witness.yml`) — except `wasi/games/run.sh`, which is on demand by design.

| Witness | What it proves | Engines |
|---|---|---|
| `wasi/witness/run.sh` | wasm-EH: typed catch, unwind destructors, `setjmp`/`longjmp` coexistence | node, Chromium, Firefox |
| `wasi/pump/run.sh` | the frame pump: boot to first yield, five frames, error-with-traceback survival, clean quit, EH selftest | node, Chromium |
| `wasi/boot/run.sh` | LÖVE core boot, real `love.data`/`love.math`, typed exceptions as Lua errors | node, Chromium |
| `wasi/graphics/run.sh` | the full 2D drawing surface through the real backend, and the WebGL2 ceiling as a graceful divergence | Chromium |
| `wasi/audio/run.sh` | playback and microphone tone recovery, including a real-capture leg against a fake device | node, Chromium |
| `wasi/platform/run.sh` | the `love_fs` read round-trip, byte-exact through embedded NULs and high bytes | node, Chromium |
| `wasi/platform/run-fs2.sh` | the real `love.filesystem` module on that seam | node, Chromium |
| `wasi/platform/run-win.sh` | the real `love.window`, and with it step 4's `captureScreenshot` | Chromium |
| `wasi/platform/run-input.sh` | `love.event`/`keyboard`/`mouse` on the input push seam | node, Chromium |
| `wasi/platform/run-joystick.sh` | `love.joystick`/`gamepad` over the Gamepad API, poll-and-diff into synthesized events | node, Chromium |
| `wasi/platform/run-timer-system.sh` | the real `love.timer` and `love.system` | node, Chromium |
| `wasi/platform/run-frame.sh` | the first full `main.lua` frame: conf → canvas → load → draw → present | Chromium |
| `wasi/platform/run-embed.sh` | the embedding contract: write path, save namespace, and the reload invariant | node, Chromium |
| `wasi/platform/run-sensor.sh` | the warned stub and its one-time `[love.wasm preview]` notice (#27) | node, Chromium |
| `wasi/platform/run-physics.sh` | `love.physics` on the in-tree Box2D — a body falls under gravity | node, Chromium |
| `wasi/platform/run-sound.sh` | the `love.sound` lullaby decoders — a real Ogg Vorbis asset decoded to PCM | node, Chromium |
| `wasi/platform/run-fs-list.sh` | `love.filesystem` enumeration over `fs_list`, project and save merged and de-duped | node, Chromium |
| `wasi/platform/run-game.sh` | the union: a real game, with sound, physics and drawing together | Chromium |
| `wasi/shell/run.sh` | the interactive shell: a project loaded from disk, real DOM key events moving the game and stopping on release, and a module edit reaching the running instance | Chromium |

`wasi/sweep/run.sh` is not a witness but a probe: `-fsyntax-only` over every engine-module translation unit under the build's exact contract flags, so no module's status is left unknown (#9).

In an interactive session `.claude/hooks/session-start.sh` brings the toolchain up on start — `clang-20` from Ubuntu's own repos, Node from the `nodejs.org` tarball (the sandbox denies `apt.llvm.org` and `deb.nodesource.com`), `playwright-core` over the pre-provisioned Chromium — and fetches the prebuilt wasm-EH sysroot published by `.github/workflows/publish-sysroot.yml`, so the witnesses run green in-session without a minutes-long from-source sysroot rebuild in every ephemeral container.

## Upstream relationship — branches, patches, and the 12.0 swap

LÖVE 12 is unreleased but functionally complete (its open milestone items are polish, several in backends this build excludes). This fork does not wait for it, does not finish it, and must be able to adopt the released 12.0 cheaply. The machinery:

**Branch model.** `main` is a pristine mirror of upstream `love2d/love` — never committed to, only fast-forwarded when adopting a new upstream commit. **`wasi` is the working branch and the repo default**; everything this fork adds lives there. At any moment, `git diff main...wasi` is the complete, current answer to "what did this fork touch" — the evidence for the honest claim above.

**Three lanes for changes:**

1. **Wasi-only code** — new backends, build files, the pump. Additive by design (new files, minimal edits to shared code), lives on `wasi` forever, rebases near-conflict-free.
2. **Generic fixes LÖVE needs** — cut a topic branch from the *upstream base commit* (not from `wasi`), PR it to love2d, cherry-pick it into `wasi` meanwhile. When upstream merges, the carried copy is shed automatically at the next rebase (git recognizes already-applied patches). Carried, never kept.
3. **Fork-private edits to shared engine code — not allowed.** If upstream declines a fix this port needs, that becomes a recorded design decision here, never a silent divergence.

**The swap.** Adopting a new upstream — a fresh nightly or the 12.0 release itself — is: fast-forward `main` to the new commit, rebase `wasi` onto it, watch lane-2 patches fall out, update the base pin at the top of this README. Because lane 1 is additive and lane 2 self-sheds, the expected cost is an afternoon, not a migration.

## Constitution

- **One artifact, no parts.** The product is one engine artifact — `love.wasm`; the JS host is deployment-page scaffolding, not a second product file, and Workers spawn from Blob URLs. Whether the wasm ships embedded or fetched by URL is #7, decided by measurement; the recommended shape is recorded on the issue. A repo may have a build; its output may not have pieces.
- **Pin-by-commit in both directions.** Upstream base pinned above; lua.wasm pinned in-tree; LoveIDE pins this repo's artifact by commit. Nothing floats.
- **Claims match evidence.** A subsystem "works" when the `testing/` corpus exercises it in a real browser and matches desktop behavior. Anything less is labeled as less.
- **Upstreamable by construction.** The web backend is written against upstream's own abstractions; small generic seams are offered upstream as they arise; the goal-state conversation — a web platform for LÖVE proper — stays open.

## Working agreement

How work is planned, executed, reviewed, and integrated here is governed by [`AGENTS.md`](AGENTS.md) — the [working agreement](https://github.com/andy-emerson/working-agreement) adopted verbatim, so it updates by replacement: Human and Agent roles, the Plan → Develop → Assess → Review phases, claims graded on an evidence ladder, and a truth-seeking documentation review that checks the code review's optimism. [`CONTRIBUTING.md`](CONTRIBUTING.md) is its craft companion — how code, tests, and prose are written — and its §7 holds this repository's own conventions: the branch model (trunk is `wasi`, because `main` mirrors upstream), what counts as evidence here, and the toolchain invariants.

## Credits & license

zlib license, same as upstream (`license.txt`). LÖVE is the work of the LÖVE Development Team — this fork exists to carry it somewhere new, not to claim it. The Lua layer is PUC-Rio Lua 5.4, the stock reference interpreter, vendored via [andy-emerson/lua.wasm](https://github.com/andy-emerson/lua.wasm) (which through 0.1.x also carried Hugo Musso Gualandi's lua-aot research, retired at 0.2.0).
