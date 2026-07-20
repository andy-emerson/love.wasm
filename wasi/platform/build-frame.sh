#!/usr/bin/env bash
# Build the step-6.6b artifact — THE MILESTONE: the LÖVE core with EVERY module
# the first full main.lua frame needs, so LÖVE's real boot.lua runs end to end:
# love.conf honored -> canvas sized/titled -> love.load -> love.update/love.draw
# on the pump -> present. It is the UNION of the sub-step builds:
#   - love.graphics (opengl on WebGL2 static imports) + image + font + glslang +
#     FreeType/HarfBuzz  (from build-win.sh, the 6.3 graphics+window build)
#   - real love.window on the love_win seam   (window-backend.cpp, from build-win)
#   - real love.filesystem on the love_fs seam (fs-backend.cpp + the filesystem
#     module TUs + nativefile-stub, from build-fs2.sh) — REPLACING the boot
#     filesystem-stub.cpp that build-win used
#   - real love.event/keyboard/mouse on the love_input seam (input-backend.cpp +
#     the three module TUs, from build-input.sh)
#   - real love.timer (Timer.cpp + delay-wasi.cpp) + love.system (system-backend
#     .cpp), from build-timer-system.sh
#   - love.data + love.math (graphics deps)
#
# frame-deps-stub.cpp REPLACES graphics-deps-stub.cpp: the union build compiles
# the real filesystem + timer, so only the genuinely-absent audio/video/thread
# module symbols love.graphics links against are stubbed (using the graphics stub
# would duplicate File::type/luax_getdata/Timer::getTime — now real). love.joystick
# is deliberately NOT linked (the event module needs only the joystick HEADER,
# which is compile-time); input-backend.cpp's wasi_poll_gamepad_events weak hook
# stays null, so pump() skips it.
#
# Chromium-only (needs a real WebGL2 context; node has no WebGL2) — the same
# constraint the 6.3 window witness and the step-4 graphics witnesses carry.
#
#   PREFIX=/path/to/wasi-eh OUT=love-frame.wasm wasi/platform/build-frame.sh
# Heavy build (~5-6 min: glslang + FreeType + HarfBuzz + all of graphics).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BOOT="$ROOT/wasi/boot"
GFX="$ROOT/wasi/graphics"
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-frame.wasm}
GFXLIBS_DIR=${GFXLIBS_DIR:-$PREFIX/gfxlibs}

source "$ROOT/wasi/toolchain/eh-flags.sh"

# Vendored FreeType + HarfBuzz archives (shared with the graphics/window cache).
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
  $SRC/modules/thread/Channel.cpp
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
  $SRC/modules/filesystem/Filesystem.cpp
  $SRC/modules/filesystem/File.cpp
  $SRC/modules/filesystem/FileData.cpp
  $SRC/modules/filesystem/wrap_Filesystem.cpp
  $SRC/modules/filesystem/wrap_File.cpp
  $SRC/modules/filesystem/wrap_FileData.cpp
  $SRC/modules/filesystem/wrap_NativeFile.cpp
  $HERE/fs-backend.cpp
  $HERE/nativefile-stub.cpp
  $SRC/modules/event/Event.cpp
  $SRC/modules/event/wrap_Event.cpp
  $SRC/modules/keyboard/Keyboard.cpp
  $SRC/modules/keyboard/wrap_Keyboard.cpp
  $SRC/modules/mouse/Cursor.cpp
  $SRC/modules/mouse/wrap_Cursor.cpp
  $SRC/modules/mouse/wrap_Mouse.cpp
  $HERE/input-backend.cpp
  $SRC/modules/timer/Timer.cpp
  $SRC/modules/timer/wrap_Timer.cpp
  $HERE/delay-wasi.cpp
  $SRC/modules/system/System.cpp
  $SRC/modules/system/wrap_System.cpp
  $HERE/system-backend.cpp
  $HERE/preview-warn.cpp
  $HERE/frame-deps-stub.cpp
  $BOOT/pump-ext.cpp
  $BOOT/threads-wasi.cpp
"

# glslang: LÖVE's shader reflector (same subset as the graphics/window build).
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
  -DHAVE_CONFIG_H -I"$HERE/config-frame/include" \
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
echo "built $OUT (LÖVE first-frame union: filesystem+window+graphics+image+font+event+keyboard+mouse+timer+system; external EH confirmed)"
