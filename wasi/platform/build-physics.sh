#!/usr/bin/env bash
# Build the love.physics (Box2D) link witness — pre-step-7 "unblock a real game"
# work. love.physics is a pure-compute module: the in-tree Box2D 2.4 (single-
# threaded; no OS calls are reached on wasm — b2Timer falls into its no-op #else
# arm) plus the love.physics wrappers, which throw love::Exception through the
# shared -fwasm-exceptions contract. NO host seam and NO engine-source edits:
# module selection is entirely in config-physics/config.h through the
# HAVE_CONFIG_H door, so shared code stays byte-untouched.
#
# Windowless by design (no graphics/window/filesystem): a coroutine requires
# love.physics, builds a world + a dynamic body with an attached shape (12.0
# merged fixtures into shapes) and steps it, asserting the body falls under
# gravity — so this runs on BOTH node:wasi and real Chromium, no WebGL2 needed.
# Delta from build-timer-system.sh, all in the build — never with rm:
#   - USE config-physics (LOVE/DATA/PHYSICS) instead of config-timer-system.
#   - ADD the love.physics module TUs (modules/physics + modules/physics/box2d)
#     and the in-tree Box2D library (libraries/box2d, 45 TUs).
#   - DROP timer/system/delay-wasi/system-backend (this artifact needs none).
#
#   PREFIX=/path/to/wasi-eh OUT=love-physics.wasm wasi/platform/build-physics.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
BOOT="$ROOT/wasi/boot"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-physics.wasm}

source "$ROOT/wasi/toolchain/eh-flags.sh"

COMMON=$(ls "$SRC"/common/*.cpp | grep -v -e android.cpp -e delay.cpp)
ZLIB="$ROOT/wasi/vendor/zlib"

LOVE_SOURCES="
  $COMMON
  $SRC/modules/love/love.cpp
  $SRC/modules/thread/threads.cpp
  $(ls $SRC/modules/data/*.cpp)
  $(ls $SRC/modules/physics/*.cpp)
  $(ls $SRC/modules/physics/box2d/*.cpp)
  $(find $SRC/libraries/box2d -name '*.cpp')
  $BOOT/pump-ext.cpp
  $BOOT/threads-wasi.cpp
"

C_SOURCES="
  $SRC/libraries/lz4/lz4.c
  $SRC/libraries/lz4/lz4hc.c
  $SRC/libraries/lua53/lstrlib.c
  $ZLIB/adler32.c $ZLIB/compress.c $ZLIB/crc32.c $ZLIB/deflate.c $ZLIB/infback.c
  $ZLIB/inffast.c $ZLIB/inflate.c $ZLIB/inftrees.c $ZLIB/trees.c $ZLIB/uncompr.c $ZLIB/zutil.c
"

# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi -O2 $EH_FLAGS \
  -fno-strict-aliasing \
  -nostdinc++ -I"$PREFIX/include/c++/v1" \
  -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS \
  -DLUA_USE_JUMPTABLE=0 -DMAKE_LIB -DLUAW_EXTERNAL_EH \
  -DHAVE_CONFIG_H -I"$HERE/config-physics/include" \
  -I"$LUA/wasi" -I"$LUA" \
  -I"$SRC" -I"$SRC/modules" -I"$SRC/libraries" -I"$ZLIB" -I"$HERE" \
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
"$ROOT/wasi/toolchain/check-eh-encoding.sh" "$OUT"
echo "built $OUT (LÖVE core + real love.physics on in-tree Box2D; external EH confirmed)"
