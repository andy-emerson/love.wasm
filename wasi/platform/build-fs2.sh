#!/usr/bin/env bash
# Build the step-6.2 artifact: the LÖVE core (same set as wasi/boot/build.sh)
# with the REAL love.filesystem module linked on top of the love_fs VFS seam
# (6.1), replacing the step-3 loud stub. This is the inverse of 6.1's build:
# 6.1 linked ONLY the raw seam (no LÖVE core) to isolate the file-bytes
# plumbing; 6.2 rides the real module on that same seam.
#
# Delta from wasi/boot/build.sh (the step-3 boot core), all here in the build —
# never with rm (readme.md: the tree stays upstream-shaped):
#   - REMOVE wasi/boot/filesystem-stub.cpp (its luaopen_love_filesystem and
#     luax_cangetdata now come from the real wrap_Filesystem.cpp).
#   - ADD the real filesystem module TUs: Filesystem/File/FileData + their
#     wrap_*; wrap_NativeFile (SDL-free, compiles as-is).
#   - ADD the wasm backend (fs-backend.cpp: wasi_fs::Filesystem + File on the
#     love_fs imports) and the non-SDL NativeFile stub (nativefile-stub.cpp).
#   - NOT compiled: NativeFile.cpp (SDL3) and physfs/* (real OS fd layer).
#   -I wasi/platform lets wrap_Filesystem.cpp's LOVE_WASI factory seam include
#   fs-backend.h.
#
#   PREFIX=/path/to/wasi-eh OUT=love-fs2.wasm wasi/platform/build-fs2.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
BOOT="$ROOT/wasi/boot"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-fs2.wasm}

# Single-sourced EH contract flags (wasi/toolchain/eh-flags.sh); sets $EH_FLAGS.
source "$ROOT/wasi/toolchain/eh-flags.sh"

# LÖVE common/, minus the platform files that belong to other targets (apple
# .mm, android jni) and delay.cpp (SDL_Delay). Same exclusion as boot/build.sh.
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
  $SRC/modules/filesystem/Filesystem.cpp
  $SRC/modules/filesystem/File.cpp
  $SRC/modules/filesystem/FileData.cpp
  $SRC/modules/filesystem/wrap_Filesystem.cpp
  $SRC/modules/filesystem/wrap_File.cpp
  $SRC/modules/filesystem/wrap_FileData.cpp
  $SRC/modules/filesystem/wrap_NativeFile.cpp
  $HERE/fs-backend.cpp
  $HERE/nativefile-stub.cpp
  $SRC/libraries/noise1234/noise1234.cpp
  $SRC/libraries/noise1234/simplexnoise1234.cpp
  $BOOT/pump-ext.cpp
  $BOOT/threads-wasi.cpp
"

# Plain-C third parties, compiled as C (same set as boot/build.sh).
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
  -DHAVE_CONFIG_H -I"$BOOT/config/include" \
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
echo "built $OUT (LÖVE core + real love.filesystem on love_fs seam; external EH confirmed)"
