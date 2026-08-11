#!/usr/bin/env bash
# One-command step-6.1 witness: build the love_fs-seam artifact and require
# STEP6-FS-WITNESS: PASS under BOTH node (node:wasi) and real Chromium
# (rAF-driven). The love_fs host is shared by both legs, so they compare the
# recovered bytes against the same source project.
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run.sh
#
# Same environment requirements as wasi/boot/run.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-fs.wasm" "$HERE/build.sh"

echo "== node =="
node --no-warnings "$HERE/run-node.mjs" "$TMP/love-fs.wasm"

echo "== chromium =="
node "$HERE/run-browser.mjs" "$TMP/love-fs.wasm"

echo "platform witness (love_fs seam 6.1): node + browser PASS"
