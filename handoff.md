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

Two limits on that sentence, both deliberate. The game is a **test fixture
written into the witness** (`wasi/platform/run-browser-game.mjs`) — a real,
desktop-compatible LÖVE project, but not a third-party `.love` — and it runs
**headless under Playwright**, not as a page anyone can play. The `testing/`
corpus has not been run under this build.

`love.thread` is the one major module still stubbed (build-order step 7).

## Beta

**Beta = real games playable interactively from a standalone dev artifact, with
the sliced `testing/` corpus green modulo declared divergences.** Packaging
(#7, build-order step 8) is post-Beta: love.wasm must be demonstrably operable
on its own, which is not the same as building every downstream consumer.

Five steps get there, and each names the evidence that will close it.

### 1. Interactive standalone shell — the next step

A minimal browser page that instantiates the union artifact, wires the existing
host seams to **live** sources, pumps on `requestAnimationFrame`, and shows a
playable canvas. This is assembly of seams that already exist rather than new
engine work: the host fulfillers in `wasi/host/` are written, and
`run-browser-game.mjs` already boots the real `boot.lua` on rAF. What is missing
is that those hosts are consumed by **stringification into a Playwright page**,
driven by a **baked event script**, against a **canned in-memory project**.
Step 1 turns each of the three into a live source.

- **Shape:** game-player only. Not a REPL, not an editor or agent UI — that is
  the downstream consumer's job.
- **Live input:** forward real DOM events into the `love_input` seam. Forward
  the common events, `preventDefault` on game keys, pause on tab blur; IME and
  pointer-lock are deferred. `input-host.mjs` is self-contained by contract so
  both witness legs can share one host, so the live version is a sibling —
  `gl-host.mjs` / `gl-host-browser.mjs` is the precedent already in the tree —
  not an edit to it.
- **Live-edit:** module granularity only, over the existing `pump_invalidate()`
  and write path. `main.lua`-direct live-edit stays deferred (D4); restart is
  the fallback.
- **Packaging:** stays a local dev artifact loading the raw `.wasm`. Does not
  touch #7.
- **Evidence that closes it:** a witness driving the real page in Chromium —
  synthetic DOM key events through the live input path, an assertion that the
  game visibly responds, and one reload cycle — wired into `witness.yml`. That
  needs a fixture that responds to input; the present one only falls under
  gravity.

### 2. Real third-party games

Run actual open-source LÖVE 12 games rather than the fixture. **Do not bundle a
game in the repository** — keep a local folder of a few small free ones.
Selection: pure LÖVE inside the linked envelope (no `love.thread`, no
`love.video`, no networking), preferring games that have corpus `expected/`
outputs where possible. **Evidence:** boots, playable, no crash, visually
plausible. Pixel parity is step 3's job.

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
| D4 (`DESIGN.md`) | reload granularity: whole-chunk re-eval vs function-body hotswap | deferred past Beta; module granularity plus restart is what ships |
| D7 (`DESIGN.md`) | who unzips a runtime-mounted archive: host JS vs a guest zip reader over the in-tree zlib | archive mounting; enumeration shipped without needing it |
| step-7 divergences | which desktop `love.thread` behaviors we accept losing | enumerated when the thread design document is written |
| #7 | packaging: single `.js` vs `.js` + `.wasm` | step 8, decided by measurement, post-Beta |

`DESIGN.md` records D1–D3, D5 and D6 as closed, carrying the alternatives that
lost. Under `CONTRIBUTING.md` §3.3 an open decision belongs in the issue tracker
rather than inside a durable document, so D4 and D7 want promoting to issues;
that has not been done.

## Practical notes

- **A pull request's base is `wasi`.** The repository began as a fork of
  `love2d/love`, so the host may default a new pull request's base to the
  upstream parent. `main` is the pristine upstream mirror and is never a merge
  target.
- **A merged pull request here displays as "closed"** rather than with the
  purple "merged" badge. Judge a merge by whether its commits landed on `wasi`.
- **The dependency cache is `$HOME/.love.wasm`.** The first session after that
  rename re-fetches the wasm-EH sysroot once.
