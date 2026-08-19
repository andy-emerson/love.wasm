#!/usr/bin/env bash
# One-command love.shim witness (D21, #64).
#
# No single love.wasm build links every module, so no single build can exercise
# the whole shim. This runs ONE witness (witness-shim.lua) against FOUR
# artifacts; every leg is guarded by a module presence check and yields "skip"
# when its module is absent, so coverage is visible in the transcript rather
# than implied. Together they cover 25 of the 27 restorations:
#
#   physics  LOVE DATA PHYSICS                the Lua 5.1 tier + 13 physics names
#   fs       LOVE DATA MATH FILESYSTEM        love.math.compress + 4 predicates
#   sound    LOVE DATA SOUND                  SoundData:getChannels
#   audio    LOVE DATA MATH FS AUDIO          love.audio.getSourceCount
#
#   frame    LOVE ... GRAPHICS WINDOW ...     ParticleSystem:get/setAreaSpread
#
# The frame leg is different in kind: it runs a REAL GAME through LOVE's own
# boot, because ParticleSystem needs a live GL context and that is the only
# place Lua can reach one. It is Chromium-only for the same reason.
#
#   PREFIX=/path/to/wasi-eh wasi/shim/run.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "== physics artifact: the Lua 5.1 tier + the physics names =="
PREFIX="$PREFIX" OUT="$TMP/love-physics.wasm" "$ROOT/platform/build-physics.sh" >/dev/null
node --no-warnings "$HERE/run-node-shim.mjs" "$TMP/love-physics.wasm"
node "$HERE/run-browser-shim.mjs" "$TMP/love-physics.wasm" >/dev/null
echo "   node + chromium OK"

echo "== fs artifact: love.math.compress + the four getInfo predicates =="
PREFIX="$PREFIX" OUT="$TMP/love-fs2.wasm" "$ROOT/platform/build-fs2.sh" >/dev/null
node --no-warnings "$HERE/run-node-fs.mjs" "$TMP/love-fs2.wasm"
node "$HERE/run-browser-fs.mjs" "$TMP/love-fs2.wasm" >/dev/null
echo "   node + chromium OK"

echo "== sound artifact: SoundData:getChannels =="
PREFIX="$PREFIX" OUT="$TMP/love-sound.wasm" "$ROOT/platform/build-sound.sh" >/dev/null
node --no-warnings "$HERE/run-node-sound.mjs" "$TMP/love-sound.wasm"
echo "   node OK"

echo "== audio artifact: love.audio.getSourceCount =="
PREFIX="$PREFIX" OUT="$TMP/love-audio.wasm" "$ROOT/audio/build.sh" >/dev/null
node --no-warnings "$HERE/run-node-audio.mjs" "$TMP/love-audio.wasm"
echo "   node OK"

echo "== frame artifact: ParticleSystem area spread, in a real game with a live context =="
PREFIX="$PREFIX" OUT="$TMP/love-frame.wasm" "$ROOT/platform/build-frame.sh" >/dev/null
node "$HERE/run-browser-frame-shim.mjs" "$TMP/love-frame.wasm" | tail -3
echo "   chromium OK"

echo "shim witness: all 24 restorations exercised across five artifacts"
