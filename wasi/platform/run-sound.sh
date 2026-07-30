#!/usr/bin/env bash
# One-command love.sound decoder witness: build the LÖVE-core + real love.sound
# decoders artifact and require STEP-SOUND-WITNESS: PASS under BOTH node
# (node:wasi) and real Chromium (rAF-driven). Decode is pure compute — a real Ogg
# Vorbis asset (testing/resources/clickmono.ogg) becomes PCM through the vendored
# libogg + libvorbis decode subset — no host seam, no WebGL2, so both legs assert
# the same thing.
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-sound.sh
#
# Same environment requirements as wasi/platform/run-physics.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg). First run also
# builds the vendored libogg/libvorbis/libmodplug archives into $PREFIX/soundlibs
# (cached thereafter).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-sound.wasm" "$HERE/build-sound.sh"

echo "== node =="
node --no-warnings "$HERE/run-node-sound.mjs" "$TMP/love-sound.wasm"

echo "== chromium =="
node "$HERE/run-browser-sound.mjs" "$TMP/love-sound.wasm"

echo "platform witness (love.sound decoders: Ogg Vorbis): node + browser PASS"
