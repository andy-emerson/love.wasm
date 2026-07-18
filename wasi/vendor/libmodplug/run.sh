#!/usr/bin/env bash
# One-command witness for vendored libmodplug: build the archive, synthesize a
# minimal audible MOD, link a command module that loads + decodes it via the
# libmodplug C API, and require MODPLUG-WITNESS: PASS under node:wasi, real
# Chromium, and wasmtime.
#
#   PREFIX=/path/to/wasi-eh wasi/vendor/libmodplug/run.sh
#
# PREFIX is the step-0 sysroot (libmodplug is C++ → needs libc++/libc++abi).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/wasi/toolchain/eh-flags.sh"
source "$ROOT/wasi/witness/legs.sh"

PREFIX="$PREFIX" OUT="$TMP/libmodplug.a" "$HERE/build.sh"

# Synthesize the test module and embed it (witness reads mod_bytes[] / mod_len).
node "$HERE/make-witness-mod.mjs" > "$TMP/witness.mod"
node "$ROOT/wasi/witness/embed.mjs" "$TMP/witness.mod" mod_bytes mod_len > "$TMP/mod_data.h"

clang-20 --target=wasm32-wasi -O2 -I"$HERE/include" -I"$TMP" \
  -c "$HERE/witness.c" -o "$TMP/witness.o"
# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi $EH_FLAGS -Wno-unused-command-line-argument \
  "$TMP/witness.o" "$TMP/libmodplug.a" \
  "$PREFIX/lib/unwind-wasm.o" -L"$PREFIX/lib" -lc++ -lc++abi \
  -o "$TMP/mp-witness.wasm"

witness_legs "$TMP/mp-witness.wasm" "MODPLUG-WITNESS: PASS" check-eh
echo "libmodplug witness: decoded tracker music in wasm on node + browser$(witness_wasmtime_suffix)"
