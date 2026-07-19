#!/usr/bin/env bash
# One-command step-6.2 witness: build the LÖVE-core + real love.filesystem
# artifact and require STEP6-FS2-WITNESS: PASS under BOTH node (node:wasi) and
# real Chromium (rAF-driven). The love_fs host is shared by both legs, so they
# recover the same source project through the same import contract.
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-fs2.sh
#
# Same environment requirements as wasi/boot/run.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-fs2.wasm" "$HERE/build-fs2.sh"

echo "== node =="
node --no-warnings "$HERE/run-node-fs2.mjs" "$TMP/love-fs2.wasm"

echo "== chromium =="
node "$HERE/run-browser-fs2.mjs" "$TMP/love-fs2.wasm"

echo "platform witness (real love.filesystem 6.2): node + browser PASS"
