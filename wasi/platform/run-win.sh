#!/usr/bin/env bash
# One-command step-6.3 witness: build the LÖVE-core + real love.window +
# love.graphics artifact and require STEP6-WIN-WITNESS: PASS under real Chromium
# (rAF-driven). Chromium-only: the witness needs a real WebGL2 context (node has
# no WebGL2), the same constraint the step-4 graphics real-backend legs carry.
# The combined love_gl + love_win host serves both import modules over one real
# WebGL2 context: love.window.setMode creates the canvas + context, graphics
# binds to it, and present() reads the presented backbuffer back for the
# captureScreenshot close of build-order step 4.
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-win.sh
#
# Same environment requirements as wasi/graphics/run.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-win.wasm" "$HERE/build-win.sh"

echo "== chromium =="
node "$HERE/run-browser-win.mjs" "$TMP/love-win.wasm"

echo "platform witness (real love.window 6.3 + step-4 captureScreenshot close): browser PASS"
