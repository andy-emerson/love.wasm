# love-wasi embedding contract (build-order step 6.7)

This is the seam a **host** (an IDE, a live-edit runner, a game shell) fulfils to
run a real LÖVE 12 game as wasm32-wasi in the browser. It is the boundary of this
repo's responsibility: love-wasi ships and documents the contract; the downstream
consumer (LoveIDE: editor, git-wasm save flow, agent live-edit UX) is a separate
repo that *uses* it, out of scope here.

The artifact is a **wasm32-wasi reactor**. The host instantiates it, binds its
memory to each host module, runs the reactor ctors (`_initialize`), then drives
the resident coroutine one frame per `requestAnimationFrame` tick through the
pump ABI. The `wasi/host/*.mjs` files are a complete, self-contained reference
host (the same one both witness legs use, node:wasi and Chromium); a real host
swaps each canned store for its live model behind the *same* imports.

Two rules the whole contract rests on:

- **The game is pure LÖVE.** The shipped `.love` is a normal LÖVE 12 game — it
  runs identically on desktop LÖVE. None of the live-edit / reload / console
  machinery is a game-facing API; it is all host-side, driven out of band.
- **Loud, not faked.** Anything genuinely unsupported (real archive mounting,
  desktop-exact sync durability) throws or reports unsupported — it never returns
  a plausible lie. Declared deferrals are listed at the end.

## 1. The pump ABI (`wasi/pump/pump.cpp`)

The engine runs as a resident Lua coroutine; the host resumes it once per frame.
One in-slot and one out-slot over linear memory:

| Export | Meaning |
|---|---|
| `pump_in(cap) -> ptr` | host-writable buffer of ≥ `cap` bytes (write the payload here, then call boot/frame with its length) |
| `pump_boot(len) -> status` | in-slot = Lua source; (re)creates the resident coroutine and runs it to its first yield |
| `pump_frame(len) -> status` | in-slot = this frame's payload (one Lua string); resumes the coroutine once |
| `pump_out() -> ptr`, `pump_out_len() -> u32` | the yielded / returned / error value, valid until the next pump call |
| `pump_invalidate() -> int` | **live-edit reload primitive** (§4): drops game Lua modules from `package.loaded`; returns the count, or `PUMP_NOBOOT` before boot |

`status`: `>= 0` coroutine yielded (value = `pump_out_len()`); `-1` `PUMP_DONE`
(returned; out-slot = final value); `-2` `PUMP_ERROR` (Lua error; out-slot =
message + traceback — the `lua_State` **survives**, LÖVE semantics: an error ends
the game loop, not the engine); `-3` `PUMP_NOBOOT` (`pump_frame` before boot).

`g_L` (the VM) **persists across `pump_boot`**, so `package.loaded` survives a
reboot — that is why the invalidate primitive exists (§4).

The host boots the game by feeding LÖVE's `boot.lua` chunk as the boot source
(it returns LÖVE's main-loop function, which is natively pump-shaped — it yields
once per frame). See `wasi/boot/` for the boot wiring.

## 2. The host import surface

Each module is a WebAssembly import module the host provides at instantiate. All
are self-contained linear-memory contracts (pointers + lengths into the wasm
memory the host bound); none require COOP/COEP, SharedArrayBuffer, or Emscripten.
A build links only the modules its enabled `conf.lua` modules need (the windowless
embed/fs builds link `love_fs` only; the union frame build links all of them).

### `love_fs` — filesystem (read: 6.1/6.2; write: 6.7) — `wasi/host/fs-host.mjs`

The host holds **two namespaces**: a read-only **project** (the game source /
`.love` contents) and a separate, writable **save** namespace keyed by
`t.identity` (D2: OPFS in the browser, eager-flush durability). Reads resolve
**save-first, then project** (physfs mount order), so a written file shadows a
project file of the same name; removing the save copy reveals the project file
beneath. Writes **never** touch the project.

| Import | Contract |
|---|---|
| `fs_size(path, len) -> i32` | byte length, or `-1` if absent (directory → `0`) |
| `fs_read(path, len, buf, cap) -> i32` | bytes copied (≤ `cap`) into `buf`, or `-1`; consults **both** namespaces, save-first |
| `fs_stat(path, len, *type, *size, *mtime) -> i32` | `0` ok / `-1` absent; writes little-endian out-params. `type`: `0` file, `1` dir, `2` symlink, `3` other |
| `fs_write(path, len, buf, n) -> i32` | writes `n` bytes to the **save** namespace, returns `n` (or `-1`); replaces the whole file |
| `fs_remove(path, len) -> i32` | `0` removed / `-1` absent — save namespace only (the project is immutable) |
| `fs_mkdir(path, len) -> i32` | `0` — records a directory in the save namespace |

The wasm side (`wasi/platform/fs-backend.cpp`, `love::filesystem::wasi_fs`)
computes `getSaveDirectory()` as `save:<identity>` and routes
`write`/`append`/`File:open("w"/"a")`/`remove`/`createDirectory` through these
imports; `read`/`getInfo`/`exists`/`require` ride the read imports.

### `love_win` — window + GL context (6.3) — `wasi/host/win-host.mjs`

`love.window.setMode` drives the host to size the `<canvas>` and create the real
WebGL2 context (D3); `present()` swaps; `captureScreenshot` reads the presented
backbuffer back. The created context is the surface the static WebGL2 GL imports
(step 4) issue draw calls against.

### `love_gl` — the WebGL2 draw surface (step 4)

The `opengl` backend, reused, with its GL loader reseamed to **static WebGL2
imports** (`LOVE_GRAPHICS_GL_STATIC_IMPORTS`): ~100+ `gl*` entry points the host
fulfils from the `love_win`-created context. The host provides no draw logic —
just the WebGL2 calls.

### `love_input` — event + keyboard + mouse (6.4) — `wasi/host/input-host.mjs`

The first host→guest **push** seam. The host queues forwarded DOM events; the
guest's `event::wasm::Event::pump()` drains them into `love::event::Message`
objects (the translation `event/sdl/Event.cpp` does for SDL, incl. the DOM→LÖVE
button remap and physical-`code`→key mapping), which the unchanged Lua dispatch
fires as `love.keypressed`/`love.mousepressed`/… . `love.keyboard`/`love.mouse`
read the shared input snapshot the pump maintains.

### `love_gamepad` — joystick + gamepad (6.5) — `wasi/host/gamepad-host.mjs`

A **poll** seam over the browser Gamepad API (`gamepad_count`/`gamepad_read`,
mirroring `navigator.getGamepads()`). Once per frame the guest reads the slots
and **diffs** them against the previous poll to synthesize the
`joystick*`/`gamepad*` events SDL would push, reusing 6.4's push queue via a weak
poll hook.

### `love_system` — system capabilities (6.6a) — `wasi/host/system-host.mjs`

The genuine browser capabilities: processor count, clipboard get/set, `openURL`,
locale/preferred-locales. `getOS()` returns `"Web"` (guarded seam). Honest
defaults for the rest. (`love.timer` needs **no** import — it routes through
`clock_gettime(CLOCK_MONOTONIC)`/`gettimeofday`; `love::sleep` is a browser
no-op, since the main thread must not block.)

### `love_audio` — playback + capture (step 5) — `wasi/host/audio-host.mjs`

The WebAudio backend seam: sources stream PCM the host plays through an
`AudioContext`; the microphone seam (`mic_*`) drives capture via `getUserMedia` →
AudioWorklet. Not linked in the windowless platform builds.

### `wasi_snapshot_preview1` — the WASI shim — `wasi/host/wasi-shim.mjs`

A minimal preview1 shim: `fd_write` taps fd 1/2 (the console channel, D6 — `print`
→ fd 1, errors → fd 2, host taps both), clock/random/env, and `autostub`
ENOSYS-stubs any preview1 call a given build imports but the shim doesn't
implement (loudly absent, never silently wrong). **No preopens** — the browser
has no fd layer, so the filesystem is `love_fs`, not WASI files.

## 3. Driving a frame (reference)

```
p = pump_in(payload.length); memcpy(mem+p, payload); st = pump_boot(len)   // boot
while st >= 0:  read pump_out()/pump_out_len(); await rAF; st = pump_frame(put("t"))
```

See `wasi/platform/driver.mjs` for the exact reference loop (shared by every
platform witness) and `wasi/host/witness-harness.mjs` for the node:wasi and
Chromium instantiate/bind/drive scaffolding.

## 4. Live-edit reload (D5=A — minimal & explicit, whole-chunk re-eval)

**The reload invariant** (architect-set): `reload(edit)` at state S ≡ a fresh run
of the new code that has reached S. Edits change the **future, not the past**:
`love.load` does **not** re-run on reload (a fresh run reaching S already ran it
once); only the per-frame path picks up edits. A broken save breaks the game —
LÖVE's error screen appears, exactly as a fresh run of broken code would (no
rollback, no containment — the more faithful choice).

**The mechanism** (D5=A): whole-chunk re-eval at **module granularity**. To apply
an edit the host:

1. **writes** the new module source into the VFS (`fs_write` — it lands in the
   save namespace and shadows the project file of the same name); then
2. calls **`pump_invalidate()`**, which drops every **game** Lua module from
   `package.loaded` — preserving `love`, every `love.*` submodule, and the
   standard Lua libraries (only the game's own modules are cleared); then
3. the next `require("mod")` misses the cache, re-runs the love `loader`
   searcher, re-reads the (now-edited) source through `love_fs`, and
   re-evaluates the chunk — the new module is live.

The witness (`wasi/platform/witness-embed.lua`) proves the composition end to
end: `require("mod").v == 1` → `fs_write` a `return {v=2}` → (still cached at 1) →
`pump_invalidate()` → `require("mod").v == 2`, with `love`/`love.filesystem`
surviving. A Lua twin `__pump_invalidate()` is registered on the state so a
witness (or a Lua-level host driver) can drive the sequence in-script; the
`pump_invalidate()` **export** is what a real host calls.

**Supported-edit class (D5=A).** Guaranteed live: function-body edits to
callbacks and the functions they call, and file-scope constant literals, applied
by re-requiring the changed module. Everything else (edits to already-executed
init whose state lives in file-scope locals, structural changes that would leave
stale live references) → **restart** (a fresh `pump_boot`), the blessed fallback.
Finer-grained function-body hotswap that preserves live state (**D4**, still open)
can layer on later without foreclosing this: it would refine step 3, not change
the write/invalidate handshake.

## 5. Declared deferrals

- **True cross-reload durability.** The reference host's save namespace is
  in-memory (same-session read-after-write is what 6.7 proves). The browser host
  backs it with **OPFS, eager-flush eventual durability** (D2): async OPFS under
  the sync `fs_write`, flushed after each write + on `pagehide`/`visibilitychange`.
  In-session behavior is desktop-identical; the only residual is a force-kill
  within the last-write window — a declared cross-platform timing note. Desktop-
  exact **sync** durability needs the engine-in-Worker + OPFS sync-access-handle
  pivot, parked for a shipping variant that needs it.
- **Real archive / `.love`-zip mounting** (`mount*`) and **directory enumeration**
  (`getDirectoryItems`) remain unimplemented — loud `false`/throw, not faked.
  The host store is flat + keyed by relative name; a real host that needs mount
  ordering or listing extends the seam.
- **D4 hotswap** (function-body, state-preserving) is not built; D5=A's
  whole-chunk re-eval + restart fallback is the shipped mechanism.
- Per-file **read-only** reporting: `getInfo(...).readonly` reflects the read-only
  project posture; the save layer's writability is not yet surfaced per-file (the
  `fs_stat` ABI carries no readonly out-param). Not witness-critical.
