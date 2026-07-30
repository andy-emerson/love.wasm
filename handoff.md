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

What is still unproven: no third-party `.love` has run — the projects so far are
real, desktop-compatible LÖVE, but written here — and the `testing/` corpus has
not been run under this build.

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

**The blocker, confirmed against two real games and not their fault.** LÖVE
enables every module by default and `boot.lua` requires each enabled one. Neither
game sets `t.modules.*`, so both die in boot before reaching `main.lua` —
`touch`, `video` and `thread` are enabled by default and the union artifact links
none of them. No game-side filter catches this, and requiring every game to edit
its `conf.lua` would break the `.love`-runs-unmodified pillar outright.

### 2a. Widen the artifact so a default `conf.lua` boots — DO THIS FIRST

**Needs the Human to confirm**, because it changes the module-disposition table
in `readme.md`.

| Module | What it needs | Backend today |
|---|---|---|
| `joystick` | link it | `wasi/platform/joystick-backend.cpp`, real and witnessed |
| `sensor` | link it | `wasi/platform/sensor-backend.cpp`, the #27 warned stub |
| `touch` | a new warned stub | SDL only |
| `video` | a module-level warned stub so `require` succeeds | none, Theora dropped |
| `thread` | a module-level warned stub so `require` succeeds | none, step 7 |

`joystick` and `sensor` are a `config-game` change. The other three want the
already-ratified #27 warned-stub tier: `require` succeeds, the API is honestly
inert, first use emits one `[love.wasm preview]` notice. That keeps the
divergence declared rather than faked, and it is what lets an unmodified game
boot.

**Then:** run legend-of-lua through `wasi/shell/serve.sh 8080 <clone>`.
**Evidence:** boots, playable, no crash, visually plausible. Pixel parity is
step 3's job.

**Unknown worth measuring, not assuming:** the game targets **1920x1080**. Every
witness so far renders 64x64 or 96x64, so nothing yet says the WebGL2 path
handles a canvas that size, or at what frame cost.

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
| #47 (D4) | reload granularity: whole-chunk re-eval vs function-body hotswap | deferred past Beta; module granularity plus restart is what ships |
| #48 (D7) | who unzips a runtime-mounted archive: host JS vs a guest zip reader over the in-tree zlib | archive mounting; enumeration shipped without needing it |
| step-7 divergences | which desktop `love.thread` behaviors we accept losing | enumerated when the thread design document is written |
| #7 | packaging: single `.js` vs `.js` + `.wasm` | step 8, decided by measurement, post-Beta |

`DESIGN.md` records D1–D3, D5 and D6 as closed, carrying the alternatives that
lost. D4 and D7 are open, so under `CONTRIBUTING.md` §3.3 they live in the
tracker — #47 and #48 — and `DESIGN.md` keeps only what is settled about each
and points at the issue.

## Practical notes

- **A pull request's base is `wasi`.** The repository began as a fork of
  `love2d/love`, so the host may default a new pull request's base to the
  upstream parent. `main` is the pristine upstream mirror and is never a merge
  target.
- **A merged pull request here displays as "closed"** rather than with the
  purple "merged" badge. Judge a merge by whether its commits landed on `wasi`.
- **The dependency cache is `$HOME/.love.wasm`.** The first session after that
  rename re-fetches the wasm-EH sysroot once.
