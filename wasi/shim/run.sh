#!/usr/bin/env bash
# One-command love.shim witness (D21, #64): build the LÖVE core + love.data +
# real love.physics artifact and require SHIM-WITNESS: PASS under BOTH node and
# real Chromium.
#
# It reuses build-physics.sh rather than adding a build: the shim is pure Lua,
# so it needs no compilation — what it needs is an engine to shim, and the
# physics artifact is the smallest one carrying the spring joints, which are the
# only part of the 11.5 -> 12 gap that changed units rather than names.
#
#   PREFIX=/path/to/wasi-eh wasi/shim/run.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-physics.wasm" "$ROOT/platform/build-physics.sh"

echo "== node =="
node --no-warnings "$HERE/run-node-shim.mjs" "$TMP/love-physics.wasm"

echo "== chromium =="
node "$HERE/run-browser-shim.mjs" "$TMP/love-physics.wasm"

echo "shim witness (love.shim, Lua 5.1 + LÖVE 11.5 tiers): node + browser PASS"
