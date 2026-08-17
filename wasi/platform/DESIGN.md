# love.wasm — design

What love.wasm is, what it is for, and the principles every seam is measured
against. Design forks and their rulings are in
[`../DECISIONS.md`](../DECISIONS.md); open work is in
[GitHub Issues](https://github.com/andy-emerson/love.wasm/issues). This
document changes rarely — if a passage here needs updating every session, it is
living status wearing a design document's clothes and belongs in Issues.

## 1. Goals

Stated as **constraints** — the rules on *how* — and **objectives** — what we
are trying to do. Objectives are either **requirements**, which always win a
conflict, or **preferences**, which are ranked. Each is either a **threshold**,
which is satisfied and then stops pulling, or an **optimization**, which is
never satisfied because more is always better.

Two requirements in conflict is an inconsistency in the design, not a trade-off
to manage. It is resolved immediately, usually by demoting one to a preference.

### 1.1 Constraints

**Machine-given** — not chosen, and not negotiable:

- A wasm module can reach nothing on its own: no filesystem, no GPU, no canvas,
  no input, no audio. Everything arrives as a function the embedder supplies.
- wasm forbids runtime code generation, so there is no JIT. Every Lua-in-wasm is
  interpreter-class, LuaJIT included — which is why it is not an option here.
- wasm32-wasi is single-threaded. Real concurrency means real Web Workers with
  message passing.
- Browser WebGPU accepts WGSL only; SPIR-V was dropped from the web API.
- A frame is roughly 16.7 ms, and the main thread must never block.

**Principle-given** — chosen, and therefore excluding options:

- **The engine is real LÖVE, compiled.** Not a reimplementation of the `love.*`
  API. A reimplementation was considered and rejected: multi-year effort, and
  never bit-exact. Every Lua-facing engine call funnels through
  `luax_catchexcept`'s typed C++ exception handling at 145 call sites;
  imitations get details like that subtly wrong forever.
- **No Emscripten, no pthreads, no SharedArrayBuffer, no COOP/COEP.** The
  artifact must run on any static host, with no server configuration. This is
  the constraint the project exists to satisfy — love.js requires cross-origin
  isolation because its build bakes in `-pthread`, and no amount of swapping the
  Lua VM removes that.
- **The project tree stays `.love`-shaped.** The unit of a game is Lua source
  and assets, not a compiled artifact.

### 1.2 Requirements

| | Objective | Type |
|---|---|---|
| **R1** | A game that runs in the browser is **correct** — complete and faithful as a *browser* game | Threshold, held at 100% of what the browser can do |
| **R2** | An edit to a running game **applies live**, with state intact | Threshold — it works or it does not |
| **R3** | Every divergence from desktop is **declared, never faked** | Threshold |

R1 is the bar every seam decision is measured against: judge by *"what does a
correct browser game do?"*, not *"does it byte-match desktop?"*

R2 is why ahead-of-time compilation of game Lua cannot be the default path — it
is mutually exclusive with hotswap, and a preference never beats a requirement
(D0 / Q1).

R3 is what makes `COMPATIBILITY.md` a design document rather than a scoreboard:
a blank means the browser does not have the feature at all, which is a declared
divergence, not a gap.

### 1.3 Preferences, in order

| | Objective | Type |
|---|---|---|
| **P1** | **The preview predicts desktop.** A game built in the browser for desktop should look, feel and behave in the preview as it will on desktop | Optimization |
| **P2** | **Existing LÖVE games play** — most games written for 11.5 / Lua 5.1, directly or after an automatic shim | Optimization, with a floor at *most* |
| **P3** | **The artifact is small** | Optimization |
| **P4** | **The engine is fast** | Optimization |

P1 is why the engine is compiled real LÖVE rather than an imitation, and why
WebGPU is not optional: LÖVE 12 has compute shaders and WebGL2 has none, so a
game using one cannot be previewed at all (D10).

**Conflicts already resolved, and the rulings they produced:**

- **R2 over P4** — live edit beats speed. Closes ahead-of-time compilation out
  of the preview path (Q1).
- **R1 over P1** — browser-native correctness beats desktop parity. A browser
  cannot match desktop on storage durability, HRTF, microphone rates or
  threading, and is not expected to.
- **P1 over P2** — the preview's fidelity beats shader-source portability. A
  game's shaders no longer run unmodified on desktop LÖVE (D11); its logic
  still does.


## The other principle: the game stays pure LÖVE; the host holds the powers

Features (live-edit, console, reload) and fidelity need not conflict, because the
feature surface is **host-side, never a game-facing API**. The shipped `.love` is
a normal LÖVE 12 game: run it on desktop LÖVE and it behaves identically, because
none of the live-edit / console / reload machinery is baked into the artifact or
visible to Lua. The IDE mutates the project *out of band* through host imports;
the game never references any of it.

The single place this tempts a fidelity violation is the console-control idea
([`../DECISIONS.md`](../DECISIONS.md), D6): if "control what's in the console"
became a `love.log()` the game *calls*, it would break on other engines. It
stays faithful instead — `print` is `print`; control is host-side.

## The build order

The step numbers cited across the repository — CI step names in
`witness.yml`, build-script headers, `EMBEDDING.md`'s title, `readme.md`'s
status line — were defined in a handoff document retired in `03ab2ae`; this
ledger is their durable home. Two sequences, engine first:

**Build-order steps** — the engine, bottom up. Each step's witness is its
evidence.

| step | what | where it stands |
|---|---|---|
| 0 | wasm-EH C++ toolchain: typed catch, carried payload, destructors on unwind | done — `wasi/witness/run.sh`, artifact 1 |
| 1 | setjmp/longjmp beside wasm-EH in one module (wasi-libc omits SjLj; FreeType needs it) | done — `wasi/witness/run.sh`, artifact 2 |
| 2 | the frame pump: the pump ABI over embedded Lua | done — `wasi/pump/` |
| 3 | `love.boot`: LÖVE's own boot wrapper to a first yielded frame | done — `wasi/boot/` |
| 4 | `love.graphics` on real WebGL2 | done — `wasi/graphics/` |
| 5 | `love.audio`: the webaudio seam | done — `wasi/audio/` (its `DESIGN.md`) |
| 6 | the platform seams, 6.1–6.7 in the ledger below | **complete** |
| 7 | `love.thread` on Web Workers | unbuilt; design-doc-first (#66) |
| 8 | *(dropped)* was packaging / LoveIDE integration | packaging is now D14; the surviving measurement question is #7, its disposition #82 |

**Beta steps** — playability on top of the built engine ("Beta" says only
that no release exists yet):

| step | what | where it stands |
|---|---|---|
| 1 | the interactive shell — serve a project, play it, live-edit it | done — `wasi/shell/run.sh`, CI |
| 2 | a real third-party game ported and playable | witnessed on demand — `wasi/games/run.sh` (fetches a third party's repo, so deliberately not in the per-push gate) |
| 3 | corpus parity against `testing/` with every failure classified | done — `wasi/corpus/run.sh`, CI |

## Sub-step ledger (step 6 — all landed)

Boot order puts filesystem first: LÖVE reads `conf.lua`/`main.lua` before it
opens a window. Step 3's boot witness proves LÖVE's `main()` dies *at* the
`love.filesystem` seam; step 6's job is to carry it *past* that line.

- **6.1 — `love_fs` VFS seam, read round-trip.** **Done** (this note's companion
  code). Isolates the host↔wasm file-bytes plumbing — a binary asset with
  embedded NULs recovered byte-exact through the seam under node:wasi + Chromium
  — before the real module rides on it. No LÖVE core linked; the analogue of
  graphics' 4.1a raw-GL leg.
- **6.2 — real `love.filesystem` on the seam. Done** (scripted; node:wasi + real
  Chromium; CI step added). D1=A: a real `love::filesystem::wasi_fs` backend
  (`wasi/platform/fs-backend.{h,cpp}`) replaces the PhysFS module and the boot
  stub. `require("love.filesystem")` now succeeds (the step-3 stop-line is gone)
  and `read`/`getInfo`/`openFile`/`File:read`/`load`/`require` recover host files
  byte-exact (incl. binary/NUL) through the real module. Driven directly from a
  witness coroutine (not full `boot.lua`, which needs `love.system`/window/event
  — those are 6.3–6.6). Read-only: `write`/`mount`/enumerate throw/false loudly,
  not faked; the write/save-dir path (D2's OPFS) is the 6.7 sub-step. Shared
  engine touched only through guarded seams (`Filesystem.cpp` `getExecutablePath`
  + `<filesystem>`; `wrap_Filesystem.cpp` factory + SDL `extloader`), byte-clean
  for desktop. The `extloader` native-C `require` searcher is dropped on wasm (no
  `dlopen`) — a declared divergence.
- **6.3 — `love.window`. Done** (scripted; real Chromium; CI step added). D3=A: a
  real `love::window::wasm` backend (`wasi/platform/window-backend.{h,cpp}`) on a
  `love_win` host seam (`window_setmode`/`window_get_pixel_dimensions`/
  `window_present`). `setMode` drives the host to create the real `<canvas>` +
  WebGL2 context and make it current for the `love_gl` imports **before**
  `graphics->setMode(nullptr,…)` runs — retiring the fake `setMode`
  `graphics-ext.cpp` plays. With a registered, open window, `Graphics::isActive()`
  is true, so `present()` runs for real — which **completed step 4**:
  `captureScreenshot` reads the presented backbuffer (FBO 0) back through
  `newImageData`, drawn + clear pixels recovered exactly. One guarded seam
  (`wrap_Window.cpp` factory), byte-clean for desktop; the window-irrelevant
  surface (fullscreen, displays, dialogs, …) is honest no-ops.
- **6.4 — `love.event` + keyboard/mouse. DONE** (node:wasi + real Chromium; CI
  step added). The real `love.event`/`love.keyboard`/`love.mouse` on the
  `love_input` host seam (`wasi/platform/input-backend.{h,cpp}`), replacing the
  three SDL backends. This is the first **host→guest push** seam — every prior
  seam was guest→host pull (guest asks, host answers synchronously); DOM events
  fire on the browser event loop, the host queues them, and
  `event::wasm::Event::pump()` drains that queue once per frame, translating each
  record into a `love::event::Message` (the exact job `event/sdl/Event.cpp
  ::convert` does for SDL) that the unchanged Lua dispatch in `callbacks.lua`
  fires as `love.keypressed` / `love.mousepressed` / … . One shared `InputState`:
  `pump()` is the single writer (pressed-key/scancode sets, mouse position,
  button mask), keyboard/mouse are pure readers — the same split SDL has
  (`SDL_PumpEvents` updates what `SDL_GetKeyboardState`/`GetMouseState` read). The
  DOM↔LÖVE name/button mapping lives in C++ next to LÖVE's Key/Scancode enums;
  the physical-`code`→US-key translation is a declared, documented divergence
  from SDL's live-layout mapping (the typed character still rides through as the
  `textinput` payload). Three guarded factory seams (`wrap_Event`/`wrap_Keyboard`/
  `wrap_Mouse`), byte-clean for desktop, plus one generic version-guarded
  `lua_cpcall`→`lua_pcall` shim (Lua 5.2 removed `lua_cpcall`; `love.event`'s
  modal-draw path is the only caller — offered upstream). `love.image` +
  `love.filesystem` link because `love.mouse`'s Cursor is image/file-backed;
  witnessed windowlessly, so it runs on node **and** Chromium (no WebGL2).
  `isModifierActive` (lock latch) and pointer confinement are the honest
  warn-once edges. (Custom image cursors were one too until #58: `newCursor` now
  sends the RGBA8 pixels + hotspot through `input_new_cursor_image` and the
  browser host sets a data-URL CSS cursor; the 6.4 witness asserts the host
  received the exact bytes. #58 also routed the host's FOCUS/MOUSEFOCUS records
  into the shared snapshot, where `love.window.hasFocus`/`hasMouseFocus` read
  them over weak hooks.)
- **6.5 — `love.joystick` + `love.gamepad`. DONE** (node:wasi + real Chromium; CI
  step added). The real `love.joystick`/`love.gamepad` on a new `love_gamepad`
  host seam (`wasi/platform/joystick-backend.{h,cpp}`) over the browser **Gamepad
  API** — **required for fidelity, not optional**: gamepads are a capability the
  browser genuinely *has*, so warned-stubbing them (as we did `love.sensor`, a
  genuinely-absent capability) would violate the "correct browser game held to
  100%" bar. Unlike 6.4's host→guest *push* queue, the Gamepad API is
  **poll-based** (no event stream, only a per-frame snapshot array) — so the seam
  is guest→host *pull* (`gamepad_count`/`gamepad_read`, mirroring
  `navigator.getGamepads()`): once per frame the guest reads the current gamepad
  slots and **diffs** them against the previous poll to *synthesize* the
  `joystickadded`/`joystickremoved`, `joystick{pressed,released,axis}` and
  `gamepad{pressed,released,axis}` events SDL would have delivered, emitting BOTH
  the raw-joystick and the mapped-gamepad event for one physical change exactly as
  SDL sends both families. That synthesis **reuses 6.4's push mechanism**: the
  diffed events are `love::event::Message`s pushed onto the same `love.event`
  queue. The poll is wired into 6.4's `pump()` by a **weak hook**
  (`wasi_poll_gamepad_events`, declared null in `input-backend.cpp`, defined
  strong in `joystick-backend.cpp`), so the 6.4 build — which does not link the
  joystick module — is unaffected (the symbol is null and the call skipped; the
  6.4 witness re-runs green with the hook in place). LÖVE's `love.gamepad` is
  SDL's standard-controller mapping, ~1:1 with the **W3C "standard gamepad"**
  mapping, so it rides it directly; the W3C-index↔LÖVE-button and axis translation
  lives in C++ next to LÖVE's enums (host forwards browser truth, the backend owns
  LÖVE semantics — the same split the input backend has). W3C buttons 6/7 (the
  analog triggers) map to LÖVE trigger **axes**, not buttons, so a trigger emits
  `gamepadaxis`, matching SDL. One guarded factory seam (`wrap_JoystickModule.cpp`,
  byte-clean for desktop under `#else`). Enabling `love.sensor` (the #27 warned
  stub) is **required** here, not incidental: `wrap_Joystick.cpp` registers
  `Joystick:getDevicePowerInfo`/`:getDeviceConnectionState` unconditionally but
  only *defines* them under `LOVE_ENABLE_SENSOR` (upstream bug #23), so joystick
  won't link with sensor off — enabling it moots #23 by config. The honest
  warn-once edges: ~~vibration~~ (**closed by #58**: `setVibration` /
  `isVibrationSupported` ride two more `love_gamepad` imports, the host drives
  the pad's `vibrationActuator` with a `'dual-rumble'` effect and records every
  request in an effects log the 6.5 witness asserts — the "unwitnessable"
  objection fell once the effects log made the call reaching the host
  observable, the same standard the cursor-shape effects meet), the
  **gamepad-mapping string** (no SDL controller DB in
  the browser — the W3C standard mapping is implicit, so `getGamepadMappingString`
  / `setGamepadMapping` / `loadGamepadMappings` are empty/no-op), and **gamepad
  motion sensors** (no gamepad sensor stream). The input path itself is real.
  Witnessed windowlessly on node **and** Chromium.
- **6.5b — `love.touch`. DONE** (node:wasi + real Chromium; not a numbered step
  in the original build order — it was the last module left merely *unbuilt*,
  and a real game reaching a playable state is what made its absence worth
  closing). `wasi/platform/touch-backend.{h,cpp}` over the browser's
  **TouchEvent** API, the sibling of `touch/sdl/Touch.cpp`.

  It adds **no host seam**. A browser reports touches as events, so they arrive
  as three more record types (13/14/15) on the existing `love_input` record —
  next to the mouse and keyboard ones, the same way finger events sit beside
  them in an SDL queue. Pressure overlays the `code[]` field, which a touch
  record does not use. One guarded factory seam (`wrap_Touch.cpp`, byte-clean
  for desktop under `#else`, verified by preprocessing).

  The module/pump division is upstream's, deliberately: the live-touch list
  lives in the module and the **event pump** updates it as it converts, which is
  where `event/sdl/Event.cpp` does it and why (`touch/sdl/Touch.h`: querying
  SDL's own state races a game iterating `getTouches()`). Honest edges: a
  browser gives absolute positions and no per-touch delta, so the host remembers
  each identifier's last position and computes `dx`/`dy`; `deviceType` is always
  `touchscreen`, since a browser has no indirect-touch kind to report and mouse
  input arrives as `MouseEvent` rather than being synthesized into this path;
  and `t.trackpadtouch = true` is a warn-once no-op, because a page cannot ask
  the OS to deliver a trackpad as touch (`false`, the default, is exactly what a
  browser already does, so it reports nothing).
- **6.6 — `love.timer` + `love.system` + the first full `main.lua` frame. DONE**
  (6.6a windowless on node:wasi + real Chromium; 6.6b Chromium-only; CI steps
  added). Two phases:
  - **6.6a — `love.timer` + `love.system`.** `love.timer` is a concrete class (no
    backend split): `Timer.cpp` routes through
    `clock_gettime(CLOCK_MONOTONIC)`/`gettimeofday` under a guarded `LOVE_WASM` arm
    of its POSIX `#if` (wasi-libc provides both; the WASI host fulfils
    `clock_time_get`), and `love::sleep` is an **honest browser no-op**
    (`wasi/platform/delay-wasi.cpp`) — a browser must not block its main thread;
    frame cadence is the host's `requestAnimationFrame`, not a guest spin — in
    place of the SDL `SDL_DelayNS` `common/delay.cpp` (excluded from every wasm
    build). `love.system` is backend-split: a real `love::system::wasm::System`
    backend (`wasi/platform/system-backend.{h,cpp}`) on a new `love_system` host
    seam carries the **genuine browser capabilities** — processor count
    (`navigator.hardwareConcurrency`), the text clipboard (a host cell fronting the
    async Clipboard API), `openURL` (`window.open`), preferred locales
    (`navigator.languages`) — and reports honest defaults for the rest (memory size
    0; power `unknown` — the Battery Status API is gated across engines);
    `getOS()` returns `"Web"` via a guarded seam in `System.cpp`. Three guarded
    seams (`Timer.cpp` POSIX arm, `System.cpp` `getOS`, `wrap_System.cpp` factory),
    byte-clean for desktop.
  - **6.6b — the first full `main.lua` frame (THE MILESTONE).** The **union** build
    (`build-frame.sh`: real filesystem 6.2 + window 6.3 + graphics/opengl-on-WebGL2
    step 4 + image + font + event/keyboard/mouse 6.4 + timer + system 6.6a + data +
    math) boots LÖVE's **real `boot.lua`** under the pump and runs an actual game
    end to end: `conf.lua` (read through the real `love.filesystem`) sizes/titles
    the canvas, `love.window.setMode` opens the real WebGL2 context at the conf
    dimensions, `love.load` runs (a unique marker to the host tap proves it), and
    `love.run`'s loop yields once per pumped frame running
    `event.pump`/`timer.step`/`update`/`clear`/`draw`/`present`. `love.draw` fills
    the canvas RED; the driver reads the presented backbuffer's centre pixel back
    through the WebGL2 context and recovers `(255,0,0,255)` — proving
    conf → canvas → load → draw → present ran a real frame. `frame-deps-stub.cpp`
    replaces the windowless graphics build's `graphics-deps-stub.cpp` (the union
    compiles the real filesystem + timer, so only the genuinely-absent
    audio/video/thread module symbols love.graphics links against are stubbed —
    reusing the graphics stub would duplicate `File::type`/`luax_getdata`/
    `Timer::getTime`). `love.joystick` is deliberately not linked (the event module
    needs only the joystick HEADER; `input-backend.cpp`'s `wasi_poll_gamepad_events`
    weak hook stays null, so `pump()` skips it). Chromium-only — a real WebGL2
    context, node has none — exactly like the 6.3 window witness and the step-4
    graphics witnesses; no node leg (expected). The one integration subtlety: the
    canned `conf.lua` disables every module the union does NOT link
    (thread/joystick/touch/sound/sensor/audio/video/physics), because `boot.lua`'s
    module loop `require`s each enabled module unconditionally.
- **6.7 — the embedding contract. DONE** (scripted; node:wasi + real Chromium; CI
  step added) — the runtime's capstone, and the boundary of this repo's
  responsibility. What makes the runtime *consumable* by a live-edit host:
  - **The filesystem write path** — the real `love.filesystem`
    `write`/`append`/`remove`/`createDirectory`/`File:open("w"/"a")` and the save
    dir, over three new `love_fs` write imports (`fs_write`/`fs_remove`/`fs_mkdir`,
    entirely in the out-of-tree `fs-backend.cpp` + host — **no new `src/` seam**).
    The host holds a **separate writable save namespace** (D2 rules it OPFS-backed in the
    browser) beside the read-only project; reads resolve **save-first then
    project** (physfs mount order), so a written file shadows a project file and
    removing the save copy reveals the pristine project beneath — the witness
    proves, by transcript alone, that writes never mutate the project.
    `getSaveDirectory()` = `save:<t.identity>`. Writes are NUL-safe.
  - **The reload / invalidate primitive** (D5=A: minimal & explicit, whole-chunk
    re-eval) — a host-callable `pump_invalidate()` export (+ a Lua twin
    `__pump_invalidate()` for in-script driving) that drops **game** Lua modules
    from `package.loaded` while preserving `love`/`love.*` and the standard libs.
    `g_L` persists across `pump_boot`, so caches survive a reboot — this clears
    them. The **reload invariant** is witnessed: `require("mod").v==1` → host-edit
    the source via the write path (`return {v=2}`) → `pump_invalidate()` →
    `require("mod").v==2` — write + invalidate + re-eval compose into live-edit,
    and `love.load` does **not** re-run (edits change the future, not the past).
  - **The seam documented** — `wasi/platform/EMBEDDING.md` (referenced here): the
    full host-import surface a consumer fulfills (`love_fs` read+write, `love_win`,
    `love_gl`, `love_input`, `love_gamepad`, `love_system`, `love_audio`, the WASI
    shim), the pump ABI + reload entry points and how to drive them, and the
    supported-edit class. It documents the **seam**, not the downstream IDE.

  Built without resolving **D4** (hotswap vs whole-chunk) — and the D4=B
  refinement (#56) has since layered onto step 3 of the reload handshake exactly
  as predicted, without changing the write/invalidate seam: `pump_hotswap`
  (`wasi/pump/pump.cpp`, EMBEDDING.md §4) is the `main.lua`-direct path. The IDE
  (LoveIDE: editor, git-wasm save flow, agent live-edit UX) is a separate repo
  that consumes this contract — out of scope here. **With 6.7 landed, Step 6 is
  COMPLETE.** The former "step 8" is dropped; "step 7" (`love.thread` via Workers)
  remains a large, separate, design-doc-first, demand-driven step after 6.7.

## Decisions

Design forks and their rulings live in [`../DECISIONS.md`](../DECISIONS.md),
not here. This document says what the system is and why; that one says what was
chosen where more than one answer was available, and what the rejected answers
were.

D1 (filesystem seam), D3 (window and rendering-context creation), D5
(supported-edit class), D6 (console channel) and D7 (runtime archive mounting)
were re-put and re-ruled on 2026-08-16 after an audit found no evidence that
they had ever been ruled. D0 records what a closed decision means, and why that
needed writing down.

## Resolved by the reload invariant (recorded as decided, not open)

The Human set the reload contract:

> **`reload(edit)` at state S ≡ a fresh run of the new code that has reached S.**
> Live edits change the **future, not the past**; if you break your code and save
> mid-run, it breaks — exactly as a fresh run of broken code would.

Two questions fall out as *decided*:

- **Error containment: dropped.** A broken save breaks the game; LÖVE's error
  screen appears, same as always. No last-good rollback, no containment mode, no
  divergence — the *more* faithful choice.
- **Does `love.load` re-run on reload? No.** A fresh run reaching S ran `love.load`
  once, in the past; re-running it would violate the invariant. Only the
  per-frame path picks up edits. (Corollary: an edit to already-executed init has
  no well-defined "same state" — the trajectory would diverge — so it simply does
  not manifest until a real restart. Consistent with the rule.)
