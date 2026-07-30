#!/usr/bin/env bash
# One-command witness for the interactive shell (Beta step 1). Serves the real
# shell page, drives it in real Chromium, and requires SHELL-WITNESS: PASS.
#
# What it proves that no earlier witness can:
#   - a real project from disk runs (its own conf.lua sizes the canvas, and
#     love.filesystem reads an asset from a subdirectory of it);
#   - REAL DOM key events reach love.keyboard and the game responds — and stops
#     on keyup. The 6.4 witness proves the love_input seam with a baked queue and
#     cannot prove the DOM half;
#   - a module edited ON DISK reaches the RUNNING game, and main.lua is reported
#     as restart-only rather than silently ignored (#47 / D4).
#
# Chromium-only: it needs a real WebGL2 context, exactly like the frame, window
# and union-game witnesses. There is NO node leg (expected).
#
#   PREFIX=/path/to/wasi-eh wasi/shell/run.sh
#
# The union artifact is reused if it is already at wasi/shell/love-game.wasm and
# rebuilt otherwise (heavy, ~6 min). Keeping it is deliberate: a rebuild per
# iteration would make the shell undevelopable.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-$HERE/love-game.wasm}

if [ -f "$OUT" ]; then
  echo "== reusing $OUT (delete it to force a rebuild) =="
else
  echo "== building the union artifact (~6 min) =="
  PREFIX="$PREFIX" OUT="$OUT" "$HERE/../platform/build-game.sh"
fi

echo "== chromium (the real shell page: project + live input + live edit) =="
node "$HERE/run-browser.mjs" "$OUT" "$HERE/fixture"

echo "shell witness (interactive shell, Beta step 1): Chromium PASS"
