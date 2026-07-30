#!/usr/bin/env bash
# Beta step 2 reproducer: fetch a real third-party LÖVE game, port it to Lua 5.4,
# run it in the interactive shell, and assert it plays.
#
#   PREFIX=/path/to/wasi-eh wasi/games/run.sh
#
# The game is NOT in this repository and must not be. This script clones it at a
# pinned commit into a scratch directory, applies wasi/games/<game>.patch, and
# deletes the clone afterwards. Keep it that way: what this repository owns is
# the patch — our port — not somebody else's game.
#
# NOT WIRED INTO CI, deliberately. Every other witness depends only on this
# repository and its pinned toolchain; this one depends on a third party's
# repository staying reachable and a commit staying alive. Putting that in the
# per-push gate would mean our CI goes red when somebody else force-pushes.
# Its evidence is re-runnable on demand instead, which is the point: before this
# script existed, "a real game runs" rested on one session that no longer exists.
#
# What it proves, beyond the fixture witnesses:
#   - a game NOBODY here wrote boots from its own conf.lua at its own resolution;
#   - its own asset pipeline (167 loose png/ogg/wav/ttf files) loads;
#   - it reaches a playable state and responds to real keys;
#   - the port needed for Lua 5.4 is exactly the patch, and nothing else.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
WASM=${WASM:-$ROOT/wasi/shell/love-game.wasm}

# The pin. A moving target would make this witness meaningless.
GAME_URL=${GAME_URL:-https://github.com/challacade/legend-of-lua.git}
GAME_REF=${GAME_REF:-351f2456}
PATCH="$HERE/legend-of-lua.patch"

if [ -f "$WASM" ]; then
  echo "== reusing $WASM (delete it to force a rebuild) =="
else
  echo "== building the union artifact (~6 min) =="
  PREFIX="$PREFIX" OUT="$WASM" "$ROOT/wasi/platform/build-game.sh"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "== cloning $GAME_URL @ $GAME_REF =="
git clone --quiet "$GAME_URL" "$WORK/game"
git -C "$WORK/game" checkout --quiet "$GAME_REF"
rm -rf "$WORK/game/.git"

echo "== applying $(basename "$PATCH") (the Lua 5.1 -> 5.4 port) =="
# --check first: if the game's tree has moved under the pin, say so plainly
# rather than half-applying and failing later with a confusing Lua error.
git -C "$WORK/game" apply --check "$PATCH" \
  || { echo "FAIL: the patch does not apply to $GAME_REF — the pin or the patch is wrong" >&2; exit 1; }
git -C "$WORK/game" apply "$PATCH"

echo "== chromium (the real shell page, the real game) =="
node "$HERE/run-browser-game.mjs" "$WASM" "$WORK/game"

echo "third-party game witness (Beta step 2): Chromium PASS"
