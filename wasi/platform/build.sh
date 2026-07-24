#!/usr/bin/env bash
# Build the step-6.1 artifact: the lua.wasm source drop + the step-2 pump +
# the love_fs seam bridge (fs-ext.cpp) in one wasm32-wasi reactor. NO LÖVE core
# — 6.1 isolates the host<->wasm file-bytes plumbing (the raw seam), the way
# graphics/build-raw isolated the WebGL2 plumbing before the reused backend.
# Same flag contract as wasi/pump/build.sh (standardized wasm-EH, external EH).
#
#   PREFIX=/path/to/wasi-eh OUT=love-fs.wasm wasi/platform/build.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LUA="$ROOT/wasi/lua/upstream/src"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-fs.wasm}

# Single-sourced EH contract flags (wasi/toolchain/eh-flags.sh); sets $EH_FLAGS.
source "$ROOT/wasi/toolchain/eh-flags.sh"

# The love_fs imports (fs_size/fs_read) are declared with import_module
# attributes in fs-ext.cpp, so lld emits them as wasm imports — no
# --allow-undefined needed (same as gl-imports.cpp).
clang++-20 --target=wasm32-wasi -O2 $EH_FLAGS \
  -fno-strict-aliasing \
  -nostdinc++ -I"$PREFIX/include/c++/v1" \
  -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS \
  -DLUA_USE_JUMPTABLE=0 -DMAKE_LIB -DLUAW_EXTERNAL_EH \
  -I"$LUA/wasi" -I"$LUA" \
  -mexec-model=reactor \
  -Wl,-z,stack-size=8388608 \
  -x c++ "$LUA/onelua.c" "$ROOT/wasi/pump/pump.cpp" "$HERE/fs-ext.cpp" -x none \
  "$PREFIX/lib/unwind-wasm.o" -L"$PREFIX/lib" -lc++ -lc++abi \
  -lwasi-emulated-signal -lwasi-emulated-process-clocks \
  -o "$OUT"

# Fingerprint gate + EH-encoding gate (same as pump/boot): external EH runtime
# must really be linked, in the standardized encoding.
grep -aq "libc++abi" "$OUT" || {
  echo "FAIL: libc++abi fingerprint missing in $OUT -- external EH runtime not linked" >&2
  exit 1
}
"$ROOT/wasi/toolchain/check-eh-encoding.sh" "$OUT"
echo "built $OUT (pump + love_fs seam; external EH confirmed)"
