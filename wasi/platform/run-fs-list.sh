#!/usr/bin/env bash
# One-command filesystem directory-enumeration witness: build the LÖVE-core +
# real love.filesystem artifact (the same build-fs2.sh — getDirectoryItems now
# rides the new fs_list seam in fs-backend.cpp) and require STEP-FSLIST-WITNESS:
# PASS under BOTH node (node:wasi) and real Chromium (rAF-driven). The love_fs
# host (fs-host.mjs, now fulfilling fs_list) is shared by both legs.
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-fs-list.sh
#
# Same environment requirements as wasi/platform/run-fs2.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-fs2.wasm" "$HERE/build-fs2.sh"

echo "== node =="
node --no-warnings "$HERE/run-node-fs-list.mjs" "$TMP/love-fs2.wasm"

echo "== chromium =="
node "$HERE/run-browser-fs-list.mjs" "$TMP/love-fs2.wasm"

echo "platform witness (love.filesystem directory enumeration / fs_list): node + browser PASS"
