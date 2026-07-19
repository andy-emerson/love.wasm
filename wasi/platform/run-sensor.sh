#!/usr/bin/env bash
# One-command issue-#27 witness: build the LÖVE-core + real love.sensor
# warned-stub artifact and require STEP27-WARN-WITNESS: PASS under BOTH node
# (node:wasi) and real Chromium (rAF-driven), AND that the one-time
# "[love-wasi preview]" warning appears exactly once across two uses of the
# warned feature (getData) — asserted from the host tap by each leg.
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-sensor.sh
#
# Same environment requirements as wasi/boot/run.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-sensor.wasm" "$HERE/build-sensor.sh"

echo "== node =="
node --no-warnings "$HERE/run-node-sensor.mjs" "$TMP/love-sensor.wasm"

echo "== chromium =="
node "$HERE/run-browser-sensor.mjs" "$TMP/love-sensor.wasm"

echo "platform witness (love.sensor warned stub + preview-warn one-time, #27): node + browser PASS"
