#!/usr/bin/env bash
# The D9 draw-call sweep, run against real WebGL2 in Chromium.
#
#   PREFIX=/path/to/wasi-eh wasi/bench/run.sh
#
# A PROBE, NOT A WITNESS — deliberately not wired into witness.yml. Every runner
# in wasi/witness, wasi/pump and wasi/graphics renders a verdict CI can enforce;
# this one produces a measurement, and a measurement belongs to the machine that
# produced it. A GitHub runner has no GPU, so a gate here would gate on
# SwiftShader and mean nothing.
#
# THE NUMBER THAT MATTERS IS A RATIO. Run the same fixture under desktop LÖVE on
# the same machine:
#
#   love wasi/bench/project            # desktop leg — prints its table
#   PREFIX=... wasi/bench/run.sh       # browser leg — prints its table
#
# and compare the unbatched columns. That ratio is browser submission overhead;
# absolute milliseconds from two different machines compare nothing. See
# wasi/bench/project/main.lua for what the two modes isolate and why.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
WASM=${WASM:-$ROOT/wasi/shell/love-game.wasm}

# The same union artifact the shell, corpus and game witnesses run.
if [ -f "$WASM" ]; then
  echo "== reusing $WASM (delete it to force a rebuild) =="
else
  echo "== building the union artifact (~6 min) =="
  PREFIX="$PREFIX" OUT="$WASM" "$ROOT/wasi/platform/build-game.sh"
fi

echo "== chromium (real WebGL2) =="
node "$HERE/run-browser-bench.mjs" "$WASM"
