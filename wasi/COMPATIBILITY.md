# What works where

A LÖVE feature is not correct or broken in the abstract. It is correct or
broken **on the platform the game is deployed to**: a browser game runs in a
browser, a Windows game runs on Windows, and the two do not owe each other a
window position or a native library loader. This document says, per feature and
per target, whether the target has the feature at all — and, where it does,
whether this build delivers it.

That is the frame `readme.md`'s fidelity standard already sets: **browser-native
correctness first**, desktop as the reference rather than the pass/fail line.
This table is that standard written out one feature at a time.

## How to read it

| mark | meaning |
|---|---|
| **✓** | the target has this feature, and this build does it — witnessed |
| **✗** | the target has this feature, and this build does **not**. A gap, and every one is named below |
| **~** | the target has it and this build does it, but only under conditions no test can create (a browser API that requires a user gesture, or an async permission grant the test environment refuses). Stated, not witnessed |
| *(blank)* | the target does not have this feature. A **declared divergence**, never a hidden failure |

A blank cell is the load-bearing one. It does not mean "missing"; it means the
question does not apply here, the same way `love.window.setPosition` does not
apply to a full-screen mobile app. Nothing is ever made to pass by storing a
value the platform never applied — that is the line between a declared
divergence and a fake.

## The columns

- **Desktop** — LÖVE 12 on Windows, macOS and Linux. This column says only
  *whether the feature exists there*, and it is read out of upstream's source,
  which this repository carries byte-for-byte on `main`. It carries no claim
  about our code. Where the three desktop OSes differ, the row says so.
- **Web** — the artifact this repository builds: LÖVE 12 compiled to
  `wasm32-wasi`, on WebGL2, WebAudio, OPFS and the DOM. This is the only column
  that reports our own evidence, and every ✓ in it is backed by a witness in
  `wasi/**/run*.sh` or by the `testing/` corpus, which needs no slicing — it gates
  every suite on `if love.<module> ~= nil`, so it runs in one shot.

**Mobile is deliberately absent.** LÖVE's iOS and Android ports live in
`love-ios` and `love-android`, outside this tree, so a mobile column would be
guesswork rather than something read from source. It is worth adding by whoever
can ground it: it would make most of the blanks below visibly *not* a browser
peculiarity — a phone cannot reposition its window either.

---

## love.filesystem

| feature | Desktop | Web | |
|---|:--:|:--:|---|
| read a file from the project | ✓ | ✓ | |
| enumerate a directory | ✓ | ✓ | |
| `getInfo` — type, size, modification time | ✓ | ✓ | directories are implicit: one exists when a key lives beneath it |
| `getInfo().readonly` | ✓ | ✓ | the host reports which store answered, because it is the side that resolves the two |
| write / append, `File:open("w"/"a")` | ✓ | ✓ | a separate writable save namespace, OPFS-backed (D2) |
| `createDirectory` / `remove` | ✓ | ✓ | parents are created; a non-empty directory is refused |
| a saved file shadows the project file | ✓ | ✓ | physfs mount order, preserved |
| `t.identity` namespacing, `getSaveDirectory` | ✓ | ✓ | `save:<identity>` |
| `isFused` | ✓ | ✓ | `setSource` requires a game to actually be there, as desktop physfs does |
| `mountFullPath` a directory already in the store | ✓ | ✓ | rewrite sits in wrappers around the `love_fs` imports, so every operation sees mounts identically |
| mount an arbitrary directory of the machine | ✓ | | there is no host filesystem behind the seam — only the project and the save namespace. A target that does not resolve inside the store is refused, not faked |
| mount a `.love` / zip archive at runtime | ✓ | | **D7 closed (#48): deliberately not built.** PhysFS's zip archiver went with PhysFS, and neither rebuilding it in wasm nor unzipping host-side earns its cost against the demand — two corpus tests and no observed game. A `.love` as the *boot source* needs none of this: the seam takes a path→bytes map, so a host unzips in its own JS and fills the map |
| `getRealDirectory` | ✓ | | the store is virtual; there are no real directories to name |
| `getCommonPath` — userhome, userdesktop, appdocuments, userappdata | ✓ | | a page has no such paths |
| native-C `require` (the `extloader` searcher) | ✓ | | no `dlopen`, and no real on-disk path to hand one. The Lua `loader` is registered; `extloader` is not |

## love.graphics

| feature | Desktop | Web | |
|---|:--:|:--:|---|
| clear, draw, present | ✓ | ✓ | `present()` is real — the canvas is a real WebGL2 surface, which is what makes `captureScreenshot` real too |
| primitives, transforms, blend, scissor, stencil | ✓ | ✓ | |
| textures, Canvas (render targets), MRT, MSAA | ✓ | ✓ | |
| Mesh, SpriteBatch, Quad, ParticleSystem | ✓ | ✓ | |
| Text, Font, ImageFont | ✓ | ✓ | real FreeType + HarfBuzz, compiled to wasm |
| shaders (GLSL ES 3.00 / LÖVE's GLSL 3) | ✓ | ✓ | |
| instanced drawing, depth test | ✓ | ✓ | |
| `GraphicsBuffer` (vertex / index) | ✓ | ✓ | |
| pixel readback of every format | ✓ | ✓ | the destination view and its size are chosen from the format and type; WebGL2 rejects a mismatch outright rather than widening |
| `captureScreenshot` | ✓ | ✓ | |
| compute shaders / GLSL 4 | ✓ | | WebGL2 **is** OpenGL ES 3.0. Reported unsupported, and a compute shader is rejected with a catchable error, not a crash — witnessed as leg 4.17 |
| indirect draw | ✓ | | ditto |
| texel buffers, texture buffers, SSBO | ✓ | | ditto |
| client-side vertex arrays, buffer mapping | ✓ | | forbidden in WebGL2; vertex streaming selects `glBufferSubData` |
| LA8 textures | ✓ | | no texture swizzle in WebGL2; the font atlas falls back to RGBA8 |
| DXT / BC / ASTC compressed textures | ✓ | ✓ | **#51, fixed.** The GL extension list is now enumerated: the host answers `GL_NUM_EXTENSIONS` and `glGetStringi` from `gl.getSupportedExtensions()`, translated to the spellings glad asks for, and **activates** each one with `getExtension` — listing without activating would claim a capability the context had not enabled. `glCompressedTexImage2D`/`SubImage2D` (and the 3D pair) are implemented rather than warn-stubs, so a format reported supported can actually be uploaded |
| pixel-exact agreement with desktop's rasteriser | ✓ | | measured (#54): `arc`/`circle`/`ellipse` differ by 1–2 boundary pixels each, every one matching a neighbouring reference pixel exactly — a driver fill-rule tie-break; `setLineStyle` by 3/255 in one channel of an AA blend. We are at the floor: no engine change on either side converges a rasteriser we don't ship. Upstream's harness already tolerates this class of difference per-platform, and #54 is the patch offering that tolerance a `"Web"` arm |

## love.window

| feature | Desktop | Web | |
|---|:--:|:--:|---|
| open a window at the `conf.lua` size | ✓ | ✓ | `setMode` creates the real `<canvas>` and WebGL2 context |
| resize / `updateMode` | ✓ | ✓ | a repeat call resizes the drawing buffer in place and **keeps** the context; depth and stencil are requested unconditionally at creation, so a later request can always be honoured |
| window title | ✓ | ✓ | the page title |
| pixel dimensions, DPI scale, `toPixels`/`fromPixels` | ✓ | ✓ | |
| `isVisible`, `isOpen` | ✓ | ✓ | |
| fullscreen | ✓ | **~** | the Fullscreen API is real, but it requires a **user gesture**. A game calling it from a keypress can work; a test driving it cold never can |
| `hasFocus` / `hasMouseFocus` | ✓ | ✓ | the host's `blur`/`focus` and pointer enter/leave events land in the input snapshot the pump keeps, and the window backend reads it (#58); with no input backend linked the default-focused fallback answers |
| `getSystemTheme` | ✓ | ✓ | `matchMedia('(prefers-color-scheme: dark)')` over a `love_win` import (#58); a host without `matchMedia` reports `unknown` |
| display sleep (`setDisplaySleepEnabled`) | ✓ | **~** | the Screen Wake Lock is wired (#58) as request-and-report: the host requests/releases the lock, and `isDisplaySleepEnabled` reports only a lock actually **held** — the grant is async and permission-gated, and headless Chromium refuses it, so no test can see the held state |
| `setPosition` / `getPosition` | ✓ | | a page cannot move its window |
| `minimize`, `maximize`, `restore`, `isMinimized`, `isMaximized` | ✓ | | nothing to drive |
| `setIcon` / `getIcon` | ✓ | | a favicon belongs to the host document, not to the canvas the game owns. Storing the ImageData so `getIcon` round-trips would report an effect the browser never performed |
| multiple displays, `getFullscreenModes`, `getDesktopDimensions` | ✓ | | one canvas, one display |
| message boxes, file dialogs | ✓ | | no faithful primitive; the host document's business |
| `requestAttention` | ✓ | | |
| vsync control | ✓ | | `requestAnimationFrame` owns the cadence. The requested value round-trips through `getVSync`, but there is nothing to toggle |

## love.audio

| feature | Desktop | Web | |
|---|:--:|:--:|---|
| play, pause, stop, rewind — per source and for all | ✓ | ✓ | sources are tracked while playing, and retained while tracked, as the OpenAL backend does. `pause()` returns exactly the sources it paused |
| `getActiveSourceCount` | ✓ | ✓ | |
| volume, pitch, looping, seek, tell | ✓ | ✓ | |
| static, streaming and queueable sources | ✓ | ✓ | |
| `Source:getDuration` | ✓ | ✓ | arithmetic for a static source; `-1` stays the honest answer for stream and queue |
| listener position / orientation / velocity | ✓ | ✓ | stored and reported |
| distance model, doppler scale | ✓ | ✓ | default is `inverse clamped`, as desktop's is. Unappliable spatialization state is stored and reported — this backend's stated convention |
| microphone capture | ✓ | ✓ | `getUserMedia` → AudioWorklet; the host's real rate is reported rather than resampled in wasm |
| choosing the microphone's sample rate | ✓ | | a browser gives you the rate it gives you |
| EFX effects — `setEffect`, `getEffect`, `getActiveEffects` | ✓ | | no WebAudio equivalent inside LÖVE's OpenAL-shaped model |
| per-source filters — `Source:setFilter` | ✓ | | ditto |
| output-device selection | ✓ | | gated |

## love.sound / love.image / love.font / love.data / love.math / love.physics

These are pure computation. They are the same code, compiled.

| feature | Desktop | Web | |
|---|:--:|:--:|---|
| Wave / Vorbis / FLAC / MP3 decoding | ✓ | ✓ | the in-tree lullaby decoders, compiled |
| tracker music (ModPlug) | ✓ | ✓ | vendored, decode witnessed in wasm |
| PNG / JPEG / DDS / EXR decoding | ✓ | ✓ | stb_image, lodepng, ddsparse, tinyexr — unchanged |
| `love.font` — FreeType raster, HarfBuzz shaping | ✓ | ✓ | same libraries, vendored |
| `love.data` — encode, decode, hash, compress | ✓ | ✓ | |
| `love.data.pack` / `unpack` / `getPackedSize` | ✓ | ✓ | implemented over Lua 5.4's own `string.pack`; upstream's 5.3 backport is a LuaJIT-only path and traps on 5.4 |
| `love.math` | ✓ | ✓ | 20/20 in the corpus |
| `love.physics` — real Box2D | ✓ | ✓ | 26/26 in the corpus |

## Input — love.keyboard, love.mouse, love.touch, love.joystick, love.sensor

| feature | Desktop | Web | |
|---|:--:|:--:|---|
| key press / release / repeat, `isDown`, `isScancodeDown` | ✓ | ✓ | real DOM events into LÖVE's real event queue |
| text input (`love.textinput`) | ✓ | ✓ | the typed character rides through as the payload |
| live keyboard layout | ✓ | | the physical `code` is mapped to a US layout; a declared divergence from SDL's live-layout mapping |
| IME composition | ✓ | | |
| `isModifierActive` (caps/num lock latch) | ✓ | | a page sees modifier state per event, not a queryable lock latch |
| on-screen keyboard | | | `hasScreenKeyboard` is false on desktop LÖVE too; it is an iOS/Android entry point |
| mouse position, buttons, wheel | ✓ | ✓ | wheel deltas are normalized — a declared divergence |
| system cursors, `setVisible` | ✓ | ✓ | CSS cursors |
| custom image cursors (`newCursor`) | ✓ | ✓ | the RGBA8 pixels + hotspot cross the `love_input` seam and the browser host sets a PNG data-URL CSS cursor — `url(...) hotx hoty, auto` (#58) |
| `setPosition` (cursor warp) | ✓ | | a page cannot move the pointer; reported as a failure rather than faked |
| relative mode (pointer lock) | ✓ | **~** | the Pointer Lock API is real and requires a **user gesture**. The corpus *passes* it, but only because the reference host answers yes — the test proves the call is wired, not that a browser locked the pointer |
| `setGrabbed` (cursor confinement) | ✓ | | no browser API at all |
| touch — press, move, release, `getTouches`, pressure | ✓ | ✓ | the browser TouchEvent API, arriving as three more record types on the existing `love_input` seam. `dx`/`dy` are computed host-side, because a browser gives absolute positions and no per-touch delta |
| `t.trackpadtouch` | ✓ | | a page cannot ask the OS to deliver a trackpad as touch. `false` — the default — is exactly what a browser already does |
| gamepad connect/disconnect, buttons, axes | ✓ | ✓ | the Gamepad API is poll-based, so the backend diffs each frame's snapshot and **synthesizes** the events SDL would have delivered — both the raw-joystick and the mapped-gamepad family, as SDL sends both |
| gamepad vibration | ✓ | ✓ | `setVibration` drives the pad's `vibrationActuator` (`'dual-rumble'` playEffect) over the `love_gamepad` seam, and the host records every request so the witness can observe it; `isVibrationSupported` reports whether the actuator exists (#58) |
| custom gamepad mappings — `setGamepadMapping`, `getGamepadMappingString` | ✓ | | no SDL controller database in a browser; the W3C standard mapping is fixed and implicit. `loadGamepadMappings` checks the shape of what it is given and refuses garbage, so a mistyped filename is not silently swallowed |
| gamepad motion sensors | ✓ | | no gamepad sensor stream |
| `love.sensor` — accelerometer, gyroscope | | | desktop LÖVE reports no sensors either. The browser's `DeviceMotionEvent` is permission- and HTTPS-gated, and is not wired; the module is linked with warn-once stubs so `love.sensor` is a real table, as it is on desktop |

## love.system / love.timer / love.event

| feature | Desktop | Web | |
|---|:--:|:--:|---|
| `love.event` — pump, push, poll, quit | ✓ | ✓ | 4/4 in the corpus |
| `love.timer` — `step`, `getDelta`, `getFPS`, `getTime` | ✓ | ✓ | `clock_gettime(CLOCK_MONOTONIC)` through the WASI host |
| `love.timer.sleep` | ✓ | | blocking the main thread is forbidden here. `love::sleep` is an honest no-op; frame cadence is `requestAnimationFrame`, not a guest spin |
| processor count | ✓ | ✓ | `navigator.hardwareConcurrency` |
| clipboard | ✓ | ✓ | a host cell fronting the async Clipboard API |
| `openURL` | ✓ | ✓ | `window.open` |
| preferred locales | ✓ | ✓ | `navigator.languages` |
| `getOS` | ✓ | ✓ | returns `"Web"`. The corpus asserts membership of a closed desktop-only list, which has no Web entry — a test-side divergence, not a broken call |
| memory size | ✓ | | reported as 0; a page is not told |
| power / battery info | ✓ | | the Battery Status API is gated across engines; reported `unknown` |
| `vibrate` | | | a no-op on desktop LÖVE too — `System::vibrate` has an Android and an iOS arm and nothing else. `navigator.vibrate` exists on mobile browsers and is unbuilt |

## Not linked at all

| feature | Desktop | Web | |
|---|:--:|:--:|---|
| `love.thread` | ✓ | **✗** | build-order step 7, design-doc-first. The architecture is fixed rather than open: **message-passing Web Workers only**, because `SharedArrayBuffer` and cross-origin isolation are ruled out by the pillar that this engine runs on any static host. Not in Beta |
| `love.video` (Theora) | ✓ | | dropped. A future `<video>` seam is the right path, not libtheora in wasm |
| networking — `enet`, `luasocket`, `luahttps` | ✓ | | no faithful browser primitive for raw sockets. A web-native transport is a later exploration |

A game that touches an unlinked module still boots. `love.<name>` is left **nil**
— the same shape desktop has with `t.modules.<name> = false`, so a feature test
takes the absent path — and a metatable on `love` prints one notice **at the
point of use**, naming the feature. Not at `require` time: LÖVE enables all
twenty modules for every game, so a require-time notice fires on every boot
whether or not the game cares, and stays silent in the one case worth knowing
about.

## The Lua dialect

Not a feature row, but it lands in the same table for game authors.

| | Desktop | Web | |
|---|:--:|:--:|---|
| Lua version | 5.1 (LuaJIT 2.1, or PUC 5.1 with `LOVE_JIT=OFF`) | 5.4 | LuaJIT cannot target wasm. **D8**, closed deliberately |
| the `love.*` API surface | ✓ | ✓ | the engine carries the `LUA_VERSION_NUM >= 504` branches it needs; the modules behave identically |
| 5.1-era game *Lua* running untouched | ✓ | | `unpack`, `math.atan2`, and non-integer numbers where an integer is required. Each has a portable form that runs on **both**, so porting a game forward costs it nothing on desktop |

The compatibility question this project measures is whether a LÖVE **feature**
works, not how a game's Lua was wired up. A ported game is still a LÖVE game.
See **The Lua dialect** in `readme.md`, and D8 in `wasi/platform/DESIGN.md`.

---

## What this says about the corpus

The `testing/` corpus stands at **306 pass / 34 fail / 15 skip** across 21 suites
— measured by `wasi/corpus/run.sh`, which is where these counts now come from.
Read through this table, the 34 stop being one number:

| | count | |
|---|:--:|---|
| *(blank)* — not supposed to work here | **30** | declared divergences. A test asserting them here is asserting something about a desktop, and it should be marked expected-fail rather than fixed |
| **~** — real, but gated behind what no test can supply | **4** | `setFullscreen` / `getFullscreen` (a user gesture) and `setDisplaySleepEnabled` / `isDisplaySleepEnabled` (#58 — the Screen Wake Lock is wired, but the grant is async and headless Chromium refuses it, and the honest state reports only a lock actually held). A game can reach all four; a test driving them cold cannot |
| **✗** — the browser has it and we do not | **0** | the wake lock was the last one; #58 closed it and the other four ✗ cells this table had (`hasFocus`/`hasMouseFocus`, `getSystemTheme`, image cursors, gamepad rumble) |

The 30, by suite — and `wasi/corpus/expected.txt` is the same list, executable:

| suite | n | |
|---|:--:|---|
| audio | 6 | mic sample rate; `setEffect`, `getEffect`, `getActiveEffects`, `Source:setFilter`; output-device selection |
| window | 8 | `setPosition`, `getPosition`, `maximize`, `minimize`, `isMaximized`, `isMinimized`, `setIcon`, `getIcon` |
| graphics | 6 | `Video()`, `newVideo()` (`love.video` absent); `arc`, `circle`, `ellipse`, `setLineStyle` (rasteriser) |
| filesystem | 4 | `mountCommonPath`, `getRealDirectory`, and `mount` / `unmount` — archive mounting, **D7 closed as not-built** |
| timer | 2 | `sleep` and `getTime` are one fact: `love::sleep` is an honest no-op, so `getTime` is measuring a sleep that did not happen |
| mouse | 1 | `setGrabbed` |
| joystick | 1 | `setGamepadMapping` (24 asserts) |
| system | 1 | `getOS` returns `"Web"`; the test asserts a closed desktop-only list |
| sound | 1 | `SoundData:getSample(0.001)` — a **D8** consequence, not a sound defect: `luaL_checkinteger` truncates under 5.1 and raises under 5.4 |

Four of them — the rasterisation near-misses — are not a decision after all:
measured (#54), they are upstream test-harness tolerance gates that have not
met a Web target, and the fix is an upstream patch, not a ruling here.

The ✗ column is the honest to-do list, and it is now empty: #58 closed the wake
lock (to **~**, grant-gated) and the four ✗ cells the corpus never probed —
`hasFocus`/`hasMouseFocus`, `getSystemTheme`, custom image cursors, and gamepad
vibration — each behind a host import with a witness that saw the host observe
the request. Finding them is what writing the table out feature by feature
bought.

## Keeping it true

Prose rots silently, so the Web column is not only prose. Its failing half is
`wasi/corpus/expected.txt`, and `wasi/corpus/run.sh` — in `witness.yml`, on
every push — fails three ways: a test expected to pass that failed, a test on the
expected-fail list that starts **passing** (this table is stale, which is a good
problem and still a failure, because an unearned divergence is a lie), and a
test that failed while classified nowhere. All three are demonstrated able to
fail. So a divergence that quietly becomes supported, and a fix that quietly
regresses, both turn CI red instead of ageing in a document.

This document is therefore **tested** where the corpus reaches it — 306/34/15,
re-earned on every push — and **observed** elsewhere: rows the corpus does not
probe rest on the platform witnesses (`hasFocus`, `getSystemTheme`, image
cursors and rumble are asserted by `wasi/platform/run-win.sh`, `run-input.sh`
and `run-joystick.sh` since #58) or on reading the code, and the Desktop column
remains a reading of upstream's source rather than a run.
