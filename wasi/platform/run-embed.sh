#!/usr/bin/env bash
# One-command step-6.7 witness: build the embedding-contract artifact (LÖVE core
# + real love.filesystem read+write + the pump reload/invalidate primitive) and
# require STEP67-EMBED-WITNESS: PASS under BOTH node (node:wasi) and real
# Chromium (rAF-driven). The love_fs host — a read-only project map plus a
# separate writable save namespace — is shared by both legs, so they exercise
# the same write path and reload sequence through the same import contract.
#
#   PREFIX=/path/to/wasi-eh wasi/platform/run-embed.sh
#
# Same environment requirements as wasi/boot/run.sh (step-0 sysroot,
# Node >= 24.15, playwright-core + chromium for the browser leg).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-embed.wasm" "$HERE/build-embed.sh"

echo "== node =="
node --no-warnings "$HERE/run-node-embed.mjs" "$TMP/love-embed.wasm"

echo "== chromium =="
node "$HERE/run-browser-embed.mjs" "$TMP/love-embed.wasm"

echo "platform witness (embedding contract 6.7): node + browser PASS"
