#!/usr/bin/env bash
# One-command step-6.5 witness: build the LÖVE-core + real love.joystick/gamepad
# artifact and require STEP65-JOYSTICK-WITNESS: PASS under BOTH node (node:wasi)
# and real Chromium (rAF-driven). The love_gamepad host (a scripted sequence of
# Gamepad-API frames) is shared by both legs, so they advance the same frames
# through the same poll-and-diff import contract and assert the same synthesized
# joystick/gamepad events + love.joystick state.
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-joystick.sh
#
# Same environment requirements as wasi/platform/run-input.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-joystick.wasm" "$HERE/build-joystick.sh"

echo "== node =="
node --no-warnings "$HERE/run-node-joystick.mjs" "$TMP/love-joystick.wasm"

echo "== chromium =="
node "$HERE/run-browser-joystick.mjs" "$TMP/love-joystick.wasm"

echo "platform witness (real love.joystick/gamepad 6.5): node + browser PASS"
