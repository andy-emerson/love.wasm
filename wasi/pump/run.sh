#!/usr/bin/env bash
# One-command step-2 witness: build the pump artifact (lua.wasm source drop
# + pump.cpp, external EH) and require PUMP-WITNESS: PASS under BOTH node
# and real Chromium (frames on requestAnimationFrame).
#
#   PREFIX=/path/to/wasi-eh wasi/pump/run.sh
#
# PREFIX is the step-0 sysroot from wasi/toolchain/build-libcxx-eh.sh.
# Node >= 24.15 required (first 24.x to take the standardized exnref
# encoding by default — lua.wasm #27). Browser leg needs playwright-core
# resolvable from the invoking cwd and an installed chromium (or CHROMIUM
# set to an executable).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PREFIX="$PREFIX" OUT="$TMP/love-pump.wasm" "$HERE/build.sh"

echo "== node =="
node --no-warnings "$HERE/run-node.mjs" "$TMP/love-pump.wasm"

echo "== chromium =="
node "$HERE/run-browser.mjs" "$TMP/love-pump.wasm"

echo "pump witness: node + browser PASS"
