#!/usr/bin/env bash
# One-command graphics witness (build-order step 4).
#
# Sub-step 4.1a — the raw-GL readback witness: build the command module
# (witness-gl.cpp) and run it under node's WASI with the mock love_gl host,
# proving the WebGL2 import plumbing + glReadPixels round-trip end to end,
# ahead of wiring LÖVE's opengl::Graphics (4.1b). The Chromium leg (real
# WebGL2 via OffscreenCanvas) is added alongside the node leg as 4.1a lands.
#
#   PREFIX=/path/to/wasi-eh wasi/graphics/run.sh
#
# PREFIX is the step-0 sysroot (wasi/toolchain/build-libcxx-eh.sh; default
# ./wasi-eh). Node leg needs Node >= 24.15.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source "$HERE/../toolchain/eh-flags.sh"

WASM="$TMP/witness-gl.wasm"
# Command module (main/_start). Linked like the step-0 witnesses (standardized
# wasm-EH encoding + the sysroot libc++) so the contract matches, even though
# this trivial TU raises nothing itself.
# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi $EH_FLAGS -O2 \
  -nostdinc++ -I"$PREFIX/include/c++/v1" \
  "$HERE/witness-gl.cpp" "$PREFIX/lib/unwind-wasm.o" \
  -L"$PREFIX/lib" -lc++ -lc++abi \
  -o "$WASM"

echo "### raw-GL witness (4.1a) ###"

echo "-- node leg (mock love_gl host) --"
node "$HERE/run-node.mjs" "$WASM"
echo "GL-WITNESS node: PASS"

echo "-- Chromium leg (real WebGL2 via OffscreenCanvas) --"
node "$HERE/run-browser.mjs" "$WASM"
echo "GL-WITNESS chromium: PASS"

echo
echo "raw-GL witness (4.1a): node + Chromium PASS"

# ── 4.1c: the love.graphics clear/readback witness ───────────────────────────
# The real LÖVE core + love.graphics on the opengl backend, reseamed to a real
# WebGL2 context, driven through the graphics-ext bridge to setMode + clear +
# read the pixel back. Chromium only: driving the real backend exercises ~100+
# GL entry points (shader compile, framebuffer setup), which a node mock cannot
# fake — so the fidelity leg is real WebGL2 (the node leg stays at 4.1a).
echo
echo "### love.graphics witness (4.1c) ###"
LOVE_WASM="$TMP/love-graphics.wasm"
GFXLIBS_DIR="${GFXLIBS_DIR:-$PREFIX/gfxlibs}" PREFIX="$PREFIX" OUT="$LOVE_WASM" "$HERE/build.sh" >/dev/null
echo "-- Chromium leg (real WebGL2, real backend) --"
node "$HERE/run-browser-love.mjs" "$LOVE_WASM"
echo "love.graphics witness (4.1c): Chromium PASS"
