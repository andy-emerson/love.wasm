#!/usr/bin/env bash
# Build the step-3 artifact: the LÖVE core (common/ + module registry +
# love.math as the first real engine module + the embedded boot scripts)
# linked with the lua-wasi source drop under the step-2 pump — one
# wasm32-wasi reactor, same flag contract as wasi/pump/build.sh.
#
# Module set (build-order step 3: "graphics/audio/window/thread stubbed"):
#   real:     love (registry + boot scripts), love.math (pure C++)
#   stubbed:  love.filesystem (loud seam error, wasi/boot/filesystem-stub.cpp)
#             love::thread primitives (single-threaded exact no-ops,
#             wasi/boot/threads-wasi.cpp; the love.thread *module* is absent)
#   absent:   everything SDL/GL/AL-backed — requiring them says so
#
# Exclusions happen here in the build, never with rm (readme.md: the tree
# stays upstream-shaped; the wasi build compiles the subset).
#
#   PREFIX=/path/to/wasi-eh OUT=love-boot.wasm wasi/boot/build.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-boot.wasm}

EH_FLAGS="-fwasm-exceptions -mllvm -wasm-use-legacy-eh=false"

# LÖVE common/, minus the platform files that belong to other targets
# (apple .mm, android jni) and delay.cpp (SDL_Delay — nothing in this set
# sleeps; a browser tab must never block anyway).
COMMON=$(ls "$SRC"/common/*.cpp | grep -v -e android.cpp -e delay.cpp)

ZLIB="$ROOT/wasi/vendor/zlib"

LOVE_SOURCES="
  $COMMON
  $SRC/modules/love/love.cpp
  $SRC/modules/thread/threads.cpp
  $SRC/modules/data/ByteData.cpp
  $SRC/modules/data/CompressedData.cpp
  $SRC/modules/data/Compressor.cpp
  $SRC/modules/data/DataModule.cpp
  $SRC/modules/data/DataStream.cpp
  $SRC/modules/data/DataView.cpp
  $SRC/modules/data/HashFunction.cpp
  $SRC/modules/data/wrap_ByteData.cpp
  $SRC/modules/data/wrap_CompressedData.cpp
  $SRC/modules/data/wrap_Data.cpp
  $SRC/modules/data/wrap_DataModule.cpp
  $SRC/modules/data/wrap_DataView.cpp
  $SRC/modules/math/MathModule.cpp
  $SRC/modules/math/BezierCurve.cpp
  $SRC/modules/math/RandomGenerator.cpp
  $SRC/modules/math/Transform.cpp
  $SRC/modules/math/wrap_Math.cpp
  $SRC/modules/math/wrap_BezierCurve.cpp
  $SRC/modules/math/wrap_RandomGenerator.cpp
  $SRC/modules/math/wrap_Transform.cpp
  $SRC/libraries/noise1234/noise1234.cpp
  $SRC/libraries/noise1234/simplexnoise1234.cpp
  $HERE/pump-ext.cpp
  $HERE/threads-wasi.cpp
  $HERE/filesystem-stub.cpp
"

# Plain-C third parties, compiled as C (their headers carry the extern-C
# guards; upstream builds them as C too).
C_SOURCES="
  $SRC/libraries/lz4/lz4.c
  $SRC/libraries/lz4/lz4hc.c
  $SRC/libraries/lua53/lstrlib.c
  $ZLIB/adler32.c
  $ZLIB/compress.c
  $ZLIB/crc32.c
  $ZLIB/deflate.c
  $ZLIB/infback.c
  $ZLIB/inffast.c
  $ZLIB/inflate.c
  $ZLIB/inftrees.c
  $ZLIB/trees.c
  $ZLIB/uncompr.c
  $ZLIB/zutil.c
"

# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi -O2 $EH_FLAGS \
  -fno-strict-aliasing \
  -nostdinc++ -I"$PREFIX/include/c++/v1" \
  -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS \
  -DLUA_USE_JUMPTABLE=0 -DMAKE_LIB -DLUAW_EXTERNAL_EH \
  -DHAVE_CONFIG_H -I"$HERE/config/include" \
  -I"$LUA/wasi" -I"$LUA" \
  -I"$SRC" -I"$SRC/modules" -I"$SRC/libraries" -I"$ZLIB" \
  -mexec-model=reactor \
  -Wl,-z,stack-size=8388608 \
  -x c++ "$LUA/onelua.c" "$ROOT/wasi/pump/pump.cpp" $LOVE_SOURCES \
  -x c $C_SOURCES -x none \
  "$PREFIX/lib/unwind-wasm.o" -L"$PREFIX/lib" -lc++ -lc++abi \
  -lwasi-emulated-signal -lwasi-emulated-process-clocks \
  -o "$OUT"

grep -aq "libc++abi" "$OUT" || {
  echo "FAIL: libc++abi fingerprint missing in $OUT -- external EH runtime not linked" >&2
  exit 1
}
echo "built $OUT (LÖVE core + lua-wasi + pump; external EH confirmed)"
