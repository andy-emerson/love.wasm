#!/usr/bin/env bash
# Build the step-4 (4.1c) artifact: the LÖVE core + love.graphics on the opengl
# backend reseamed to WebGL2 static imports, linked with lua-wasi under the pump
# — one wasm32-wasi reactor, same flag contract as wasi/audio/build.sh.
#
# Module set: step 3's core (love, data, math, filesystem stub) plus graphics,
# image, and font — the modules graphics needs to construct. The opengl backend
# is compiled verbatim; the GL loader is reseamed by LOVE_GRAPHICS_GL_STATIC_
# IMPORTS (wasi/graphics/gl-imports.cpp supplies the entry points as host
# imports). love.window is NOT built (step 6): the graphics-ext bridge plays its
# one structural role (setMode) for the witness. Font rasterization is real:
# vendored FreeType + HarfBuzz (built here if not provided via $GFXLIBS_DIR).
#
#   PREFIX=/path/to/wasi-eh OUT=love-graphics.wasm wasi/graphics/build.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BOOT="$ROOT/wasi/boot"
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-graphics.wasm}
GFXLIBS_DIR=${GFXLIBS_DIR:-$PREFIX/gfxlibs}

source "$ROOT/wasi/toolchain/eh-flags.sh"

# Vendored FreeType + HarfBuzz archives (real font rasterization). Built once.
mkdir -p "$GFXLIBS_DIR"
[ -f "$GFXLIBS_DIR/libfreetype.a" ] || \
  PREFIX="$PREFIX" OUT="$GFXLIBS_DIR/libfreetype.a" "$ROOT/wasi/vendor/freetype/build.sh"
[ -f "$GFXLIBS_DIR/libharfbuzz.a" ] || \
  PREFIX="$PREFIX" OUT="$GFXLIBS_DIR/libharfbuzz.a" "$ROOT/wasi/vendor/harfbuzz/build.sh"

COMMON=$(ls "$SRC"/common/*.cpp | grep -v -e android.cpp -e delay.cpp)
ZLIB="$ROOT/wasi/vendor/zlib"

LOVE_SOURCES="
  $COMMON
  $SRC/modules/love/love.cpp
  $SRC/modules/thread/threads.cpp
  $(ls $SRC/modules/data/*.cpp)
  $(ls $SRC/modules/math/*.cpp)
  $(ls $SRC/modules/graphics/*.cpp)
  $(ls $SRC/modules/graphics/opengl/*.cpp)
  $SRC/libraries/glad/glad.cpp
  $HERE/gl-imports.cpp
  $(ls $SRC/modules/image/*.cpp)
  $(ls $SRC/modules/image/magpie/*.cpp)
  $(ls $SRC/modules/font/*.cpp)
  $(ls $SRC/modules/font/freetype/*.cpp)
  $SRC/libraries/lodepng/lodepng.cpp
  $SRC/libraries/ddsparse/ddsparse.cpp
  $SRC/libraries/noise1234/noise1234.cpp
  $SRC/libraries/noise1234/simplexnoise1234.cpp
  $HERE/graphics-ext.cpp
  $BOOT/threads-wasi.cpp
  $BOOT/filesystem-stub.cpp
"
C_SOURCES="
  $SRC/libraries/lz4/lz4.c $SRC/libraries/lz4/lz4hc.c
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
  -DLOVE_GRAPHICS_GL_STATIC_IMPORTS \
  -DHAVE_CONFIG_H -I"$HERE/config/include" \
  -I"$LUA/wasi" -I"$LUA" \
  -I"$SRC" -I"$SRC/modules" -I"$SRC/libraries" -I"$ZLIB" \
  -I"$ROOT/wasi/vendor/freetype/include" -I"$ROOT/wasi/vendor/harfbuzz/src" \
  -mexec-model=reactor \
  -Wl,-z,stack-size=8388608 \
  -Wl,--export=malloc -Wl,--export=free \
  -x c++ "$LUA/onelua.c" "$ROOT/wasi/pump/pump.cpp" $LOVE_SOURCES \
  -x c $C_SOURCES -x none \
  "$GFXLIBS_DIR/libfreetype.a" "$GFXLIBS_DIR/libharfbuzz.a" \
  "$PREFIX/lib/unwind-wasm.o" "$PREFIX/lib/wasi-setjmp.o" \
  -L"$PREFIX/lib" -lc++ -lc++abi \
  -lwasi-emulated-signal -lwasi-emulated-process-clocks \
  -o "$OUT"

grep -aq "libc++abi" "$OUT" || {
  echo "FAIL: libc++abi fingerprint missing in $OUT -- external EH runtime not linked" >&2
  exit 1
}
"$ROOT/wasi/toolchain/check-eh-encoding.sh" "$OUT"
echo "built $OUT (LÖVE core + love.graphics[opengl/webgl] + image + font + lua-wasi + pump)"
