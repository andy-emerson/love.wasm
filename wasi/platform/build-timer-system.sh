#!/usr/bin/env bash
# Build the step-6.6a artifact: the LÖVE core with the REAL love.timer and
# love.system modules linked. love.timer is a concrete class (no backend split):
# Timer.cpp routes through clock_gettime(CLOCK_MONOTONIC)/gettimeofday under the
# LOVE_WASI arm of its POSIX guard (wasi-libc provides both, the WASI host
# fulfils clock_time_get), and love::sleep is an honest browser no-op
# (wasi/platform/delay-wasi.cpp — the main thread must not block; the host paces
# frames via requestAnimationFrame). love.system is backend-split: the wasm
# backend (wasi/platform/system-backend.cpp) rides the love_system host seam for
# the genuine browser capabilities (processor count, clipboard, openURL, locales)
# and reports honest defaults for the rest (memory 0, power unknown); getOS()
# returns "Web" via the guarded seam in System.cpp.
#
# Windowless by design (no graphics/window/filesystem): the timer + system path
# is witnessed by a coroutine (require the two modules; assert getTime advances,
# step() dt >= 0, getOS "Web", processor count, clipboard round-trip, locale
# shape), so this runs on BOTH node:wasi and real Chromium — no WebGL2 needed.
# Delta from wasi/platform/build-input.sh, all in the build — never with rm:
#   - USE config-timer-system (LOVE/DATA/TIMER/SYSTEM) instead of config-input.
#   - ADD Timer.cpp + wrap_Timer.cpp + delay-wasi.cpp.
#   - ADD System.cpp + wrap_System.cpp + system-backend.cpp.
#   - NOT compiled: any sdl/*.cpp, common/delay.cpp (SDL_Delay), the input /
#     filesystem / image TUs (this artifact needs none of them).
#   -I wasi/platform lets wrap_System.cpp's LOVE_WASI factory seam include
#   system-backend.h.
#
#   PREFIX=/path/to/wasi-eh OUT=love-timer-system.wasm wasi/platform/build-timer-system.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
BOOT="$ROOT/wasi/boot"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-timer-system.wasm}

source "$ROOT/wasi/toolchain/eh-flags.sh"

COMMON=$(ls "$SRC"/common/*.cpp | grep -v -e android.cpp -e delay.cpp)
ZLIB="$ROOT/wasi/vendor/zlib"

LOVE_SOURCES="
  $COMMON
  $SRC/modules/love/love.cpp
  $SRC/modules/thread/threads.cpp
  $(ls $SRC/modules/data/*.cpp)
  $SRC/modules/timer/Timer.cpp
  $SRC/modules/timer/wrap_Timer.cpp
  $HERE/delay-wasi.cpp
  $SRC/modules/system/System.cpp
  $SRC/modules/system/wrap_System.cpp
  $HERE/system-backend.cpp
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
  -DHAVE_CONFIG_H -I"$HERE/config-timer-system/include" \
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
echo "built $OUT (LÖVE core + real love.timer + real love.system on love_system seam; external EH confirmed)"
