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
keyboard and mouse events into `love.event`, and applies an edit — a module or
`main.lua` itself (#56 function-body hotswap, state intact) — to the running
game without a reload. Beta step 1 is done, witnessed by `wasi/shell/run.sh`
(and `wasi/shell/run-hotswap.sh`) and CI-enforced.

A third-party game runs too: `challacade/legend-of-lua`, at 1920x1080, playable,
and **re-runnable** — `wasi/games/run.sh` fetches the pin, applies our port
patch, plays it and asserts. Its Lua needs a 5.1 → 5.4 port; every LÖVE feature
it uses works. See step 2, and **The Lua dialect** in `readme.md`.

The `testing/` corpus runs as a **witness** — `wasi/corpus/run.sh`, **306 pass /
34 fail / 15 skip** across 21 suites, up from 236/92 when it first ran. Every
failure is classified, and the comparison against that classification is what the
witness asserts. See step 3.

**`wasi/COMPATIBILITY.md` is the durable home for what works where**: every LÖVE
feature against desktop and against this build, ✓ / ✗ / blank. It replaces the
flat failure count with the question that actually matters — does the target have
the feature at all — and it resolves the 34 into **30 blanks** (the browser does
not have it) and **4 grant-/gesture-gated** (fullscreen and, since #58, the
Screen Wake Lock) — the real-gap count is **zero**. Its failing half is `wasi/corpus/expected.txt`, so the
classification is executable rather than prose. It also surfaced the four ✗
cells the corpus never probes, which #58 then closed.

`love.thread` is the one major module still stubbed (build-order step 7).

**The unbuilt-work audit (this session): decisions were outrunning
implementations, and three ideas existed nowhere but prose or conversation.**
Now in the tracker, per `CONTRIBUTING.md` §3.3:

- **#55 — D2's OPFS save store** (decided, documented as built, never
  implemented — the sharpest instance of the pattern) — **built**:
  `wasi/host/fs-opfs.mjs` wraps the reference fs host (same `love_fs` imports;
  the in-memory map stays the synchronous truth; eager per-write flush plus a
  `pagehide`/`visibilitychange` retry; `boot()` hydrates before `pump_boot`).
  Evidence: `wasi/shell/run-durability.sh` — write through `love.filesystem`,
  `page.reload()`, read the payload back; demonstrated able to fail by the
  `?opfs=0` leg, which must come back empty. The docs' present-tense claims are
  true again. Not yet in `witness.yml` (the Agent's token lacks workflow scope —
  same as the corpus step, which the Human wired by hand).
- **#56 — D4=B hotswap**, the implementation of the freshly closed ruling —
  **built**: `pump_hotswap` beside `pump_invalidate` in the pump (the edited
  chunk re-runs in a capture environment; replaced functions' same-named
  upvalues are `debug.upvaluejoin`ed to the old cells, so file-scope state
  survives, still shared), exposed on `boot()`'s handle as `hotswap(path)` and
  routed by the shell's watcher, so a `main.lua` edit is live instead of
  restart-only. Evidence: `wasi/shell/run-hotswap.sh` — four legs in the D4
  record's order (new body at next call; state survived and shared; a broken
  save errors on the user's line with the session intact; `love.load` once per
  session), each demonstrated able to fail. The restart-only residue is
  declared in `EMBEDDING.md` §4. Not yet in `witness.yml` (the Agent's token
  lacks workflow scope — same as the corpus step, which the Human wired by
  hand).
- **#57 — the `boot({files, canvas, onLog})` library entry point** — **built**:
  `wasi/shell/boot.mjs` exports the consumer-invariant wiring (instantiate, bind,
  the `WebAssembly.Module.imports()` skew check, pump boot, the rAF loop with the
  blur/visibility pause) and returns a handle; `player.mjs` is the first caller,
  and `EMBEDDING.md` §2 documents it as the recommended consumption shape.
  Evidence: the shell witness passes unchanged over the new seam.
- **#58 — the five constant-answer gaps** (wake lock, hasFocus/hasMouseFocus,
  getSystemTheme, image cursors, gamepad rumble), previously visible only as
  COMPATIBILITY ✗ cells — **built**: each rides a host import in the existing
  seam style (`love_win` wake-lock request/release + held-state + theme;
  FOCUS/MOUSEFOCUS into the input snapshot, read by the window backend over
  weak hooks; RGBA8 pixels + hotspot → a data-URL CSS cursor over `love_input`;
  `vibrationActuator` dual-rumble over `love_gamepad`), and each witness asserts
  the host **observed** the request — all demonstrated able to fail. The ✗
  column is now empty; the wake lock lands as **~** (the grant is async and
  permission-gated, and headless Chromium refuses it, so `expected.txt` keeps
  its two lines reworded to the fullscreen shape), and honest reporting held:
  `isDisplaySleepEnabled` reflects only a lock actually held.

**#27 closed** — the warn-once mechanism shipped long ago and
COMPATIBILITY.md + expected.txt are its "declared disposition table", exceeded.
Its one unbuilt idea (LoveIDE-side static pre-scan) is noted in the closing
comment as belonging downstream. **#51 closes when its branch merges.**
Deliberately still open: #7 (pending the LoveIDE measurement), #23 and #54
(standing upstream-contribution records).

Parked ideas that stay in prose deliberately, each with a named trigger:
D6 option B (structured console tap — if stdio proves insufficient for the
agent), the engine-in-Worker + OPFS sync-handle pivot (a shipping variant that
needs sync durability), `love.video` over a `<video>` seam, a web-native
networking transport, and the COMPATIBILITY mobile column (whoever can ground
it from love-ios/love-android).

## Beta

**Beta = real games playable interactively from a standalone dev artifact, with
the `testing/` corpus green modulo declared divergences.** (It needs no slicing:
`testing/main.lua` gates every suite on `if love.<module> ~= nil`, so the whole
corpus runs in one shot — the recorded plan to run it by module slice was wrong.) Packaging
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
host. Live-edit is module granularity over the existing `pump_invalidate()` for
`require`'d files, and **function-body hotswap for `main.lua` (D4=B, #47,
built as #56)** — an edit takes effect at the function's next call with
file-scope state intact. `conf.lua` is init-only by the reload invariant, so
restart-only remains its honest report.

Divergences declared in the host's own header: physical-`code` keys mapped to a
US layout, no IME, normalized wheel deltas, and pointer-lock and cursor-warp
reported as failures rather than faked.

**Evidence:** `wasi/shell/run.sh` in real Chromium, in `witness.yml`. A project
from disk runs (its own `conf.lua` sizes the canvas, and an asset is read from a
subdirectory); real DOM key events move the game, it stops on keyup, and it moves
back on the opposite key; a module edited on disk reaches the running instance,
a `main.lua` edit is hotswapped into it (#56 — `wasi/shell/run-hotswap.sh`
carries the deep state-survival legs), and a `conf.lua` edit is reported
restart-only rather than silently ignored.

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
| after the three fixes (census session) | 303 | 37 | 15 |

(Historical: the census session's snapshot. The corpus witness now measures
**306/34/15** — see step 3.) Per suite at that snapshot (▲ marks what the three
fixes moved):

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
| `mount`, `unmount` | archive mounting — **#48 (D7)**, closed as deliberately not built |
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
exercise it. Both hosts fixed, view and size chosen from format and type. (The residual named
here as "still unexamined" was examined in the same session — see the
classification below and `wasi/corpus/expected.txt`.)

**The 37 are now classified, in `wasi/COMPATIBILITY.md`.** The reframing is the
Human's: correctness is judged against the system a game is deployed to, not
against one universal bar — a browser game works in a browser, a Windows game
works on Windows. So the table puts every LÖVE feature on the y axis and the
deployment targets on the x axis, and marks ✓ where the target has the feature
and this build does it, ✗ where the target has it and we do not, and **blank**
where the target does not have it. A blank is a declared divergence, and it is
the cell that does the work: it separates "`setPosition` is broken" from "a page
cannot move its window".

The 37 resolve as **30 blank, 4 gesture-gated (`~`), 3 real gaps** — the wake
lock (unbuilt) and DXT1 (**#51**, the extension-enumeration defect). Archive
mount moved from ✗ to blank when D7 closed as not-built. Four of the 30 are the rasterisation near-misses,
and they are the only group a decision could still move.

**#51 — FIXED this session.** The host now answers `GL_NUM_EXTENSIONS` and
`glGetStringi` from `gl.getSupportedExtensions()`, translated to the spellings
glad asks for (one WebGL extension can satisfy several GL names — s3tc is the
DXT1/3/5 trio LÖVE checks separately), and **activates** each with
`getExtension`, because a WebGL extension is inert until it is. `glGetStringi`
was added to the generated import shim: glad calls it from `find_extensions()`,
which the generator's scrape of the *backend* could never see. The four
compressed-upload entry points are implemented rather than warn-stubs, so a
format reported supported can actually be uploaded.

Smaller than feared: Chromium exposes 29 extensions, and intersected with the 39
`GLAD_*` flags the `opengl` backend reads, only ~11 flip true — all format and
capability flags, not new desktop-GL entry points. `graphics/Image` passes,
corpus **306/34**, and all 20 graphics legs stay green. **The witness caught its
own staleness**: with `graphics/Image` still listed as a defect the run failed
with "on the expected-fail list but PASSING", which is precisely the mode that
stops a fix landing without striking its line. Demonstrated able to fail:
disabling the enumeration brings back "The DXT1 pixel format is not supported on
this system."

**The original reading of #51 was wrong, and the record is worth keeping.** `glGetStringi` is not
auto-stubbed; it is not imported at all, and `getStaticGLProcAddress` returns
null for it. Nothing traps only because `GL_NUM_EXTENSIONS` has no WebGL2
`getParameter` pname — `gl.getParameter` raises `INVALID_ENUM`, returns null,
the host writes `null|0` = 0, and glad's `has_ext` loop never reaches the null
pointer. So the two halves cannot be fixed independently: answering the count
without importing `glGetStringi` converts a silent wrong answer into a trap.
All **491** `GLAD_*` flags are false, of which the `opengl` backend reads ~39 —
DXT1 is only the one the corpus probes. Not an easy fix: it needs a
WebGL→GL name map, `gl.getExtension` activation (listing without activating
would be a fake), the currently-stubbed `glCompressedTexImage2D` path, and a
staged re-run of all 20 graphics legs, since flipping ~39 flags sends the
backend down paths this build has never taken.

Two columns, not more: **Desktop** (read out of upstream's source, which `main`
carries byte-for-byte) and **Web** (ours, the only column carrying our own
evidence). **Mobile was deliberately left out** — `love-ios` and `love-android`
are outside this tree, so that column would be guesswork. Worth adding by
whoever can ground it; it would show most of the blanks are not a browser
peculiarity.

**It also found four ✗ cells the corpus does not probe**, which no failure count
would have surfaced: `hasFocus`/`hasMouseFocus` return a constant `true` where a
page genuinely knows (`document.hasFocus()`, `blur`/`focus`); `getSystemTheme`
reports `unknown` where `prefers-color-scheme` is real; custom image cursors
(a data-URL CSS cursor) are unbuilt; gamepad vibration (`vibrationActuator`) is
unbuilt. None is in the corpus's failure set.

**Evidence: tested where the corpus reaches it.** Every ✓ traces to a witness
run or to the corpus at 306/34/15, every blank to a named platform fact — and
the mapping is re-checked on every push, because `expected.txt` is the failing
half of the table and the corpus witness compares against it in CI. The rows
the corpus does not probe (the four ✗ cells above, and the Desktop column)
remain observed.

### Step 3 — DONE. The classification is executable and in CI.

`wasi/corpus/run.sh` + `run-browser-corpus.mjs` + `expected.txt`. The corpus runs
as an ordinary game — `testing/` IS the project, its own conf.lua sizes the
canvas, boot.lua loads its main.lua — and the driver pumps until the suite calls
`love.event.quit`, then reads the JUnit report **out of the save namespace** the
engine wrote it to. Per-test names come from that XML, so nothing is scraped from
a console.

**The comparison is the witness**, and all three modes are demonstrated able to
fail: a failure classified nowhere, an expected-fail entry that starts passing,
and an entry naming a test the corpus does not have (a renamed or deleted test
cannot hide a real failure behind a dead line).

**306 pass / 34 fail / 15 skip**, deterministic across three back-to-back runs,
**~18s** on a reused artifact — cheap enough for the per-push gate rather than
on demand.

**The loose end closed: the corpus witness is in `witness.yml`.** The Agent's
push lacked `workflow` scope, so the Human committed the step directly on `wasi`
(0153f8ebb, corrected in 9e680bc6b after a paste artifact briefly made the whole
workflow unparseable — worth remembering that a malformed workflow does not go
red, it silently never runs). Step 3 is fully closed: the corpus runs on every
push.
The 34 are 30 divergence / 2 gesture / 2 defect.

Two numbers moved from the recorded census snapshot (303/37): `mouse.setRelativeMode` and
`getRelativeMode` now pass. The earlier ad-hoc census ran with the 6.4 input
host's **baked event script** replaying, which polluted mouse state — and whose
last record is a QUIT, which is why the first corpus run here died after one
frame. The driver silences `input_poll`, which is the honest shape for a run
with no user. Worth remembering: that fixture is a trap for any driver that
reuses the input host.

**The corpus immediately earned its keep.** Run against the rebuilt artifact it
caught a regression this session's code review had just introduced: moving
tracking into `Source::play()` was right, but it exposed that `playing` never
clears when a clip ends on its own, so `love.audio.pause()` handed back every
Source ever played (`audio/pause`: "check nothing paused, expected 0 got 1").
Fixed properly rather than reverted — `isPlaying()` now runs a non-looping STATIC
Source against the clock, since its duration is knowable, and `pause()` /
`getActiveSourceCount()` reap before answering. STREAM and QUEUE keep the old
behaviour, honestly, because their length is not known.

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
exploration. Runtime archive/`.love`-zip mounting is now a divergence in its
own right: **D7 closed as not built** (#48), reopening only if a real game calls
`mount` on an archive.

## Open decisions

These gate work, and only the Human closes them (`AGENTS.md`, "Records").

| Decision | The fork | What it gates |
|---|---|---|
| step-7 divergences | which desktop `love.thread` behaviors we accept losing | enumerated when the thread design document is written |
| #7 | packaging: single `.js` vs `.js` + `.wasm` | step 8, decided by measurement — newly actionable, since LoveIDE (the measuring consumer) is now reachable |

**Two decisions closed this session, and one dissolved:**

- **#47 (D4) — CLOSED: B, function-body hotswap.** The Human's ruling, driven
  by play-testing: live-edit exists so a bug found two hours into a session is
  fixed *in that session*, and any state-resetting mechanism forfeits that. The
  responsibility line is set too — a broken saved edit fails on the user's own
  code at its next call; the engine performs the swap, it does not validate it.
  Full record in `DESIGN.md` D4, with why A and C lost. **Implemented as #56**
  (see the tracker bullet above): `pump_hotswap` in the reload path, witnessed
  by `wasi/shell/run-hotswap.sh`.
- **Rasterisation tolerance — DISSOLVED by measurement (#54).** Not a decision:
  the four failures are upstream test-harness tolerance gates that don't know a
  Web target. Measured per pixel: arc/circle/ellipse differ by 1–2 boundary
  pixels each, every one matching a neighbouring reference pixel exactly (a
  driver fill-rule tie-break); setLineStyle is uniformly 3/255 in one channel
  of an AA blend. The harness already has the knobs and already grants them —
  gated on `isOS('Linux')`. The fix is an upstream patch to
  `testing/tests/graphics.lua`; filed as **#54** alongside #23. Nothing on our
  side to build, and `expected.txt` now carries the measured reasons.

`DESIGN.md` records D1–D6 as closed, carrying the alternatives that lost —
D4 closed this session (#47, ruled B; see above). **D7
closed this session** (#48), ruled *not built*: the survey was re-checked before
closing and had a hole — both recorded options answered *who* unzips and so
presupposed that we unzip at all. The full record, with both alternatives and
why each lost, is in `DESIGN.md`. D8 (Lua dialect) closed this session and is recorded in
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
