# CLAUDE.md

The working agreement for this repository is in [`AGENTS.md`](AGENTS.md). Read it
and follow it — it is the operative contract for how work is planned, done,
reviewed, and integrated here.

One repo-specific mapping, because this is a fork with an upstream mirror
(see readme.md, "Upstream relationship"):

- Where `AGENTS.md` says **`main`** (the trunk: reviewed, documented,
  known-good), read **`wasi`** — the default branch of this repo.
- This repo's actual `main` is a **pristine mirror of upstream love2d/love** —
  never commit to it; it only fast-forwards when a new upstream base is
  adopted. Working branches are cut from `wasi` and integrate back to `wasi`.
