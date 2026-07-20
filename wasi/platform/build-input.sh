#!/usr/bin/env bash
# Build the step-6.4 artifact: the LÖVE core with the REAL love.event,
# love.keyboard and love.mouse modules linked on top of the love_input host seam
# (wasi/platform/input-backend.{h,cpp}), replacing the three SDL backends. This
# is the first host->guest PUSH seam: DOM events the host queues are drained by
# love.event::wasm::Event::pump() and translated into love::event::Message
# objects the unchanged Lua dispatch fires as love.keypressed / love.mousepressed
# / ... , while love.keyboard / love.mouse read the shared snapshot pump keeps.
#
# Windowless by design (no graphics/window/font): the input path is witnessed by
# a coroutine driving pump + poll + the state readers, so this runs on BOTH
# node:wasi and real Chromium — no WebGL2 context required (unlike the 6.3 window
# build). Delta from wasi/platform/build-fs2.sh (the non-graphics core), all in
# the build — never with rm (readme.md: the tree stays upstream-shaped):
#   - USE config-input (LOVE/DATA/IMAGE/EVENT/KEYBOARD/MOUSE) instead of the boot
#     config, so love.cpp registers the three input modules + love.image.
#   - ADD the real event/keyboard/mouse module TUs + their wrap_*; love.mouse's
#     Cursor is image-backed and loads from files, so the image module (+ magpie
#     + lodepng) and the real love.filesystem (the 6.2 module on the love_fs
#     seam: fs-backend.cpp + nativefile-stub.cpp) link too.
#   - ADD wasi/platform/input-backend.cpp (the three wasm:: backends + shared
#     input state on the love_input imports).
#   - NOT compiled: any sdl/*.cpp (native OS event loop + cursor).
#   -I wasi/platform lets the wrap_*.cpp LOVE_WASI factory seams include
#   input-backend.h.
#
#   PREFIX=/path/to/wasi-eh OUT=love-input.wasm wasi/platform/build-input.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
BOOT="$ROOT/wasi/boot"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-input.wasm}

source "$ROOT/wasi/toolchain/eh-flags.sh"

COMMON=$(ls "$SRC"/common/*.cpp | grep -v -e android.cpp -e delay.cpp)
ZLIB="$ROOT/wasi/vendor/zlib"

LOVE_SOURCES="
  $COMMON
  $SRC/modules/love/love.cpp
  $SRC/modules/thread/threads.cpp
  $SRC/modules/thread/Channel.cpp
  $(ls $SRC/modules/data/*.cpp)
  $(ls $SRC/modules/image/*.cpp)
  $(ls $SRC/modules/image/magpie/*.cpp)
  $SRC/libraries/lodepng/lodepng.cpp
  $SRC/libraries/ddsparse/ddsparse.cpp
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
  $HERE/preview-warn.cpp
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
  -DHAVE_CONFIG_H -I"$HERE/config-input/include" \
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
echo "built $OUT (LÖVE core + real love.event/keyboard/mouse on love_input seam; external EH confirmed)"
