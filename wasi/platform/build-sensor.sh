#!/usr/bin/env bash
# Build the issue-#27 artifact: the LÖVE-core boot set (same as wasi/boot/build.sh)
# PLUS the REAL love.sensor module, linked on top of the out-of-tree warned-stub
# backend (wasi/platform/sensor-backend.cpp) and the preview-limitation warning
# mechanism (wasi/platform/preview-warn.cpp). This is the witnessed example of
# issue #27's one-time, non-fatal "[love-wasi preview]" warning: love.sensor
# loads, its API is present, and USING a sensor emits one host-routed preview
# note and returns a safe default rather than throwing or faking a reading.
#
# Delta from wasi/boot/build.sh (the step-3 boot core), all here in the build —
# never with rm (readme.md: the tree stays upstream-shaped):
#   - ADD the real love.sensor module TUs: Sensor.cpp (base Module + SensorType
#     stringmap) and wrap_Sensor.cpp (the Lua wrap + luaopen_love_sensor; its
#     LOVE_WASI factory seam constructs love::sensor::wasm::Sensor).
#   - ADD the wasm warned-stub backend (sensor-backend.cpp) and the preview
#     warning mechanism (preview-warn.cpp).
#   - Use wasi/platform/config-sensor (LOVE_ENABLE_SENSOR=1) instead of the boot
#     config, so love.cpp registers love.sensor and luaopen_love_sensor links.
#   -I wasi/platform lets wrap_Sensor.cpp's LOVE_WASI factory seam include
#   sensor-backend.h.
#   NOT compiled: sdl/Sensor.cpp (SDL_sensor native backend).
#
#   PREFIX=/path/to/wasi-eh OUT=love-sensor.wasm wasi/platform/build-sensor.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
BOOT="$ROOT/wasi/boot"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-sensor.wasm}

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
  $SRC/modules/sensor/Sensor.cpp
  $SRC/modules/sensor/wrap_Sensor.cpp
  $HERE/sensor-backend.cpp
  $HERE/preview-warn.cpp
  $SRC/libraries/noise1234/noise1234.cpp
  $SRC/libraries/noise1234/simplexnoise1234.cpp
  $BOOT/pump-ext.cpp
  $BOOT/threads-wasi.cpp
  $BOOT/filesystem-stub.cpp
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
  -DHAVE_CONFIG_H -I"$HERE/config-sensor/include" \
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
echo "built $OUT (LÖVE core + real love.sensor warned-stub backend + preview-warn mechanism; external EH confirmed)"
