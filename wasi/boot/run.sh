#!/usr/bin/env bash
# One-command step-3 witness: build the LÖVE-core boot artifact and require
# STEP3-WITNESS: PASS under BOTH node and real Chromium (rAF-driven).
#
#   PREFIX=/path/to/wasi-eh wasi/boot/run.sh
#
# Same environment requirements as wasi/pump/run.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-boot.wasm" "$HERE/build.sh"

echo "== node =="
node --no-warnings "$HERE/run-node.mjs" "$TMP/love-boot.wasm"

echo "== chromium =="
node "$HERE/run-browser.mjs" "$TMP/love-boot.wasm"

echo "boot witness: node + browser PASS"
