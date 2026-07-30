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

A third-party game runs too: `challacade/legend-of-lua`, unmodified, at
1920x1080 — though only with a Lua 5.1 compatibility layer that is **not** on
this branch, because it answers an open decision. See step 2.

What is still unproven: the `testing/` corpus has not been run under this build,
and neither of step 2's two fixes has a witness.

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

### 2. Real third-party games — IN PROGRESS

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
- Every module it touches is inside the sixteen the union artifact links:
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

**It runs.** Legend of Lua boots from its own `conf.lua`, opens a 1920x1080
canvas, and plays: tilemap, trees, water, shadows, sprites, the equip UI and text
all draw, keys move the game, and GL reports no error. Getting there took two
fixes, both ours and both now on this branch, and it still needs one thing that
is **not** on this branch because it answers an open decision — see "The Lua
gap" below.

Three findings, in the order they were hit:

**1. Module defaults — fixed (was step 2a).** `boot.lua:204` defaults every one
of the twenty modules to `true`, then loads them with a bare
`require("love." .. v)` that hard-errors on a missing module. So `t.modules.*` has
never been required of any game, on 11 or 12 — omitting it is idiomatic, and on
desktop the default is always satisfiable because desktop links everything. It
becomes unsatisfiable only on a build shipping a subset, which is ours.

The boot wrapper now preloads the modules this build does not link, reading
linked-ness from `package.preload` rather than a list, so linking one for real
retires its stub with no edit. It deliberately does **not** set `love.<name>`,
which leaves the engine in the shape desktop has when a game sets
`t.modules.<name> = false` — `callbacks.lua`'s `if love.joystick then` takes the
absent path instead of calling into a stub. No new guarded seam (the count stays
ten), no `src/` change, no rebuild.

The bargain stated plainly: this is correct for a module a game *enables but
never calls*. A game that really uses `love.video` gets a nil index and fails
loudly, which is the honest outcome. "Boots" and "works" stay separate claims.

Two things it deliberately does not do. Editing a game's `conf.lua` voids the
`.love`-runs-unmodified pillar. Changing `boot.lua`'s defaults is a fork-private
edit to shared engine source (lane 3, forbidden) and would make `love.conf`
report something desktop does not.

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

Reproduced in an 8-line project: create one trivial passthrough shader, draw two
rectangles, and the rectangles vanish. That repro should become the witness.

**3. The Lua gap — OPEN, and the last thing between us and unmodified games.**
See "Open decisions".

**Tier 2, still to do — link `joystick` and `sensor` for real.** Both have
witnessed wasm backends (`wasi/platform/{joystick,sensor}-backend.cpp`), so
stubbing them is a lie where the truth is cheap: a `config-game` change plus the
sources `build-joystick.sh` already lists. Costs a ~6 min rebuild and a re-run of
the union and shell witnesses. `touch`, `video` and `thread` keep the stub —
bespoke backends would add guarded seams for no gain, and `thread` stays step 7's
problem.

**Measured, not assumed:** 1920x1080 renders correctly. A minimal project at that
size draws rectangles and text exactly as the 96x64 fixtures do, and the game
fills the canvas. The earlier worry that nothing above 96x64 had ever been tried
is closed.

**Not yet earned:** neither fix has a witness, so both are **observed**, not
tested. Nothing in CI would catch a regression of either.

[lol]: https://github.com/challacade/legend-of-lua

### 3. Sliced corpus parity

Run the `testing/` `love.test.*` suites for the linked modules and diff.
Reference is the committed `testing/**/expected/` outputs, with version skew
noted. The full corpus cannot run in one shot — it exercises unlinked `thread`
and `video` — so run it **by module slice**. **Evidence:** every linked-module
suite passes, with each divergence marked expected-fail and listed explicitly.
Never silently failing.

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
| **Lua dialect** | **which Lua surface a game sees: 5.4 as-is, 5.4 made to look like 5.1, or actually vendoring 5.1** | **every game; step 2 cannot close without it** |
| #47 (D4) | reload granularity: whole-chunk re-eval vs function-body hotswap | deferred past Beta; module granularity plus restart is what ships |
| #48 (D7) | who unzips a runtime-mounted archive: host JS vs a guest zip reader over the in-tree zlib | archive mounting; enumeration shipped without needing it |
| step-7 divergences | which desktop `love.thread` behaviors we accept losing | enumerated when the thread design document is written |
| #7 | packaging: single `.js` vs `.js` + `.wasm` | step 8, decided by measurement, post-Beta |

`DESIGN.md` records D1–D3, D5 and D6 as closed, carrying the alternatives that
lost. D4 and D7 are open, so under `CONTRIBUTING.md` §3.3 they live in the
tracker — #47 and #48 — and `DESIGN.md` keeps only what is settled about each
and points at the issue. The Lua-dialect decision is new and has no issue yet.

### The Lua dialect decision

**What forces it.** **LÖVE 12 is a Lua 5.1 engine, in both of its
configurations.** `CMakeLists.txt:214` offers exactly one fork: `LOVE_JIT` on
gives LuaJIT 2.1 (which implements 5.1), `LOVE_JIT` off gives `find_package(Lua51
REQUIRED)`. It defaults on everywhere but Apple, where it defaults off. There is
no Lua 5.4 build of LÖVE. `src/libraries/lua53/` confirms the baseline from the
other direction: it *backports* 5.3's `lstrlib` and `lutf8lib` into a 5.1 world.

What does exist is **build-time** compatibility: three `LUA_VERSION_NUM >= 504`
branches (`src/love.cpp:266`, `common/runtime.cpp:1191` and `luax_objlen`) let
the engine compile against 5.4, and `changes.txt:203` records it as exactly that
— "Fixed build-time compatibility with Lua 5.4", in **11.4**, not 12. That is C
API portability, and it is what makes this build possible at all. It says nothing
about the standard library or the VM, which is where games break.

LuaJIT has no wasm backend, so this build vendors **PUC Lua 5.4** — a choice made
early and never recorded as a decision. So we are running LÖVE 12 off its
supported matrix, against a language every existing game predates. Legend of Lua
hit three instances before its title screen, and none is the game's fault:

| What the game does | LuaJIT / 5.1 | our Lua 5.4 |
|---|---|---|
| `newFont(path, 4.5*scale)` | truncates silently | **errors**: "number has no integer representation" |
| `unpack(t)` | a global | removed; it is `table.unpack` |
| `math.atan2(y, x)` | present | removed; it is `math.atan(y, x)` |

The first is the wide one. LÖVE's C API takes sizes with `luaL_optinteger`, which
truncates under 5.1 and raises under 5.4 — so **any** game computing a size from
a scale factor dies, and computing sizes from a scale factor is what every game
that supports more than one resolution does.

**The options.**

- **A. Keep 5.4, make it look like 5.1.** Two parts: `-DLUA_FLOORN2I=F2Ifloor`
  on the vendored Lua (a documented knob in `lvm.h`) restores silent float→int
  conversion, and a compatibility preamble in the boot wrapper restores the
  missing library functions. Both are in our lane. **Measured: this works.** With
  both applied, the completely unmodified clone runs, pixel-identical to the
  patched run. Its permanent gaps: `tostring(3.0)` is `"3.0"` where 5.1 says
  `"3"`, which shows up in *displayed text*; `setfenv`/`getfenv` can only be
  approximated over `_ENV`; and any 5.3+ parse error in a game is still fatal.
- **B. Vendor Lua 5.1.5.** Not an alternative dialect but *the* one: 5.1 is what
  LÖVE 12's own build produces, what its Lua is written against, and what every
  existing game targets. It removes the whole class rather than patching
  instances. Costs: no integers, no `goto`, none of 5.4's own fixes, and — the
  real bill — `lua.wasm` is a 5.4 source drop, so `onelua.c` (a 5.4
  amalgamation), `LUAW_EXTERNAL_EH` and the wasm `setjmp` shim are all 5.4-shaped
  work that would need redoing against a 5.1 tree.
- **C. Declare it a divergence.** Games must be 5.4-clean. Cheapest, and it
  breaks the `.love`-runs-unmodified pillar for a very common pattern. Recorded
  for completeness; not recommended.

**Recommendation: A as the cheap thing that works, B spiked before Beta closes.**
A is measured, small and reversible, but it is a permanent shim over a mismatch
that will keep producing findings like these three; calling it "the answer" would
overstate it. B is the baseline the engine was built for, and the only unknown
that matters is how much of the wasm toolchain assumes 5.4. That is a spike, and
it belongs before Beta closes rather than after — the longer A stands, the more
of the shim there is to unwind.

**Correction owed to `readme.md` in the doc pass:** line 62 says "LÖVE 12
supports Lua 5.4 natively". "Natively" is wrong and "supports" is too strong —
it *compiles* against 5.4 by way of three portability branches, and its build
system cannot produce such a build. The citation to `love.cpp` should also read
`src/love.cpp`, not `src/modules/love/love.cpp`.

**How the survey was made:** by running one real game to its title screen and
reading every failure, plus reading `luaL_optinteger`'s definition in both
dialects. It is not a systematic audit of the 5.1↔5.4 delta, so treat the option
list as observed, not complete, and re-check it before the decision closes.

**Where the evidence sits:** the probe build with `-DLUA_FLOORN2I=F2Ifloor` and
the boot-wrapper preamble were both **reverted**, because landing them would
entrench an answer. Reproducing them is a one-line build-flag change and a
ten-line preamble.

## Practical notes

- **A pull request's base is `wasi`.** The repository began as a fork of
  `love2d/love`, so the host may default a new pull request's base to the
  upstream parent. `main` is the pristine upstream mirror and is never a merge
  target.
- **A merged pull request here displays as "closed"** rather than with the
  purple "merged" badge. Judge a merge by whether its commits landed on `wasi`.
- **The dependency cache is `$HOME/.love.wasm`.** The first session after that
  rename re-fetches the wasm-EH sysroot once.
