#!/usr/bin/env bash
# One-command UNION "real game" witness — the pre-step-7 capstone: build the union
# artifact (graphics + window + filesystem + input + timer + system + AUDIO +
# SOUND + PHYSICS) and require UNION-GAME-WITNESS: PASS in real Chromium. LÖVE's
# real boot.lua runs an actual game end to end: conf -> canvas -> love.load (decode
# + play a real Ogg via love.sound/love.audio over love.filesystem; build a physics
# world with a falling body) -> love.update steps physics -> love.draw draws the
# body red -> present. The driver asserts the load/sound/physics markers reached
# the host tap AND a red pixel (the physics-positioned body) is on the canvas.
#
# Chromium-only: it needs a real WebGL2 context (node has no WebGL2), exactly like
# the frame and window witnesses. There is NO node leg (expected).
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-game.sh
#
# Heavy build (~6 min: glslang + FreeType + HarfBuzz + all of graphics +
# audio/sound/physics/Box2D). First run also builds the vendored sound archives.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-game.wasm" "$HERE/build-game.sh"

echo "== chromium (union real game: conf -> canvas -> load -> sound + physics -> draw) =="
node "$HERE/run-browser-game.mjs" "$TMP/love-game.wasm"

echo "platform witness (union real game): Chromium PASS"
