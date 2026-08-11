#!/usr/bin/env bash
# Build the step-2 pump artifact: the lua.wasm source drop + pump.cpp in one
# wasm32-wasi reactor, under the flag contract of lua.wasm doc/embedding.md
# at the pinned commit (wasi/lua/upstream/PIN):
#   clang-20 · onelua.c as C++ · -fwasm-exceptions with the STANDARDIZED
#   exnref encoding · -fno-strict-aliasing · -DMAKE_LIB (no reactor glue) ·
#   -DLUAW_EXTERNAL_EH with the step-0 wasm-EH libc++/libc++abi owning
#   exception dispatch.
#
#   PREFIX=/path/to/wasi-eh OUT=love-pump.wasm wasi/pump/build.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
LUA="$HERE/../lua/upstream/src"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-pump.wasm}

# One EH configuration, everywhere — single-sourced so the compile sites can't
# drift (clang-20's bare -fwasm-exceptions default is the LEGACY encoding; one
# artifact must not mix encodings). Sets $EH_FLAGS.
source "$HERE/../toolchain/eh-flags.sh"

# -D_WASI_EMULATED_*/-lwasi-emulated-*: os/time bits of the stdlib.
# -DLUA_USE_JUMPTABLE=0: part of lua.wasm's witnessed wasm recipe.
# -mexec-model=reactor: the pump is called, it does not run; exports are
# declared per-function in pump.cpp (export_name attributes).
clang++-20 --target=wasm32-wasi -O2 $EH_FLAGS \
  -fno-strict-aliasing \
  -nostdinc++ -I"$PREFIX/include/c++/v1" \
  -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS \
  -DLUA_USE_JUMPTABLE=0 -DMAKE_LIB -DLUAW_EXTERNAL_EH \
  -I"$LUA/wasi" -I"$LUA" \
  -mexec-model=reactor \
  -Wl,-z,stack-size=8388608 \
  -x c++ "$LUA/onelua.c" "$HERE/pump.cpp" -x none \
  "$PREFIX/lib/unwind-wasm.o" -L"$PREFIX/lib" -lc++ -lc++abi \
  -lwasi-emulated-signal -lwasi-emulated-process-clocks \
  -o "$OUT"

# Fingerprint gate (lua.wasm's convention): LUAW_EXTERNAL_EH suppressed the
# micro-shim, so the REAL libc++abi must actually be in the artifact.
grep -aq "libc++abi" "$OUT" || {
  echo "FAIL: libc++abi fingerprint missing in $OUT -- external EH runtime not linked" >&2
  exit 1
}
"$HERE/../toolchain/check-eh-encoding.sh" "$OUT"
echo "built $OUT (external EH confirmed: libc++abi fingerprint present)"
