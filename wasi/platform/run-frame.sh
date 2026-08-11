#!/usr/bin/env bash
# One-command step-6.6b witness — THE MILESTONE: build the union first-frame
# artifact and require STEP66-FRAME-WITNESS: PASS in real Chromium. LÖVE's real
# boot.lua runs the canned game (fs-host's conf.lua + main.lua) end to end:
# conf -> canvas (love.window.setMode on WebGL2) -> love.load (unique marker to
# the host tap) -> love.draw fills the canvas RED -> present; the driver reads the
# centre pixel back through the WebGL2 context and asserts it is RED.
#
# Chromium-only: it needs a real WebGL2 context (node has no WebGL2), exactly like
# the 6.3 window witness and the step-4 graphics witnesses. There is NO node leg
# for 6.6b (expected).
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-frame.sh
#
# Heavy build (~5-6 min: glslang + FreeType + HarfBuzz + all of graphics). Same
# environment requirements as wasi/platform/run-win.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-frame.wasm" "$HERE/build-frame.sh"

echo "== chromium (first full main.lua frame) =="
node "$HERE/run-browser-frame.mjs" "$TMP/love-frame.wasm"

echo "platform witness (first full main.lua frame 6.6b): Chromium PASS"
