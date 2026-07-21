#!/usr/bin/env bash
# One-command step-6.6a witness: build the LÖVE-core + real love.timer/love.system
# artifact and require STEP66A-TIMER-SYSTEM-WITNESS: PASS under BOTH node
# (node:wasi) and real Chromium (rAF-driven). The love_system host (baked
# deterministic hardwareConcurrency / clipboard / locales) is shared by both legs,
# so they assert the same values; timer's getTime rides each host's real
# monotonic clock (node:wasi's clock_time_get and V8's in the page).
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-timer-system.sh
#
# Same environment requirements as wasi/boot/run.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-timer-system.wasm" "$HERE/build-timer-system.sh"

echo "== node =="
node --no-warnings "$HERE/run-node-timer-system.mjs" "$TMP/love-timer-system.wasm"

echo "== chromium =="
node "$HERE/run-browser-timer-system.mjs" "$TMP/love-timer-system.wasm"

echo "platform witness (real love.timer/love.system 6.6a): node + browser PASS"
