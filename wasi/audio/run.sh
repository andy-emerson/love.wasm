#!/usr/bin/env bash
# One-command step-5 sub-step 1a witness: build the love.audio artifact
# (null backend — the inert bring-up backend) and require
# STEP5-AUDIO-WITNESS: PASS under BOTH node and real Chromium (rAF-driven).
#
#   PREFIX=/path/to/wasi-eh wasi/audio/run.sh
#
# Same environment requirements as wasi/boot/run.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg). BACKEND
# defaults to null; the webaudio backend has its own PCM-readback witness.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
BACKEND=${BACKEND:-null}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" BACKEND="$BACKEND" OUT="$TMP/love-audio.wasm" "$HERE/build.sh"

echo "== node =="
node --no-warnings "$HERE/run-node.mjs" "$TMP/love-audio.wasm"

echo "== chromium =="
node "$HERE/run-browser.mjs" "$TMP/love-audio.wasm"

echo "audio witness ($BACKEND): node + browser PASS"
