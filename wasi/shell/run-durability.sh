#!/usr/bin/env bash
# One-command witness for save durability (#55). Serves the real shell page,
# drives it in real Chromium, and requires DURABILITY-WITNESS: PASS.
#
# What it proves that no other witness can: a file written through
# love.filesystem SURVIVES A PAGE RELOAD — write, page.reload(), read the same
# bytes back — because the browser save store is OPFS-backed (D2). And it is
# demonstrated able to fail: a second leg runs the identical sequence with
# ?opfs=0 (the in-memory reference store) and requires the read to come back
# empty.
#
# Chromium-only: the shell needs a real WebGL2 context, exactly like run.sh.
#
#   PREFIX=/path/to/wasi-eh wasi/shell/run-durability.sh
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

echo "== chromium (write -> page reload -> read back, then the OPFS-disabled leg) =="
node "$HERE/run-durability.mjs" "$OUT" "$HERE/fixture-durability"

echo "durability witness (OPFS save store, #55): Chromium PASS"
