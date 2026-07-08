#!/usr/bin/env bash
# One-command step-0 witness: compile eh-typed-catch.cpp against the wasm-EH
# sysroot and require EH-WITNESS: PASS under BOTH node:wasi and real Chromium.
#
#   PREFIX=/path/to/wasi-eh wasi/witness/run.sh
#
# PREFIX is the install prefix produced by wasi/toolchain/build-libcxx-eh.sh
# (default ./wasi-eh). Browser leg needs playwright-core resolvable from the
# invoking cwd and either an installed playwright chromium or CHROMIUM set to
# a chromium executable.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source "$HERE/../toolchain/eh-flags.sh"

# Standardized exnref encoding, matching the sysroot build (one artifact,
# one encoding — clang-20's bare -fwasm-exceptions default is legacy).
# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi $EH_FLAGS -O2 \
  -nostdinc++ -I"$PREFIX/include/c++/v1" \
  "$HERE/eh-typed-catch.cpp" "$PREFIX/lib/unwind-wasm.o" \
  -L"$PREFIX/lib" -lc++ -lc++abi \
  -o "$TMP/eh-witness.wasm"

"$HERE/../toolchain/check-eh-encoding.sh" "$TMP/eh-witness.wasm"

echo "== node:wasi =="
node --no-warnings "$HERE/run-node.mjs" "$TMP/eh-witness.wasm"

echo "== chromium =="
node "$HERE/run-browser.mjs" "$TMP/eh-witness.wasm"

echo "EH witness: node + browser PASS"
