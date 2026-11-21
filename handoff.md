# handoff — `claude/repo-suggestions-review-198mij`

**Branch-scoped. Do not merge this file to `main`.** `handoff.md` was deliberately
retired from the trunk in `03ab2ae` — *"its live half is Issues, its durable half
already landed"* — and that still holds: the record of record is Issues +
`wasi/DECISIONS.md`, and `AGENTS.md` says living status stays out of durable
documents. This copy exists only so a fresh session can pick up this branch, and
it should be deleted in the merge that closes the branch.

Written 2026-11-21. Everything below is a pointer to something durable; where
this file and an issue disagree, the issue is right.

---

## 1. What this branch is

It started as an assessment of a handoff document proposing nine upgrades, and
became two things: **filing what had been living in chat** (decisions D15–D21,
issues #89–#103) and **building the first two of them**. Two commits are on the
branch beyond `main`:

| commit | what |
|---|---|
| `6493d56` | **#88** — `love.audio` listener and `Source` position/orientation/velocity: twelve empty-bodied functions returning uninitialized stack memory. Live UB, fixed, storage added. |
| `cee32dd` | **#102** — reshaped the scalar `Matrix4::multiply` so LLVM's SLP vectorizer takes it. Bit-identical, 2.58× on the function, **no new seam**. |

Both are pushed. `main..HEAD` is exactly those two.

## 2. Where each thread stands

### Landed and measured
- **#102 — ruled B, done.** Aliasing was *not* the cause (`-fno-strict-aliasing`
  made no difference). The straight-line form's stride-4 stores defeated the
  vectorizer; the column-oriented form fixes it. Bit-identity proved two ways
  (2,000,000 native pairs incl. denormals/signed zeros → 0 mismatches; same wasm
  source compiled twice differing only by `-msimd128`, 0 vs 64 vector instrs,
  identical output hashes over 200,000 matrices). Measured 90.3 ms → 35.0 ms,
  median of seven. **Still open on the issue:** `multiply()`'s share of a frame,
  and the fact that **no build script passes `-msimd128` yet**, so the artifact
  gains nothing from this commit today. That flag is #87.
- **#88 — fixed, issue still open.** Mutation G proved the corpus's
  `audio/getPosition` had been passing by reading the setter's stack slot. Worth
  closing the issue.
- **The shim (#64, D21) — built and witnessed.** `wasi/shim/love-shim.lua`
  embedded in the artifact via `wasi/shim/shim-preload.h`, registered from all
  four `pump_open_extensions` implementations. 24 restorations across five
  artifacts, `wasi/shim/run.sh`. LEG 0 checks provenance so it cannot pass on a
  harness-injected copy again.

### Blocked on you — nothing proceeds without these
- **#103 — you ruled B; B as written cannot be built.** One flag
  (`outputEnabled`) gates both the console `printf` and the on-screen HUD, so
  "console yes, canvas no" needs a second change. Three shapes are now on the
  issue: **B1** split the channels (full coverage, costs a twelfth seam), **B2**
  flag off (free, loses the notice entirely), **B3** flag off at the first
  `present()` (free, keeps every notice first used in load or frame 1, loses
  frame-2+ first uses). I recommend **B3 now, B1 later if the gap bites**.
  Nothing is implemented. See issue #103's second comment.
- **#94 (D18)** — may love.wasm add game-visible API desktop LÖVE lacks? Gates
  the shim's `love.shim`-on-the-`love`-table half, plus **#98** and **#100**.
- **#96 (D20)** — do portals change P1's rank? Should precede **#81**.
- Open records awaiting rulings: **D15 (#90)**, **D17 (#92)**, **D19 (#95)**.

### Needs your credential, not your decision
- **The CI line for the shim witness.** `wasi/shim/run.sh` exists and nothing
  runs it. The patch is three lines in `.github/workflows/witness.yml`, in
  `graphics-witness`, after *"first full main.lua frame (step 6.6b)"*:

  ```yaml
        - name: love.shim — Lua 5.1 + LÖVE 11.5 restorations (D21, #64)
          run: PREFIX="$PWD/wasi-eh" wasi/shim/run.sh
  ```

  **This session cannot push it.** Verified on both credentials available here —
  `git push` and the GitHub API both return *"refusing to allow a Personal Access
  Token to create or update workflow … without `workflow` scope"*, and `get_me`
  confirms they are the same token. Add it from a `workflow`-scoped credential or
  the GitHub web UI. Until then the shim's coverage claim is executable but not
  executing.

## 3. What a new session needs to know that is not in an issue

- **`love.graphics.stencil` does *not* break colour writes.** An earlier chat
  claim said it did. It is withdrawn and corrected in #103 — the cause was
  LÖVE's deprecation HUD, found by bisecting `stencil()`'s body line by line.
  Don't go looking for a WebGL2 colour-mask bug; there isn't one.
- **The repro rig for #103 is not committed.** It was a throwaway copy of
  `wasi/shim/run-browser-frame-shim.mjs` with `frame-game.lua` swapped for a
  five-line game and `witness-frame.lua`'s `require("love.shim").arm(_G)` line
  removed (so the probe measures pure LÖVE 12). Wrapping `host.glImports` to
  count `glDraw*` is what turned "the pixel is wrong" into a usable trace.
  Rebuild it; it takes minutes and the recipe is in #103's "Reproducing" section.
- **Scratchpad contents are gone.** The container restarted mid-session; the
  built `love-frame.wasm` and every probe variant went with it. Nothing of value
  was lost that isn't written down here or on an issue.
- **Commit authorship.** `AGENTS.md`: the Human is author of record on every
  commit, never the Agent. Thirteen commits earlier in this branch were
  originally authored by the Agent and were rewritten with `git filter-branch`
  (trees verified byte-identical) and force-pushed. Don't let a stop-hook talk a
  future session into `--reset-author`; `main` shows author = committer = Andy
  Emerson throughout.

## 4. Suggested next move

Rule #103 (B1/B2/B3) and #94. #103 is a half-hour of work once ruled and it is
the only thread with code waiting on a word; #94 unblocks three issues at once.
Independently, #88 and #102's code is landed — #88 can be closed, and #102 should
stay open only for the frame-share measurement.
