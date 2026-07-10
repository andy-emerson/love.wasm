#!/usr/bin/env bash
# Build the step-5 artifact: the step-3 LÖVE core plus love.audio, linked with
# the lua-wasi source drop under the step-2 pump — one wasm32-wasi reactor, same
# flag contract as wasi/boot/build.sh.
#
# Module set (build-order step 5): step 3's (love, love.data, love.math,
# love.filesystem stub) plus love.audio. The audio backend is selected by
# $BACKEND: `null` (inert, the bring-up/link witness) or `webaudio` (pushes
# deterministic PCM to the host — the real seam). Both implement the same
# love::audio::Audio abstraction, exactly the openal/null shape upstream.
#
# love.sound is not compiled: the witness feeds raw PCM through a queueable
# Source via a love.data Data pointer, so the file decoders aren't on the
# critical path yet (see wasi/audio/config/config.h).
#
#   PREFIX=/path/to/wasi-eh BACKEND=null OUT=love-audio.wasm wasi/audio/build.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BOOT="$ROOT/wasi/boot"
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-audio.wasm}
BACKEND=${BACKEND:-null}

# Single-sourced EH contract flags (wasi/toolchain/eh-flags.sh); sets $EH_FLAGS.
source "$ROOT/wasi/toolchain/eh-flags.sh"

# LÖVE common/, minus the platform files that belong to other targets
# (apple .mm, android jni) and delay.cpp (SDL_Delay).
COMMON=$(ls "$SRC"/common/*.cpp | grep -v -e android.cpp -e delay.cpp)

ZLIB="$ROOT/wasi/vendor/zlib"

# The audio backend source set. Both backends are pure C++ over the platform
# audio abstraction (null: no-ops; webaudio: host imports) — no OpenAL, no SDL.
case "$BACKEND" in
  null)
    AUDIO_BACKEND="
      $SRC/modules/audio/null/Audio.cpp
      $SRC/modules/audio/null/Source.cpp
      $SRC/modules/audio/null/RecordingDevice.cpp
    " ;;
  webaudio)
    AUDIO_BACKEND="
      $SRC/modules/audio/webaudio/Audio.cpp
      $SRC/modules/audio/webaudio/Source.cpp
      $SRC/modules/audio/webaudio/RecordingDevice.cpp
    " ;;
  *) echo "unknown BACKEND=$BACKEND (want null|webaudio)" >&2; exit 2 ;;
esac

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
  $SRC/modules/audio/Audio.cpp
  $SRC/modules/audio/Source.cpp
  $SRC/modules/audio/Effect.cpp
  $SRC/modules/audio/Filter.cpp
  $SRC/modules/audio/RecordingDevice.cpp
  $SRC/modules/audio/wrap_Audio.cpp
  $SRC/modules/audio/wrap_Source.cpp
  $SRC/modules/audio/wrap_RecordingDevice.cpp
  $AUDIO_BACKEND
  $SRC/modules/sound/SoundData.cpp
  $SRC/modules/sound/Decoder.cpp
  $SRC/libraries/noise1234/noise1234.cpp
  $SRC/libraries/noise1234/simplexnoise1234.cpp
  $BOOT/pump-ext.cpp
  $BOOT/threads-wasi.cpp
  $BOOT/filesystem-stub.cpp
"

# Plain-C third parties, compiled as C.
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
"$ROOT/wasi/toolchain/check-eh-encoding.sh" "$OUT"
echo "built $OUT (LÖVE core + love.audio[$BACKEND] + lua-wasi + pump; external EH confirmed)"
