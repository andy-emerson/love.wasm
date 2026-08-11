#!/usr/bin/env bash
# Beta step 3: LÖVE's own conformance corpus (testing/), run against this build
# and compared test by test against the expected-fail list.
#
#   PREFIX=/path/to/wasi-eh wasi/corpus/run.sh
#   CORPUS_BOOTSTRAP=1 wasi/corpus/run.sh    # print the failures, render no verdict
#
# What this proves that no per-seam witness can: the seams are right *together*,
# measured by somebody else's tests. Each earlier witness asserts the thing it
# built; this one asserts LÖVE's own idea of what love.* means, across 355 tests
# nobody here wrote.
#
# UNLIKE wasi/games/run.sh, this IS wired into CI. The corpus is upstream's and
# lives in this repository, so it depends on nothing outside the tree — the
# reason the third-party game witness stays on-demand does not apply here.
#
# The comparison is the witness, and it fails three ways: a test expected to
# pass that failed (a regression), a test on the expected-fail list that PASSED
# (the list is stale — a good problem, still a failure, because an unearned
# divergence is a lie), and a test that failed while classified nowhere (nobody
# decided). expected.txt carries the reason for every entry.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
WASM=${WASM:-$ROOT/wasi/shell/love-game.wasm}

# The union artifact is the same one the shell and the game witness run: LÖVE
# core + all nineteen linked modules. Reused if present, because a rebuild per
# iteration (~6 min) would make this undevelopable.
if [ -f "$WASM" ]; then
  echo "== reusing $WASM (delete it to force a rebuild) =="
else
  echo "== building the union artifact (~6 min) =="
  PREFIX="$PREFIX" OUT="$WASM" "$ROOT/wasi/platform/build-game.sh"
fi

echo "== chromium (the real corpus, real WebGL2) =="
node "$HERE/run-browser-corpus.mjs" "$WASM" "$HERE/expected.txt"

echo "corpus witness (Beta step 3): Chromium PASS"
