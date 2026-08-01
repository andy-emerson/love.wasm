# Living status

Open work, and where the next session starts. This file is **living status**,
not a durable document (`AGENTS.md`, "Records"): it changes every session, and
nothing in it is a claim about what is built. What is built is `readme.md`; why
it is built that way is `wasi/platform/DESIGN.md` and `EMBEDDING.md`; how we
work is `AGENTS.md` and `CONTRIBUTING.md`.

## Where we are

A real game runs, and that is merged to `wasi`. The engine, compiled to
`wasm32-wasi`, takes an actual LÖVE project from `conf.lua` through canvas,
`love.load`, `love.update`/`love.draw` and present, with graphics, filesystem,
sound, audio and physics working together in one artifact.

There is also an **interactive shell** (`wasi/shell/`): a page that loads a
project from disk, pumps it on `requestAnimationFrame`, forwards real DOM
keyboard and mouse events into `love.event`, and applies a module edit to the
running game without a reload. Beta step 1 is done, witnessed by
`wasi/shell/run.sh` and CI-enforced.

A third-party game runs too: `challacade/legend-of-lua`, at 1920x1080, playable,
and **re-runnable** — `wasi/games/run.sh` fetches the pin, applies our port
patch, plays it and asserts. Its Lua needs a 5.1 → 5.4 port; every LÖVE feature
it uses works. See step 2, and **The Lua dialect** in `readme.md`.

The `testing/` corpus now runs — **303 pass / 37 fail / 15 skip** across 21
suites, up from 236/92 when it first ran. All three infrastructure blockers are
fixed and **every failure has now been examined**: what remains is 37 declared
divergences, plus one open design call on rasterisation tolerance. See step 3.

`love.thread` is the one major module still stubbed (build-order step 7).

## Beta

**Beta = real games playable interactively from a standalone dev artifact, with
the sliced `testing/` corpus green modulo declared divergences.** Packaging
(#7, build-order step 8) is post-Beta: love.wasm must be demonstrably operable
on its own, which is not the same as building every downstream consumer.

Five steps get there, and each names the evidence that will close it.

### 1. Interactive standalone shell — DONE

`wasi/shell/` is a game player: `serve.sh` serves the page and, given a
directory, mounts a project at `/__project/`; `player.mjs` imports the host
fulfillers as modules, loads the project over a `manifest.json` contract, and
pumps the union artifact on `requestAnimationFrame`, pausing when the tab is
hidden or unfocused. `input-host-browser.mjs` is the live counterpart to the
baked `input-host.mjs`, which stays as it is so both witness legs can share one
host. Live-edit is module granularity over the existing `pump_invalidate()`;
`main.lua` and `conf.lua` are reported restart-only, because making them live is
#47 (D4) and outside Beta.

Divergences declared in the host's own header: physical-`code` keys mapped to a
US layout, no IME, normalized wheel deltas, and pointer-lock and cursor-warp
reported as failures rather than faked.

**Evidence:** `wasi/shell/run.sh` in real Chromium, in `witness.yml`. A project
from disk runs (its own `conf.lua` sizes the canvas, and an asset is read from a
subdirectory); real DOM key events move the game, it stops on keyup, and it moves
back on the opposite key; a module edited on disk reaches the running instance,
and a `main.lua` edit is reported restart-only rather than silently ignored.

### 2. Real third-party games — ONE GAME DONE, RE-RUNNABLE

Run actual open-source LÖVE games rather than a fixture. **Do not bundle a game
in the repository.**

**Games are reachable after all.** `add_repo` refuses cross-owner adds and
`github.com` returns 403 to unauthenticated browsing, but **`git clone` of a
public repository works through the session proxy** — verified on two repos. So
any public GitHub LÖVE game can be fetched into a scratch directory and run.
itch.io does not resolve, so itch-only games need the Human to supply them.

**The chosen game: [challacade/legend-of-lua][lol]**, pinned at
`351f2456` (2026-07-01), 12 MB. Why it is the right first candidate:

- `conf.lua` declares `t.version = "11.5"`, and the code uses **no API removed in
  12** — checked against every removal and rename in `changes.txt`.
- Every module it touches is inside the nineteen the union artifact links:
  `audio`, `data`, `event`, `filesystem`, `graphics`, `image`, `keyboard`,
  `math`, `mouse`, `physics`, `system`, `timer`, `window`.
- Assets are 167 loose `.png`/`.ogg`/`.wav`/`.ttf` files, no archives — so D7
  (#48) archive mounting is not in the way.
- It has **already been ported to love.js**, and its `conf.lua` carries the scars:
  an explicit canvas size because "web builds need an explicit canvas size since
  there is no desktop to query", and `resizable = false` because resizing
  "breaks love.js (canvas collapses to ~1x1)". A game pre-shaped around web
  constraints is a fairer first test, and gives a reference for whether we hit
  the same edges love.js did.

Rejected candidate: `besnoi/arkanoid` — clean on the 12 API scan and inside the
envelope, but it ships **no `conf.lua`** and its assets are a **split RAR** with
no extractor available here.

**It runs, and the run is repeatable.** Legend of Lua boots from its own
`conf.lua`, opens a 1920x1080 canvas, and plays: tilemap, trees, water, shadows,
sprites, the equip UI and text all draw, keys move the game, GL reports no error,
and there are no preview notices at all. The union artifact links **nineteen**
modules — everything but `video` and `thread`.

**`wasi/games/run.sh`** is the reproducer, and it is what makes this a claim
rather than an anecdote: it clones the pinned commit into a scratch directory,
applies `wasi/games/legend-of-lua.patch`, plays it in real Chromium, asserts, and
deletes the clone. The game is not bundled and must not be; what this repository
owns is the patch — our port — at 59 lines.

**Deliberately not in CI.** Every other witness depends only on this repository
and its pinned toolchain; this one depends on a third party's repository staying
reachable and a commit staying alive. Wiring that into the per-push gate would
turn somebody else's force-push into our red CI. `readme.md` states the exception
rather than letting "CI re-runs all of them" quietly become false.

**The port was bigger than first reported.** Three *names* moved between 5.1 and
5.4, but across **41 call sites**, 29 of them inside the four libraries the game
vendors (hump, windfield, sti, mlib) — so the patch restores the names once in a
three-line prelude instead of forking four third-party libraries. Only the 8
computed font sizes are edited where they are written, because a wrong *value*
has no prelude fix. The earlier "three one-line edits" undercounted it.

**The witness is demonstrated able to fail.** Run against the same game with the
patch NOT applied, it fails with "the game crashed — the canvas is LÖVE's error
screen". That assertion is the load-bearing one: LÖVE's error screen renders a
traceback, so it has 229 distinct colours and would sail past a "something is
drawn" check. Recognising the screen by its colour is what separates *ran* from
*crashed*.

Three findings, in the order they were hit:

**1. Module defaults — fixed, then fixed properly (was step 2a).** `boot.lua:204` defaults every one
of the twenty modules to `true`, then loads them with a bare
`require("love." .. v)` that hard-errors on a missing module. So `t.modules.*` has
never been required of any game, on 11 or 12 — omitting it is idiomatic, and on
desktop the default is always satisfiable because desktop links everything. It
becomes unsatisfiable only on a build shipping a subset, which is ours.

**`joystick` and `sensor` are now linked for real**, not stubbed. Both had real,
CI-enforced backends already (`witness.yml` covers `joystickadded/removed`,
`joystickpressed/released/axis`, `isGamepad`, `isGamepadDown`, `getGamepadAxis`,
`getName`), so the first version of this fix stubbed over a working feature: a
game's `if love.joystick then` took the absent path and silently lost gamepad
support. Linking them is a `config-game` + `build-game.sh` change; the stub
retires itself, because linked-ness is read from `package.preload` rather than
listed.

`video` and `thread` remain unlinked and are supplied by the boot wrapper. `love.<name>` stays **nil**, which is the shape desktop has with
`t.modules.<name> = false`, so a feature test takes the absent path; the report
rides on a metatable on `love` itself, so the same read both reports and
correctly evaluates false.

**The notice fires on USE, not on enable** — the `preview-warn.cpp` contract
(#27) every other preview limitation here follows. The first version reported at
`require` time, which is exactly backwards: LÖVE enables all twenty modules for
every game, so it printed five lines on every boot whether or not the game cared,
and printed *nothing* in the one case worth knowing about. The question this
build has to answer is "did a game need a feature we do not have?", so the notice
belongs where that question is answered.

Two things it deliberately does not do. Making every game declare `t.modules.*`
would push our packaging gap onto game authors for no benefit to them. Changing
`boot.lua`'s defaults is a fork-private edit to shared engine source (lane 3,
forbidden) and would make `love.conf` report something desktop does not.

**2. `glGetIntegerv` unbound the shader program — fixed.** Desktop GL names
objects with integers; WebGL hands out opaque objects, and both GL hosts
converted the answer with `v | 0`, which is `0` for an object — and `0` is also
the GL name for *nothing bound*. `Shader::loadVolatile` saves
`GL_CURRENT_PROGRAM`, binds its new program to inspect uniforms, and restores
what it saved. So creating **any** Shader, even one never used, left no program
bound, and every draw after it failed with `GL_INVALID_OPERATION`. The clear
colour still reached the screen, so the symptom was a game that looked like it
was running while drawing nothing at all — the hardest shape of bug to read from
the outside. Both hosts now keep a reverse object → name map, which fixes every
`*_BINDING` query rather than just this one.

**Witnessed, and the witness is shown able to fail.** New graphics leg **4.5b**
(`wasi/graphics/witness-shader-unused.lua`): draw, create a shader and never
attach it, draw again — both draws must land. With the host fix reverted it
reads back the clear colour and FAILS; with the fix it PASSES. The existing 4.5
shader leg passes **either way**, which is exactly why it never caught this: 4.5
draws *with* its shader, so `setShader()` re-binds a program immediately after
`newShader()` and repairs the damage before the draw. The uncovered case was
every real game's `love.load` — create shaders for later, keep drawing with the
default one.

**3. The Lua dialect — settled, and it is a porting cost, not a defect.** The
game's Lua is written for 5.1; three idioms do not survive 5.4 (`unpack`,
`math.atan2`, and a non-integer font size). Each has a portable form that runs on
both, so the port is cheap and costs the game nothing on desktop. No LÖVE feature
it uses is missing. Documented in `readme.md`; the choice itself is D8.

**Both witness projects now set NO `t.modules`**, exactly like a real game, so
the boot-wrapper path is CI-enforced rather than sidestepped. That change caught
a real regression on the way in: linking `joystick` adds a `love_gamepad` import,
which `run-browser-game.mjs` did not provide, and the union witness failed at
instantiate until it was wired.

**`love.touch` is now built.** A browser has real touch events, so `touch` was
unbuilt rather than impossible — the third reason in a list of three, and the
only one that was just a gap. `wasi/platform/touch-backend.{h,cpp}` is the
browser-TouchEvent sibling of `touch/sdl/Touch.cpp`, keeping upstream's division:
the live-touch list lives in the module and the event pump updates it as it
converts, which is exactly where `event/sdl/Event.cpp` does it.

It needs **no host import of its own**. Touch arrives as three more record types
on the existing `love_input` seam (13/14/15), next to the mouse and keyboard
ones, the same way finger events sit next to them in an SDL queue — so the host
count is unchanged and only the guarded-seam count moves, ten to eleven.
`love.thread` and `love.video` are what remain absent, for their own reasons.

**Measured, not assumed:** 1920x1080 renders correctly. A minimal project at that
size draws rectangles and text exactly as the 96x64 fixtures do, and the game
fills the canvas. The earlier worry that nothing above 96x64 had ever been tried
is closed.

**Evidence: both fixes are tested, and both witnesses are demonstrated able to
fail.** love.touch is witnessed twice, both legs green: the 6.4 input witness
drives two fingers through a baked record queue (node AND Chromium) and asserts
the message args, the live-touch LIST, and that a released finger is gone; the
shell witness dispatches REAL DOM TouchEvents over CDP — held across frames, not
tapped — and asserts the press lands on the canvas centre, the move carries a
host-computed delta, and getTouches() goes 1 then 0.

The GL fix is 4.5b — reverting the host change makes it read back the
clear colour and FAIL, while the pre-existing 4.5 passes either way. The module
handling is the union game witness, which now asserts seven things about a
project that sets no `t.modules`: linked modules are real tables, an unlinked one
reads `nil`, nothing is reported before the read, the notice fires on the read
exactly once, linked modules are never reported, and a second unlinked module
reports separately. Two adverse cases, both run:

| Regression | What the witness says |
|---|---|
| joystick/sensor stubbed instead of linked | `linked modules are real tables: false`, `linked modules are never reported: false` |
| the notice moved back to `require` time | `no notice before the read: false`, `notice fires on the read: false` |

[lol]: https://github.com/challacade/legend-of-lua

### 3. Corpus parity — CENSUSED, work sized

**It does not need slicing.** `testing/main.lua` already gates every suite on
`if love.<module> ~= nil then require(...)`, so `video` and `thread` skip
themselves — which works precisely *because* the boot wrapper leaves an absent
module `nil` rather than a truthy stub. The recorded plan to "run it by module
slice" was wrong; the whole corpus runs in one shot.

**The census (this session), 21 suites in one run — first run, then after the
three fixes below:**

| | pass | fail | skip |
|---|---|---|---|
| first run | 236 | 92 | 15 |
| **now** | **303** | **37** | **15** |

Per suite, as it stands now (▲ marks what the three fixes moved):

| module | pass | fail | | module | pass | fail |
|---|---|---|---|---|---|---|
| audio ▲ | 25 | 6 | | mouse | 15 | 3 |
| data ▲ | 12 | 0 | | physics | 26 | 0 |
| event | 4 | 0 | | sensor | 1 | 0 |
| filesystem ▲ | 29 | 4 | | sound | 3 | 1 |
| font | 7 | 0 | | system | 7 | 1 |
| graphics ▲ | 98 | 7 | | timer | 4 | 2 |
| image | 5 | 0 | | touch | 3 | 0 |
| joystick ▲ | 5 | 1 | | window | 23 | 12 |
| keyboard | 10 | 0 | | love ▲ | 6 | 0 |
| math | 20 | 0 | | thread/video | — | skipped |

**Three infrastructure blockers account for most of it. The residual is small.**

**A. `setMode` recreated the GL context every call — FIXED this session.**
`window_setmode` built a new canvas and a new WebGL2 context on every call, so
the *second* one orphaned every shader, buffer and texture LÖVE had made in the
first. The corpus died on line 39 of `love.load` — `love.window.updateMode` —
with "Cannot link shader program object". This was never corpus-specific: a
resolution change or a fullscreen toggle in any real game hit it. A repeat call
now resizes the drawing buffer in place and keeps the context, and depth+stencil
are requested unconditionally at creation so a later request can always be
honoured. Witnesses re-run: win, frame, game, shell — all pass.

**B. `love.data.pack` trapped the module — FIXED this session.** Minimal repro:
`love.data.pack('string', '>I4', 9999)` traps ("null function or function
signature mismatch"; sometimes "memory access out of bounds"). Native
`string.pack`/`unpack` are fine and `love.data.getPackedSize` is fine, so it is
not the format machinery.

The cause is `src/libraries/lua53/lstrlib.c`, the Kepler 5.3 backport LÖVE
vendors so LuaJIT gets `string.pack`. Its buffer layer branches on
`LUA_VERSION_NUM == 501`: on 5.1 it uses its own `ptr`/`nelems`/`capacity`/`L2`
fields; on anything else `luaL_buffinit_53` initialises the **native**
`luaL_Buffer` — but `luaL_addsize_53` and `lua53_pushresult` still read the
shim's own fields, which nobody set. So `lua53_pushresult` calls
`lua_pushlstring(B->L2, B->ptr, B->nelems)` on garbage. Someone added a
`>= 504` arm to one macro, which made it *compile* under 5.4 without making it
*work*; upstream never runs this path because upstream is 5.1.

The fix needed no `src/` change. Lua 5.4 has `string.pack`/`unpack`/`packsize`
natively and the backport's whole interface is five symbols, so
`wasi/platform/lua53-strlib.c` implements those over the native functions and
all fourteen build scripts link it instead of `lstrlib.c`. It includes upstream's
header, so a drift in the struct layout or a prototype is a compile error rather
than a trap. The functions come from the registry's loaded-module table, not the
`string` global, so a game reassigning `string.pack` cannot change what
`love.data.pack` does.

`love.data` is now **12 pass / 0 fail**, and the total is **290 pass / 50 fail**.
`love.data.pack` is a real LÖVE 12 API, so this was never corpus-only.

One bug of my own on the way in, worth recording because the shape recurs:
`posidx` was read *after* pushing the function and its arguments. It is an
absolute stack index, so with no position argument supplied it pointed at the
pushed function — "bad argument #3 to 'string.unpack' (number expected, got
function)". Read the caller's optional arguments before pushing anything.

**C. `mountFullPath` — FIXED this session.** It returned false, so `compareImg`
could not read its reference PNGs and 44 of graphics' 47 failures were one
missing capability rather than 44 defects. Confirmed independent of #48: this is
a **directory** mount, and #48 is about who unzips an *archive*.

Two parts, and the second was a defect in its own right:

- The store behind the seam has no host filesystem — only the loaded project and
  the writable save namespace. So a mount here cannot open an unrelated
  directory on a machine; what it can do, and all LÖVE actually asks for, is
  make a directory ALREADY in the store visible under a second name. A target
  that does not resolve inside the store is refused, not faked. The rewrite sits
  in wrappers around the `love_fs` imports, so read/stat/size/write/remove/
  mkdir/list all see mounts identically and there is no cost while no mount
  exists.
- **Project directories did not exist to `getInfo`.** The store is a flat
  path→bytes map, so only an `fs_mkdir`'d directory in the save namespace ever
  stat'ed. `love.filesystem.getInfo("<a directory of the game's own source>")`
  returned nil while `getDirectoryItems` happily listed its children — the two
  halves of one store disagreeing. A directory is now implicit: it exists when
  some key lives beneath it. That is what let the mount verify its target, and
  it fixes `getInfo` on directories for every game.

**Result: 236 pass / 92 fail → 278 pass / 50 fail.** graphics went 58/47 to
**97/8**, filesystem 23/10 to 26/7, and zero `tempoutput` failures remain.

### Triage so far

**`love.audio`: 19/12 → 25 pass / 6 fail.** Four defects, all fork-authored code
(`src/modules/audio/webaudio/` is ours — it is absent from the upstream mirror):

- **`Audio` kept no registry of playing sources.** `love.audio.stop()` was
  literally an empty function and `getActiveSourceCount()` returned a constant
  `0`, because there was nothing to answer from. Sources are now tracked while
  playing — and *retained* while tracked, as the OpenAL backend does, or
  stopping "all" would walk pointers the collector had already freed.
  `pause()` returns exactly the Sources it paused, which is what lets
  `love.audio.play(list)` resume them.
- **`Source:getDuration()` returned -1 for everything.** A static Source holds
  its whole PCM buffer, so its length is arithmetic; -1 ("unknown") was a lie
  for the one case that is knowable. STREAM and QUEUE keep -1 honestly.
- **`setDopplerScale` discarded its argument** while `setDistanceModel` stored
  its own — an inconsistency against this backend's stated convention, which is
  that unappliable spatialization state is *stored and reported* (Source.h).
- **The distance-model default was `DISTANCE_NONE`**, where desktop's is
  `DISTANCE_INVERSE_CLAMPED`.

The remaining **6 are declared divergences**, not defects: the mic's sample rate
is not settable in a browser; EFX effects and per-source filters have no
WebAudio equivalent in LÖVE's OpenAL-shaped model (`setEffect`, `getEffect`,
`getActiveEffects`, `Source:setFilter`); and output-device selection is gated.

**`love.filesystem`: 23/10 → 29 pass / 4 fail.** `mountFullPath` (blocker C)
took three of them; `remove` took a fourth:

- **`remove` could not delete a directory, and would delete a non-empty one.**
  Two host-side causes. `fs_mkdir` did not create intermediate directories,
  where physfs's does — so `createDirectory("foo/bar")` left no `foo` at all,
  and `remove("foo")` could never succeed. And `fs_remove` did not check
  emptiness, so removing a directory with a file still in it reported success.
  Both fixed in `fs-host.mjs`; no rebuild, since it is host JavaScript.

The remaining 6 divide into declared divergences and one defect worth naming:

| test | verdict |
|---|---|
| `mount`, `unmount` | archive mounting — **#48 (D7)**, open by decision |
| `mountCommonPath` | userdesktop / userhome / appdocuments / userappdata / userdocuments — a browser has no such paths |
| `getRealDirectory` | there are no real directories; the store is virtual |
| ~~`getInfo().readonly`~~ | **FIXED** — see below |
| ~~`isFused`~~ | **FIXED** — see below |

**`getInfo().readonly` — fixed by extending the seam.** `fs_stat` gained an
`out_readonly` param: the host reports which store answered, because it is the
side that resolves the two and they shadow each other. A file of the project is
read-only; a file of the save namespace is not; a directory is writable when
anything of the save namespace lives in it, since that is where a write to it
would land. `EMBEDDING.md`'s import table records the new signature, and its
deferral list drops the entry.

**`isFused` — fixed, in the two halves it needed.** `boot.lua:77` infers "fused"
from `pcall(setSource, exepath)` SUCCEEDING, and ours succeeded for anything: it
only recorded the path, where a desktop physfs `setSource` refuses a plain
executable. So `setSource` now requires a game to actually be there — `main.lua`
or `conf.lua`, the two files `boot.lua` goes on to look for — and the boot
wrapper seeds `arg` with a game argument, because the inference is read at
`boot.lua:92` *before* the non-fused branch reassigns `can_has_game`; without the
argument there would be no game at all once `setSource` stopped saying yes to
everything. That is the same route a desktop `love /path/to/game` takes.

It fixed three tests, not one: `love.setDeprecationOutput` had been switched off
by the false inference, so two `love` suite tests were failing with it. `love` is
now 6 pass / 0 fail.

The full sweep caught the cost, which is the point of running it: `run-fs2.sh`
asserted `setSource("/project")` succeeds — a path with no game in it — which
was the old permissive behaviour written down. Updated to the new contract, and
made *stronger* while there: it now asserts the refusal as well as the
acceptance, tested in that order because `setSource` is settable-once.

**The scattered nine, examined.** One defect, eight declared divergences:

- **`love.joystick.loadGamepadMappings` accepted anything — FIXED.** The wrap
  passes the argument through as mapping CONTENT when it does not name a file,
  so a mistyped filename arrived here as a mapping string and we returned
  happily; desktop rejects it while parsing. "Ignored" must not slide into
  "anything is accepted" — that hides the user's mistake instead of declaring a
  limitation. The shape is now checked (SDL mapping data is `GUID,name,binding,…`
  — at least two commas on a real line), and only the shape: it is still not
  parsed and still not applied, which is what the warning now says.
- `love.joystick.setGamepadMapping` (24 asserts) — no controller DB in a
  browser; the W3C standard mapping is fixed. Already declared in DESIGN.md 6.5.
- `love.mouse.setRelativeMode` / `getRelativeMode` — pointer lock is real but
  needs a **user gesture**, the same shape as `setFullscreen`: a game calling it
  from a click could work where a test never can.
- `love.mouse.setGrabbed` — cursor confinement has no browser API at all.
- `love.timer.sleep` and `getTime` — both are the same fact: `love::sleep` is an
  honest no-op because blocking the main thread is forbidden here, so no time
  passes across the test's sleep. `getTime` itself is fine; it is measuring a
  sleep that did not happen.
- `love.system.getOS` — returns `"Web"`, deliberately (readme's seam table). The
  corpus asserts membership of a desktop-only list, which has no Web entry.
- `love.sound.SoundData:getSample(0.001)` — **a D8 consequence, not a sound
  defect**: LÖVE takes a sample index with `luaL_checkinteger`, which truncates
  under 5.1 and raises under 5.4. Exactly the class the Lua-dialect decision
  named, showing up inside the corpus rather than in a game.

**`love.window`: 12 fail, and this is the honest shape of a page.** Nothing here
was implemented, because none of it can be done faithfully and the ones that
could be are gesture-gated:

| tests | what a page can do |
|---|---|
| `setPosition`, `getPosition` | nothing — a page cannot move its window |
| `maximize`, `minimize`, `isMaximized`, `isMinimized` | nothing |
| `setFullscreen`, `getFullscreen` | the Fullscreen API is real but needs a **user gesture**, so a game calling it from a keypress could work while this test never can |
| `setDisplaySleepEnabled`, `isDisplaySleepEnabled` | the Screen Wake Lock API is real, async and permission-gated — implementable, currently not |
| `setIcon`, `getIcon` | a favicon is the host document's business, not the canvas's |

So window's 12 divide into **6 impossible**, **2 possible only under a user
gesture**, and **4 implementable-but-unbuilt** (wake lock, icon). None of them
should be made to pass by storing a value the browser never applied — that is
the line between a declared divergence and a fake.

**What is left: 37 failures, every one examined.**
Its remaining 8 are worth naming because they set the shape of the triage:

| test | shape |
|---|---|
| `Image()` | DXT1 pixel format unsupported — a real WebGL2 divergence |
| `Video()`, `newVideo()` | `love.video` absent — expected |
| `arc()` | 3069/3072 pixels match |
| `circle()` | 1022/1024 |
| `ellipse()` | 1023/1024 |
| `setLineStyle()` | 224/256 |
| `Shader()` | **FIXED** — see below |

Four of those are near-miss rasterisation edges, which is what a different
rasteriser looks like and probably a declared divergence rather than a bug.

**`Shader()` was a genuine defect, and a much wider one than the test.**
`glReadPixels` allocated a `Uint8Array` whatever the pixel type was. WebGL2
requires the destination view to MATCH the type — `BYTE` needs an `Int8Array`,
`FLOAT` a `Float32Array` — and a mismatch is not a silent widening: it raises
`INVALID_OPERATION` and reads **nothing**, so the caller gets zeros. The size was
wrong for the same reason, `w*h*4` being true of RGBA8 and little else. So every
readback that was not `UNSIGNED_BYTE` came back as zeros — an integer render
target, and a float one too. Only the corpus's integer-canvas case happened to
exercise it. Both hosts fixed, view and size chosen from format and type. The rest of the residual
— audio 12, window 12, filesystem 7, mouse 3, joystick 2, timer 2, love 2,
system 1, sound 1 — is still unexamined, and that triage is step 3's actual
cost.

**Evidence:** every linked-module suite passes, with each divergence marked
expected-fail and listed explicitly. Never silently failing.

### 4. `love.thread` (build-order step 7)

**Design-doc-first:** a `wasi/thread/DESIGN.md` pass surfacing its own
decisions before any code. **Not in Beta** — a declared Beta limitation, since
most `.love` games do not use it. The architecture is a fixed constraint rather
than an open fork: **message-passing Web Workers only**, because
`SharedArrayBuffer` and cross-origin isolation are ruled out by the pillar that
this engine runs on any static host, leaving the share-nothing Channel path as
the only faithful option.

### 5. Declared divergences stay declared

Video (Theora) stays dropped; a future `<video>` seam is the right path.
Networking stays absent for Beta; a web-native transport is a later
exploration. Archive/`.love`-zip mounting stays enumeration-only, with D7 left
open until a real game needs a runtime mount.

## Open decisions

These gate work, and only the Human closes them (`AGENTS.md`, "Records").

| Decision | The fork | What it gates |
|---|---|---|
| #47 (D4) | reload granularity: whole-chunk re-eval vs function-body hotswap | deferred past Beta; module granularity plus restart is what ships |
| #48 (D7) | who unzips a runtime-mounted archive: host JS vs a guest zip reader over the in-tree zlib | archive mounting; enumeration shipped without needing it |
| step-7 divergences | which desktop `love.thread` behaviors we accept losing | enumerated when the thread design document is written |
| #7 | packaging: single `.js` vs `.js` + `.wasm` | step 8, decided by measurement, post-Beta |

`DESIGN.md` records D1–D3, D5 and D6 as closed, carrying the alternatives that
lost. D4 and D7 are open, so under `CONTRIBUTING.md` §3.3 they live in the
tracker — #47 and #48 — and `DESIGN.md` keeps only what is settled about each
and points at the issue. D8 (Lua dialect) closed this session and is recorded in
`DESIGN.md` in full.

### The Lua dialect — CLOSED, and where it now lives

Settled by the Human: **PUC Lua 5.4 stays, LÖVE 12 stays.** Both are deliberate
choices, not accidents to be corrected — 5.4 fits wasm, Lua's 5.x line is
incremental by design, and 12 is where LÖVE is going. Recorded as **D8** in
`wasi/platform/DESIGN.md` with the alternative that lost and its reopen
conditions; the game-facing surface is **The Lua dialect** in `readme.md`.

The framing that was wrong, and is corrected in both documents: a game whose Lua
is ported into 5.4 is still a LÖVE game. What this project measures is whether a
LÖVE **feature** works, not how a game's Lua was wired up. And the `.love`
pillar is *outbound* — "the same source runs unmodified **on desktop LÖVE**; a
game made here can go to desktop and back" — so it was never a promise that
arbitrary 5.1-era source runs here untouched. Earlier entries in this file cited
it the wrong way round.

No compatibility shim ships. The probe build (`-DLUA_FLOORN2I=F2Ifloor`) and the
boot-wrapper preamble were reverted and stay reverted.

## Practical notes

- **A pull request's base is `wasi`.** The repository began as a fork of
  `love2d/love`, so the host may default a new pull request's base to the
  upstream parent. `main` is the pristine upstream mirror and is never a merge
  target.
- **A merged pull request here displays as "closed"** rather than with the
  purple "merged" badge. Judge a merge by whether its commits landed on `wasi`.
- **The dependency cache is `$HOME/.love.wasm`.** The first session after that
  rename re-fetches the wasm-EH sysroot once.
