#!/usr/bin/env bash
# One-command witness for function-body hotswap (#56, D4=B). Serves the real
# shell page, drives it in real Chromium, and requires HOTSWAP-WITNESS: PASS.
#
# What it proves that no other witness can, in the D4 record's own order: an
# edit to love.update saved ON DISK takes effect at the function's next calls;
# file-scope state survives the swap and stays SHARED (draw keeps seeing what
# update mutates — the upvalue join aliases, it does not copy); a syntax-broken
# save fails on the USER's code, named file and line, with the lua_State and
# the session intact (a good save afterwards hotswaps into the SAME run); and
# love.load runs once per session — edits change the future, not the past.
#
# Chromium-only: the shell needs a real WebGL2 context, exactly like run.sh.
# Not yet in witness.yml: the Agent's token lacks workflow scope, so the CI
# step is the Human's to wire, as with the corpus step.
#
#   PREFIX=/path/to/wasi-eh wasi/shell/run-hotswap.sh
#
# The union artifact is reused if it is already at wasi/shell/love-game.wasm and
# rebuilt otherwise (heavy, ~6 min), same as run.sh.
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

echo "== chromium (edit love.update on disk -> next frames run it, state intact) =="
node "$HERE/run-hotswap.mjs" "$OUT" "$HERE/fixture-hotswap"

echo "hotswap witness (function-body hotswap, #56): Chromium PASS"
