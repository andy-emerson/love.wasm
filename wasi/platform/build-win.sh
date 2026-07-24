#!/usr/bin/env bash
# Build the step-6.3 artifact: the LÖVE core + love.graphics (opengl backend on
# WebGL2 static imports) + love.image + love.font, PLUS the real love.window
# module linked on top of the love_win host seam — the inverse of step 4's
# windowless graphics build.
#
# Delta from wasi/graphics/build.sh (the step-4 graphics core), all here in the
# build — never with rm (readme.md: the tree stays upstream-shaped):
#   - ADD src/modules/window/wrap_Window.cpp (the real love.window Lua wrap; its
#     LOVE_WASI factory seam constructs love::window::wasm::Window).
#   - ADD wasi/platform/window-backend.cpp (the wasm backend on the love_win
#     imports + the mandatory setHighDPIAllowedImplementation symbol).
#   - Use wasi/platform/config (LOVE_ENABLE_WINDOW=1) instead of the graphics
#     config, so love.cpp registers love.window and w__setHighDPIAllowed links.
#   - Use wasi/boot/pump-ext.cpp (preload love only) instead of graphics-ext.cpp:
#     the window witness drives the REAL love.window + love.graphics Lua API, so
#     it needs no C++ witness bridges.
#   -I wasi/platform lets wrap_Window.cpp's LOVE_WASI factory seam include
#   window-backend.h.
#   NOT compiled: sdl/Window.cpp (SDL native window + GL context).
#
#   PREFIX=/path/to/wasi-eh OUT=love-win.wasm wasi/platform/build-win.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BOOT="$ROOT/wasi/boot"
GFX="$ROOT/wasi/graphics"
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-win.wasm}
GFXLIBS_DIR=${GFXLIBS_DIR:-$PREFIX/gfxlibs}

source "$ROOT/wasi/toolchain/eh-flags.sh"

# Vendored FreeType + HarfBuzz archives (real font rasterization). Built once,
# shared with the graphics build's cache.
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
  $GFX/gl-imports.cpp
  $(ls $SRC/modules/image/*.cpp)
  $(ls $SRC/modules/image/magpie/*.cpp)
  $(ls $SRC/modules/font/*.cpp)
  $(ls $SRC/modules/font/freetype/*.cpp)
  $SRC/libraries/lodepng/lodepng.cpp
  $SRC/libraries/ddsparse/ddsparse.cpp
  $SRC/libraries/noise1234/noise1234.cpp
  $SRC/libraries/noise1234/simplexnoise1234.cpp
  $SRC/modules/window/Window.cpp
  $SRC/modules/window/wrap_Window.cpp
  $HERE/window-backend.cpp
  $SRC/modules/filesystem/FileData.cpp
  $SRC/modules/thread/Channel.cpp
  $GFX/graphics-deps-stub.cpp
  $BOOT/pump-ext.cpp
  $BOOT/threads-wasi.cpp
  $BOOT/filesystem-stub.cpp
"

# glslang: LÖVE's shader reflector (same subset as the graphics build).
GLSLANG="$SRC/libraries/glslang"
GLSLANG_SOURCES="
  $(find "$GLSLANG/SPIRV" -maxdepth 1 -name '*.cpp')
  $(find "$GLSLANG/glslang/GenericCodeGen" -name '*.cpp')
  $(find "$GLSLANG/glslang/MachineIndependent" -name '*.cpp')
  $(find "$GLSLANG/glslang/ResourceLimits" -name '*.cpp')
  $GLSLANG/glslang/OSDependent/Unix/ossource.cpp
"
C_SOURCES="
  $SRC/libraries/lz4/lz4.c $SRC/libraries/lz4/lz4hc.c
  $SRC/libraries/xxHash/xxhash.c
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
  -DGLSLANG_DISABLE_FILE_OUTPUT \
  -DHAVE_CONFIG_H -I"$HERE/config/include" \
  -I"$LUA/wasi" -I"$LUA" \
  -I"$SRC" -I"$SRC/modules" -I"$SRC/libraries" -I"$ZLIB" -I"$HERE" \
  -I"$ROOT/wasi/vendor/freetype/include" -I"$ROOT/wasi/vendor/harfbuzz/src" \
  -I"$GLSLANG" -I"$GLSLANG/glslang" -I"$GLSLANG/SPIRV" \
  -mexec-model=reactor \
  -Wl,-z,stack-size=8388608 \
  -Wl,--export=malloc \
  -x c++ "$LUA/onelua.c" "$ROOT/wasi/pump/pump.cpp" $LOVE_SOURCES $GLSLANG_SOURCES \
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
echo "built $OUT (LÖVE core + love.graphics[opengl/webgl] + image + font + real love.window on love_win seam + lua.wasm + pump)"
