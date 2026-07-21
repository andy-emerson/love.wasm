#!/usr/bin/env bash
# One-command love.physics (Box2D) link witness: build the LÖVE-core + real
# love.physics artifact and require STEP-PHYSICS-WITNESS: PASS under BOTH node
# (node:wasi) and real Chromium (rAF-driven). love.physics is pure compute — the
# in-tree Box2D 2.4, no host seam, no WebGL2 — so both legs assert the same thing:
# a dynamic body with an attached shape falls under gravity.
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-physics.sh
#
# Same environment requirements as wasi/platform/run-timer-system.sh (step-0
# sysroot, Node >= 24.15, playwright-core + chromium for the browser leg). Light
# build (no glslang / FreeType / graphics).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-physics.wasm" "$HERE/build-physics.sh"

echo "== node =="
node --no-warnings "$HERE/run-node-physics.mjs" "$TMP/love-physics.wasm"

echo "== chromium =="
node "$HERE/run-browser-physics.mjs" "$TMP/love-physics.wasm"

echo "platform witness (love.physics / Box2D link): node + browser PASS"
