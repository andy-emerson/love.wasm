# love-wasi platform seam — design decisions (build-order step 6)

Build-order step 6 reseams the roles SDL plays for desktop LÖVE — window + GL
context, input, filesystem, timer, system — onto browser primitives, under the
same guarded-seam discipline as the graphics (`opengl` → WebGL2) and audio
(OpenAL → WebAudio) seams. This note records the decisions the seam is built on,
and — because step 6 is where the roadmap starts leaning into agentic,
live-edited development — the decisions the downstream **live-edit / agent**
consumer forces, which are surfaced here **while still open** (AGENTS.md: never
hand the architect a result built on choices they never saw).

Where a passage reads as a plan, the code has not landed it yet — only 6.1 is
built (`wasi/platform/`, the `love_fs` read round-trip). The rest is the shape
we are planning against.

## The one principle: the game stays pure LÖVE; the host holds the powers

love-wasi balances two standards — **fidelity with LÖVE 12 first, wanted
features second** — and they need not conflict, because the feature surface is
**host-side, never a game-facing API**. The shipped `.love` is a normal LÖVE 12
game: run it on desktop LÖVE and it behaves identically, because none of the
live-edit / console / reload machinery is baked into the artifact or visible to
Lua. The IDE mutates the project *out of band* through host imports; the game
never references any of it.

The single place this tempts a fidelity violation is the console-control idea
(below, D6): if "control what's in the console" became a `love.log()` the game
*calls*, it would break on other engines. It stays faithful instead — `print`
is `print`; control is host-side.

## Sub-step ledger (proposed — the architect owns the ordering)

Boot order puts filesystem first: LÖVE reads `conf.lua`/`main.lua` before it
opens a window. Step 3's boot witness proves LÖVE's `main()` dies *at* the
`love.filesystem` seam; step 6's job is to carry it *past* that line.

- **6.1 — `love_fs` VFS seam, read round-trip.** **Done** (this note's companion
  code). Isolates the host↔wasm file-bytes plumbing — a binary asset with
  embedded NULs recovered byte-exact through the seam under node:wasi + Chromium
  — before the real module rides on it. No LÖVE core linked; the analogue of
  graphics' 4.1a raw-GL leg.
- **6.2 — real `love.filesystem` on the seam.** Boot proceeds *past* the step-3
  stop-line into a real `conf.lua`/`main.lua`; `love.filesystem.read`/`load`/
  `getInfo`/`getDirectoryItems` work over the seam. Needs **D1**.
- **6.3 — `love.window`.** `setMode` creates the real `<canvas>` + WebGL2 context
  (folding in the step-4 `LOVE_GRAPHICS_GL_STATIC_IMPORTS` seam), replacing the
  fake `setMode` that `graphics-ext.cpp` plays for the step-4 witness. Unblocks
  `captureScreenshot`/`present()` (the one step-4 item that genuinely needs the
  window). Needs **D3**.
- **6.4 — `love.event` + input.** DOM keyboard/mouse/pointer events forwarded
  into LÖVE's real event queue; `love.keyboard`/`love.mouse` state.
- **6.5 — `love.timer` + `love.system` + conf.lua-driven canvas.** The first full
  `main.lua` frame: `love.conf` honored → canvas sized/titled → `love.load` →
  `love.update`/`love.draw` on the pump.
- **Reserved for the live-edit consumer (post-step-6, not step-6 scope):** the
  filesystem **write path + invalidate hook** (D2), and the host-callable
  **reload/eval primitive** (D4/D5). Step 6 must not *foreclose* these; it must
  not *build* them.

## Open decisions

Each is stated with options, trade-offs, and a recommendation. 6.1 depends on
none of them (the raw seam is shared by every option), so building it did not
front-run any choice below.

### D1 — Filesystem seam: replace the module, or keep PhysFS and reseam its IO

The real backend is PhysFS-based (`src/modules/filesystem/physfs/`). Two ways to
back it with the host:

- **Option A — replace the module.** Write a `love::filesystem::Filesystem`
  backend implementing the abstract interface (`filesystem/Filesystem.h`) whose
  `read`/`write`/`getInfo`/`mount`/`setSource`/`setIdentity`/`getDirectoryItems`
  call `love_fs` host imports, plus a matching `File`. Replace the boot stub's
  `luaopen_love_filesystem`.
  - **Pros:** no `src/libraries/physfs` tree in the build (readme already lists
    PhysFS as *replaced at the seams, not compiled*); the host controls every
    path, so the live-edit **invalidate** and the save dir are just host calls;
    smallest wasm; the `.love` and save namespaces are host concepts, not OS
    ones.
  - **Cons:** reimplements the whole `Filesystem.h` surface (a real backend, as
    `webaudio` was); risk of subtle divergence from PhysFS semantics (mount
    ordering, path canonicalization, symlink policy, `.love` zip mounting) that
    the `testing/` corpus must catch.
- **Option B — keep PhysFS, reseam its IO.** Compile `src/libraries/physfs` and
  back it with a `PHYSFS_Io` (or custom archiver) whose callbacks pull bytes
  from the `love_fs` host; provide a writable path for the save dir.
  - **Pros:** PhysFS's real mount/path/zip logic stays verbatim — least semantic
    divergence on the read side.
  - **Cons:** drags the whole PhysFS tree (currently excluded) into the build;
    PhysFS still wants a real writable FS + directory scans via OS calls that
    don't exist on wasm/browser (the save dir needs a shim either way); the
    live-edit invalidate must poke *through* PhysFS's own caching; more
    indirection for no browser-visible benefit.
- **Recommendation: Option A (replace).** It is the readme's committed direction,
  gives the host the clean control the live-edit write/invalidate path needs, and
  avoids dragging PhysFS's OS-dependent write/scan machinery onto wasm. The cost
  (reimplementing the interface) is bounded and directly checkable against the
  `testing/` filesystem suite. **This is the load-bearing step-6 decision and
  gates 6.2 — flagging it for the architect before building 6.2.**

### D2 — Save directory (writable) backing

Where `love.filesystem.write` / save data lives.

- **Option A — host-backed writable namespace** (`love_fs` write imports) stored
  in IDE / browser storage (IndexedDB, or memory for the preview).
  - **Pros:** consistent with the read seam; `t.identity` is a host prefix;
    persists across reloads if the host uses IndexedDB.
  - **Cons:** IndexedDB is async but `love.filesystem.write` is sync — needs a
    memory cache + async flush **sync-façade**, the same async-across-frames
    pattern the mic seam already uses.
- **Option B — a WASI preopened writable dir.** Rejected for the same reason the
  read path isn't WASI: the browser has no fd layer.
- **Recommendation: Option A**, with a memory cache + async flush façade.
  Deferred past 6.2's read path; the write path is its own sub-step.

### D3 — Window / GL-context creation

- **Option A — `love.window.setMode` drives the host** to size the `<canvas>`
  and create the WebGL2 context, then hands that context to the step-4 static GL
  imports.
  - **Pros:** faithful (LÖVE creates its own context, as on desktop); retires the
    `graphics-ext.cpp` fake `setMode`; unblocks `present()`/`captureScreenshot`.
  - **Cons:** the witness harness currently creates the context itself; this
    inverts that — the wasm now asks the host, so the graphics legs must move to
    the real window seam.
- **Option B — keep context creation in the harness**, `love.window` a thin stub
  reporting size. Lower effort, but leaves a permanent fake in the graphics path
  and never witnesses the real create.
- **Recommendation: Option A** at 6.3 — the point of step 6 is to *build* the
  seam graphics faked.

### D4 — Reload granularity (live-edit): whole-chunk re-eval vs. function-body hotswap

The mechanism that must satisfy the reload invariant (below). A file-scope
`local` is both how a *tuning constant* (`GRAVITY`) and *evolved state* (`score`)
are written, and Lua can't tell them apart syntactically.

- **Option A — whole-chunk re-eval.** Re-run the edited chunk; reassign its
  functions/globals.
  - **Pros:** dead simple, deterministic.
  - **Cons:** resets file-scope locals → violates the invariant for state held
    there; a `local x` assigned in `love.load` becomes nil (load isn't re-run) →
    crash. Safe only if game state lives in tables/globals the chunk top level
    doesn't overwrite.
- **Option B — function-body hotswap** (rxi's `lume.hotswap`): load the new chunk
  sandboxed, copy new function bodies into the old function objects, preserving
  upvalues/state.
  - **Pros:** preserves live state; satisfies the invariant for the tuning /
    update / draw case ("notebook magic").
  - **Cons:** leaky at the edges (new/removed upvalues, changed function identity
    held by live references, added/removed functions); needs the debug library.
- **Option C — convention + re-eval.** Require state to live in a designated
  table populated in `love.load` (not re-run); re-eval reassigns functions +
  top-level constants but never that table.
  - **Pros:** simpler than full hotswap; predictable; teachable.
  - **Cons:** imposes a game convention; non-conformant games fall back to
    restart.
- **Recommendation: Option B (hotswap) as the target**, with **restart as the
  honest fallback** for edits it can't apply cleanly (the architect has blessed
  restart). The supported-edit class (D5) defines exactly what hotswap
  guarantees; everything else restarts. Not needed until the reload sub-step
  (post-step-6).

### D5 — Supported-edit class (live-edit): what is guaranteed live

- **Option A — minimal & explicit:** function-body edits to callbacks and the
  functions they call, plus file-scope constant literals. Everything else →
  restart.
  - **Pros:** small, predictable, documentable; the invariant holds by
    construction; matches "fine-tuning variables" as the intended use.
  - **Cons:** the IDE must classify an edit's tier (and offer restart for the
    rest).
- **Option B — attempt-any, restart-on-failure.** Try every edit live; restart
  only when hotswap throws.
  - **Pros:** fewer explicit restarts.
  - **Cons:** silently keeps stale state on edits that *appear* to apply but
    shouldn't — the failure mode the invariant exists to forbid.
- **Recommendation: Option A** — the invariant wants a *classifier*, not
  best-effort. Restart is the correct answer for anything outside the class.

### D6 — Console / diagnostic channel shape

The agent needs sight on a live game's output, and (the architect's ask) some
control over what's included — kept faithful.

- **Option A — pure stdio.** `print` → fd 1, errors → fd 2, host taps both. No
  new API.
  - **Pros:** perfectly faithful; already how WASI works; zero divergence.
  - **Cons:** unstructured; no verbosity control beyond host-side string
    filtering; callbacks (`keypressed`, …) invisible unless the game prints them.
- **Option B — stdio + host-side structured tap.** Keep `print` faithful; the
  host tags/timestamps/filters lines and optionally taps the pump (it already
  drives `update`/`draw` and sees `love.errorhandler`), so the agent gets a
  richer, filterable signal — the "control what's included," done host-side.
  - **Pros:** faithful game side; the control the architect wants; callback/error
    visibility for the agent.
  - **Cons:** the callback tap needs a hook in the pump; more host code.
- **Option C — a game-facing `love.log()` API.** **Rejected:** a divergence that
  breaks on other engines unless it degrades to `print`.
- **Recommendation: Option B** — `print` stays `print`; structure, verbosity, and
  callback/error taps live host-side. The stdio half is present already (the
  witnesses read fd 1); the structured taps are a later sub-step.

## Resolved by the reload invariant (recorded as decided, not open)

The architect set the reload contract:

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
