#!/usr/bin/env bash
# One-command step-6.4 witness: build the LÖVE-core + real love.event/keyboard/
# mouse artifact and require STEP64-INPUT-WITNESS: PASS under BOTH node (node:wasi)
# and real Chromium (rAF-driven). The love_input host (a pre-seeded DOM-event
# queue) is shared by both legs, so they push the same events through the same
# import contract and assert the same translated message sequence + input state.
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-input.sh
#
# Same environment requirements as wasi/boot/run.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-input.wasm" "$HERE/build-input.sh"

echo "== node =="
node --no-warnings "$HERE/run-node-input.mjs" "$TMP/love-input.wasm"

echo "== chromium =="
node "$HERE/run-browser-input.mjs" "$TMP/love-input.wasm"

echo "platform witness (real love.event/keyboard/mouse 6.4): node + browser PASS"
