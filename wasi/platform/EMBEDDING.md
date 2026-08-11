# love.wasm embedding contract (build-order step 6.7)

This is the seam a **host** (an IDE, a live-edit runner, a game shell) fulfils to
run a real LÖVE 12 game as wasm32-wasi in the browser. It is the boundary of this
repo's responsibility: love.wasm ships and documents the contract; the downstream
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

### `boot()` — the recommended consumption shape (`wasi/shell/boot.mjs`)

A browser consumer should not wire this surface by hand: `boot({ wasm, bootSrc,
files, canvas, onLog, onStatus })` is the exported entry point that instantiates
the artifact with all eight import modules, binds memory on every host, runs
`_initialize`, boots the pump, and drives it on `requestAnimationFrame` with the
blur/visibility pause. Only what genuinely varies per consumer is a parameter:
`files` is the path → bytes map this section defines (produce it however you
like), `canvas` is a `(w, h) => HTMLCanvasElement` callback invoked when
`love.window.setMode` asks for a window, and `onLog`/`onStatus` say where the
console tap and the running/paused/error/quit state go. It returns a handle —
`stop()`, `invalidate()` (§4), `quit()`, the `files`/`saves` stores,
`running`/`paused` — and it **verifies the host fulfils the module's import
surface** via `WebAssembly.Module.imports()` before instantiating, so an
artifact whose imports have outgrown the host fails loudly with the missing
names instead of at first call. `wasi/shell/player.mjs` is the first caller: its
manifest-over-HTTP loader just produces the map and calls `boot()`. This fits
the #7 delivery shape — host inline in the page, `love.wasm` fetched by URL —
and everything below remains the contract for a host that fulfils the seams
itself.

Each module is a WebAssembly import module the host provides at instantiate. All
are self-contained linear-memory contracts (pointers + lengths into the wasm
memory the host bound); none require COOP/COEP, SharedArrayBuffer, or Emscripten.
A build links only the modules its enabled `conf.lua` modules need (the windowless
embed/fs builds link `love_fs` only; the union frame build links all of them).

### `love_fs` — filesystem (read: 6.1/6.2; write: 6.7) — `wasi/host/fs-host.mjs`

The host holds **two namespaces**: a read-only **project** (the game source /
`.love` contents) and a separate, writable **save** namespace keyed by
`t.identity` (OPFS-backed in the browser per D2 — `wasi/host/fs-opfs.mjs`,
used by `boot()`, witnessed by `wasi/shell/run-durability.sh` (#55); the node
hosts keep the in-memory map). Reads resolve
**save-first, then project** (physfs mount order), so a written file shadows a
project file of the same name; removing the save copy reveals the project file
beneath. Writes **never** touch the project.

| Import | Contract |
|---|---|
| `fs_size(path, len) -> i32` | byte length, or `-1` if absent (directory → `0`) |
| `fs_read(path, len, buf, cap) -> i32` | bytes copied (≤ `cap`) into `buf`, or `-1`; consults **both** namespaces, save-first |
| `fs_stat(path, len, *type, *size, *mtime, *readonly) -> i32` | `0` ok / `-1` absent; writes little-endian out-params. `type`: `0` file, `1` dir, `2` symlink, `3` other. `readonly`: `1` for the read-only project, `0` for the writable save namespace — only the host can tell, since it resolves the two |
| `fs_write(path, len, buf, n) -> i32` | writes `n` bytes to the **save** namespace, returns `n` (or `-1`); replaces the whole file |
| `fs_remove(path, len) -> i32` | `0` removed / `-1` refused — save namespace only (the project is immutable), and a **non-empty** directory is refused, as physfs does: `love.filesystem.remove` returns false rather than deleting a tree |
| `fs_mkdir(path, len) -> i32` | `0` — records a directory in the save namespace, creating intermediate directories as physfs does |
| `fs_list(path, len, buf, cap) -> i32` | total bytes needed for the NUL-separated **immediate child names** of `path`, writing up to `cap` of them into `buf`. Call with `cap = 0` to size, then again to fill — the same two-step `fs_read` uses. Consults **both** namespaces, so a save file and a project file in one directory are listed together, once |

**How the project gets in is the host's business, and the contract asks for
nothing but bytes.** These imports are the whole interface: a host answers them
from whatever it has. `wasi/host/fs-host.mjs` keeps a plain `path -> Uint8Array`
map and exposes it as `files`, so a consumer holding a project in memory —
an in-browser editor, a live-edit IDE, a test harness generating a fixture —
populates that map and is done. **There is no archive step**: the seam takes
files, never a `.love` zip, so a host that already has the bytes should not
zip them to hand them over.

`wasi/shell/player.mjs` fetches its project from a base URL with a
`manifest.json` beside it. That is one *way to produce* the map, convenient for
a project served over HTTP, and it is not the contract — notably, a `blob:` URL
has no relative children, so a host that generates its project in the page
cannot use the URL form and should fill the map directly.

The wasm side (`wasi/platform/fs-backend.cpp`, `love::filesystem::wasi_fs`)
computes `getSaveDirectory()` as `save:<identity>` and routes
`write`/`append`/`File:open("w"/"a")`/`remove`/`createDirectory` through these
imports; `read`/`getInfo`/`exists`/`require` ride the read imports.

### `love_win` — window + GL context (6.3) — `wasi/host/webgl-win-host.mjs`

`love.window.setMode` drives the host to size the `<canvas>` and create the real
WebGL2 context (D3); `present()` swaps; `captureScreenshot` reads the presented
backbuffer back. The created context is the surface the static WebGL2 GL imports
(step 4) issue draw calls against.

Three more imports carry the honest window answers (#58):

| Import | Contract |
|---|---|
| `window_set_display_sleep(enable)` | `0` asks the host to **request** a Screen Wake Lock (keep the display awake), `1` to release it. The grant is async and permission-gated — this only asks |
| `window_get_display_sleep() -> i32` | `1` while display sleep is allowed; `0` only while a wake lock is actually **held**. `isDisplaySleepEnabled` reads this, so it never claims an effect the browser has not performed |
| `window_get_system_theme() -> i32` | `0` unknown / `1` light / `2` dark, from `matchMedia('(prefers-color-scheme: dark)')`; a host without `matchMedia` answers `0` |

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
read the shared input snapshot the pump maintains — including the FOCUS /
MOUSEFOCUS records, which also back `love.window.hasFocus()`/`hasMouseFocus()`
(#58).

Custom image cursors (#58) ride two guest→host imports beside the existing
cursor side effects:

| Import | Contract |
|---|---|
| `input_new_cursor_image(rgba, w, h, hotx, hoty) -> i32` | builds an image cursor from `w*h*4` RGBA8 bytes + hotspot; returns a host cursor id (`> 0`), or `0` when the host cannot build one (the guest raises rather than faking). The browser host paints the pixels onto a canvas and keeps `url(<png data URL>) hotx hoty, auto` |
| `input_set_cursor_image(id)` | applies a previously built image cursor to the canvas; system-cursor shapes keep flowing through `input_set_cursor_shape` |

### `love_gamepad` — joystick + gamepad (6.5) — `wasi/host/gamepad-host.mjs`

A **poll** seam over the browser Gamepad API (`gamepad_count`/`gamepad_read`,
mirroring `navigator.getGamepads()`). Once per frame the guest reads the slots
and **diffs** them against the previous poll to synthesize the
`joystick*`/`gamepad*` events SDL would push, reusing 6.4's push queue via a weak
poll hook.

Rumble (#58) adds two guest→host imports:

| Import | Contract |
|---|---|
| `gamepad_is_vibration_supported(slot) -> i32` | `1` iff the pad in this slot has a `vibrationActuator` |
| `gamepad_set_vibration(slot, left, right, duration) -> i32` | drives the actuator with a `'dual-rumble'` effect — `left`/`right` are the strong/weak magnitudes in `[0,1]`, `duration` in seconds (`<= 0` = until stopped, clamped to the API's 5s longest effect; zero magnitudes stop). Returns `1` only when an actuator was actually driven, and the host records every request in its effects log |

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

**The reload invariant** (Human-set): `reload(edit)` at state S ≡ a fresh run
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
Finer-grained function-body hotswap that preserves live state (**D4**, closed as the chosen mechanism — not yet built)
can layer on later without foreclosing this: it would refine step 3, not change
the write/invalidate handshake.

## 5. Declared deferrals

- **Cross-reload durability is eventual, not sync (D2, #55).** The browser save
  store is OPFS-backed per D2's ruling: `wasi/host/fs-opfs.mjs` upgrades the
  in-memory reference host behind the same `fs_write` import — the map stays the
  synchronous truth, every mutation eager-flushes that path to OPFS, and
  `pagehide`/`visibilitychange` retry failures; `boot()` hydrates the store back
  before `pump_boot`. Witnessed by `wasi/shell/run-durability.sh`: write →
  `page.reload()` → the same bytes come back through `love.filesystem`, and the
  OPFS-disabled leg is required to come back empty. What remains declared: a
  force-kill inside the last-write window can lose that write (eventual
  durability — the model every shipped browser game uses), and the node hosts
  keep the in-memory store. Desktop-exact **sync** durability additionally needs
  the engine-in-Worker + OPFS sync-access-handle pivot, parked for a shipping
  variant that needs it.
- **Real archive / `.love`-zip mounting** (`mount*`) is unimplemented **by
  decision** — a loud `false`, not a fake. **D7 is closed (#48): not built**, and
  it is a declared divergence rather than a deferral. Note this does not affect
  *`.love`-as-source*: the seam takes files, so a host with an archive unzips it
  in its own JS (see §2). `mountFullPath` is implemented for a directory already
  in the store; see the last entry below.
  (**Directory enumeration is no longer deferred**: `getDirectoryItems` is real,
  over the `fs_list` import in the table above, witnessed by
  `wasi/platform/run-fs-list.sh` on node and Chromium.)
- **D4 hotswap** (function-body, state-preserving) is not built; D5=A's
  whole-chunk re-eval + restart fallback is the shipped mechanism.
- Directory **mounting** is limited to a directory already in the host store
  (`mountFullPath` gives it a second name); there is no host filesystem behind
  the seam to reach anything else, and a path that does not resolve inside the
  store is refused rather than faked. Archive mounting is #48, closed as not built.
