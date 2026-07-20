#!/usr/bin/env bash
# Build the step-6.5 artifact: the LÖVE core with the REAL love.joystick +
# love.gamepad module linked on top of the love_gamepad host seam
# (wasi/platform/joystick-backend.{h,cpp}) over the browser Gamepad API, on top of
# the 6.4 love.event/keyboard/mouse stack (the joystick events flow THROUGH
# love.event — its pump() carries the gamepad poll via a weak hook).
#
# Delta from build-input.sh (the 6.4 event/keyboard/mouse artifact), all in the
# build — never with rm (readme.md: the tree stays upstream-shaped):
#   - USE config-joystick (config-input + LOVE_ENABLE_JOYSTICK) so love.cpp
#     registers love.joystick alongside the three input modules + love.image.
#   - ADD the joystick module TUs: Joystick.cpp (base STRINGMAPs reused to name the
#     gamepad button/axis enums), wrap_Joystick.cpp, wrap_JoystickModule.cpp (its
#     ONE guarded factory now builds joystick::wasm::JoystickModule under LOVE_WASI).
#   - ADD wasi/platform/joystick-backend.cpp (the wasm:: Joystick/JoystickModule +
#     the strong wasi_poll_gamepad_events that the 6.4 pump's weak hook calls).
#   - ADD the real love.sensor module (Sensor.cpp + wrap_Sensor.cpp + the #27
#     warned-stub sensor-backend.cpp), REQUIRED by config-joystick's
#     LOVE_ENABLE_SENSOR: wrap_Joystick.cpp registers Joystick:getDevicePowerInfo/
#     :getDeviceConnectionState unconditionally but only DEFINES them under
#     LOVE_ENABLE_SENSOR (upstream bug #23), so joystick won't link with sensor off.
#   - NOT compiled: any sdl/*.cpp (native controller subsystem; SDL_sensor).
#   -I wasi/platform lets wrap_JoystickModule.cpp's LOVE_WASI factory seam include
#   joystick-backend.h.
#
# Windowless by design, like 6.4 — the joystick path is witnessed by a coroutine
# driving love.event.pump (which polls the gamepad seam) + love.event.poll +
# love.joystick readers, so this runs on BOTH node:wasi and real Chromium, no
# WebGL2 required.
#
#   PREFIX=/path/to/wasi-eh OUT=love-joystick.wasm wasi/platform/build-joystick.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
BOOT="$ROOT/wasi/boot"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-joystick.wasm}

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
  $SRC/modules/joystick/Joystick.cpp
  $SRC/modules/joystick/wrap_Joystick.cpp
  $SRC/modules/joystick/wrap_JoystickModule.cpp
  $SRC/modules/sensor/Sensor.cpp
  $SRC/modules/sensor/wrap_Sensor.cpp
  $HERE/input-backend.cpp
  $HERE/joystick-backend.cpp
  $HERE/sensor-backend.cpp
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
  -DHAVE_CONFIG_H -I"$HERE/config-joystick/include" \
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
echo "built $OUT (LÖVE core + real love.joystick/gamepad on love_gamepad seam, over 6.4 love.event; external EH confirmed)"
