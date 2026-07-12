#!/usr/bin/env bash
# One-command graphics witness (build-order step 4). Three witnesses:
#
#   4.1a — raw-GL readback: a command module (witness-gl.cpp) proving the
#          WebGL2 import plumbing + glReadPixels round-trip, on node (a mock
#          love_gl host) and real Chromium WebGL2.
#   4.1c — love.graphics: the real LÖVE core + love.graphics on the opengl
#          backend, reseamed to a real WebGL2 context, clearing a framebuffer
#          and recovering the pixel through the graphics-ext bridge. Chromium
#          only — driving the real backend hits ~100+ GL entry points a node
#          mock cannot fake, so the node leg stays at 4.1a.
#   4.2  — first primitive draw: the same real backend now draws a filled
#          rectangle (shader compile + vertex stream + glDrawArrays) and reads
#          the drawn pixel back. Same wasm as 4.1c, Chromium only.
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

# ── 4.2: the first primitive draw ────────────────────────────────────────────
# The same real backend, now drawing geometry instead of only clearing: a filled
# rectangle over a black clear, read back to confirm the colour landed where it
# was rasterised. This is the first time a shader (glslang -> GLSL -> real WebGL2
# compile) and vertex streaming (a real VBO via glBufferSubData — WebGL2 forbids
# the client-side arrays and buffer mapping the desktop paths would pick) both
# run. Same wasm as 4.1c; only the witness lua differs. Chromium only.
echo
echo "### draw witness (4.2) ###"
echo "-- Chromium leg (real WebGL2, real backend) --"
node "$HERE/run-browser-love.mjs" "$LOVE_WASM" "$HERE/witness-draw.lua"
echo "draw witness (4.2): Chromium PASS"

# ── 4.3: the rest of the 2D primitive set ────────────────────────────────────
# The same real backend drawing every remaining primitive category in one frame:
# a high-vertex fan (filled circle), an arbitrary filled triangle, points
# (gl_PointSize), and the distinct STROKE path (line-mode rectangle outline +
# polyline). Each is read back at a covered pixel; the outline's hollow centre
# and a background pixel confirm the clear colour survives where nothing drew.
# Same wasm as 4.1c/4.2; only the witness lua differs. Chromium only.
echo
echo "### primitive-set witness (4.3) ###"
echo "-- Chromium leg (real WebGL2, real backend) --"
node "$HERE/run-browser-love.mjs" "$LOVE_WASM" "$HERE/witness-prims.lua"
echo "primitive-set witness (4.3): Chromium PASS"

# ── 4.4: the first texture ───────────────────────────────────────────────────
# The first real pixel data through the backend: a 2x2 four-texel RGBA8 image
# uploaded to a GL texture (glTexStorage2D/glTexSubImage) and drawn scaled with
# NEAREST filtering, each texel's block read back to recover its colour and
# position — proving texture upload, sampler binding, the textured shader, and
# correct UV mapping. Same wasm as 4.1c/4.2/4.3; only the witness lua differs.
echo
echo "### texture witness (4.4) ###"
echo "-- Chromium leg (real WebGL2, real backend) --"
node "$HERE/run-browser-love.mjs" "$LOVE_WASM" "$HERE/witness-texture.lua"
echo "texture witness (4.4): Chromium PASS"
