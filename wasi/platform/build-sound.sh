#!/usr/bin/env bash
# Build the love.sound decoder witness — pre-step-7 "unblock a real game" pass 2.
# love.sound's SoundData type already links (step 5); this adds the lullaby
# DECODERS so a real encoded asset becomes PCM: WAV (in-tree Wuff), Ogg Vorbis
# (vendored libogg + libvorbis decode subset), FLAC / MP3 (header-only
# dr_flac / dr_mp3, implementation emitted inside the decoder .cpp), and tracker
# music (vendored libmodplug). Pure compute — decode from a Data, no host seam —
# so it witnesses windowlessly on node:wasi AND real Chromium.
#
# The one link wrinkle: wrap_Sound.cpp references three love::filesystem helpers
# (to accept a filepath / File argument). This build has no love.filesystem and
# decodes from a Data instead, so those symbols are satisfied by the local
# sound-fs-stub.cpp (luax_cangetfile -> false routes every value to the Data
# branch; the getters throw if ever reached, which they are not).
# Delta from build-physics.sh, all in the build — never with rm:
#   - USE config-sound (LOVE/DATA/SOUND) instead of config-physics.
#   - ADD the love.sound module TUs + the lullaby decoders (minus Apple-only
#     CoreAudioDecoder) + sound-fs-stub.cpp; ADD Wuff (C) to C_SOURCES.
#   - BUILD + link the vendored libogg / libvorbis / libmodplug archives.
#   - DROP the physics module + Box2D.
#
#   PREFIX=/path/to/wasi-eh OUT=love-sound.wasm wasi/platform/build-sound.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
BOOT="$ROOT/wasi/boot"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-sound.wasm}

source "$ROOT/wasi/toolchain/eh-flags.sh"

# Vendored decode archives, cache-built once (freetype/harfbuzz pattern).
# libvorbis needs libogg's headers; libmodplug is C++ built under $EH_FLAGS.
SNDLIBS_DIR="$PREFIX/soundlibs"
mkdir -p "$SNDLIBS_DIR"
[ -f "$SNDLIBS_DIR/libogg.a" ] || \
  OUT="$SNDLIBS_DIR/libogg.a" "$ROOT/wasi/vendor/libogg/build.sh"
[ -f "$SNDLIBS_DIR/libvorbis.a" ] || \
  OUT="$SNDLIBS_DIR/libvorbis.a" "$ROOT/wasi/vendor/libvorbis/build.sh"
[ -f "$SNDLIBS_DIR/libmodplug.a" ] || \
  PREFIX="$PREFIX" OUT="$SNDLIBS_DIR/libmodplug.a" "$ROOT/wasi/vendor/libmodplug/build.sh"

COMMON=$(ls "$SRC"/common/*.cpp | grep -v -e android.cpp -e delay.cpp)
ZLIB="$ROOT/wasi/vendor/zlib"
LULLABY=$(ls "$SRC"/modules/sound/lullaby/*.cpp | grep -v CoreAudioDecoder)

LOVE_SOURCES="
  $COMMON
  $SRC/modules/love/love.cpp
  $SRC/modules/thread/threads.cpp
  $(ls $SRC/modules/data/*.cpp)
  $(ls $SRC/modules/sound/*.cpp)
  $LULLABY
  $HERE/sound-fs-stub.cpp
  $BOOT/pump-ext.cpp
  $BOOT/threads-wasi.cpp
"

C_SOURCES="
  $SRC/libraries/lz4/lz4.c
  $SRC/libraries/lz4/lz4hc.c
  $SRC/libraries/lua53/lstrlib.c
  $SRC/libraries/Wuff/wuff.c $SRC/libraries/Wuff/wuff_convert.c
  $SRC/libraries/Wuff/wuff_internal.c $SRC/libraries/Wuff/wuff_memory.c
  $ZLIB/adler32.c $ZLIB/compress.c $ZLIB/crc32.c $ZLIB/deflate.c $ZLIB/infback.c
  $ZLIB/inffast.c $ZLIB/inflate.c $ZLIB/inftrees.c $ZLIB/trees.c $ZLIB/uncompr.c $ZLIB/zutil.c
"

OGGINC="$ROOT/wasi/vendor/libogg/include"
VORBISINC="$ROOT/wasi/vendor/libvorbis/include"
MODPLUGINC="$ROOT/wasi/vendor/libmodplug/include"

# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi -O2 $EH_FLAGS \
  -fno-strict-aliasing \
  -nostdinc++ -I"$PREFIX/include/c++/v1" \
  -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS \
  -DLUA_USE_JUMPTABLE=0 -DMAKE_LIB -DLUAW_EXTERNAL_EH \
  -DDR_FLAC_NO_STDIO \
  -DHAVE_CONFIG_H -I"$HERE/config-sound/include" \
  -I"$LUA/wasi" -I"$LUA" \
  -I"$SRC" -I"$SRC/modules" -I"$SRC/libraries" -I"$ZLIB" -I"$HERE" \
  -I"$OGGINC" -I"$VORBISINC" -I"$MODPLUGINC" \
  -mexec-model=reactor \
  -Wl,-z,stack-size=8388608 \
  -x c++ "$LUA/onelua.c" "$ROOT/wasi/pump/pump.cpp" $LOVE_SOURCES \
  -x c $C_SOURCES -x none \
  "$SNDLIBS_DIR/libvorbis.a" "$SNDLIBS_DIR/libogg.a" "$SNDLIBS_DIR/libmodplug.a" \
  "$PREFIX/lib/unwind-wasm.o" -L"$PREFIX/lib" -lc++ -lc++abi \
  -lwasi-emulated-signal -lwasi-emulated-process-clocks \
  -o "$OUT"

grep -aq "libc++abi" "$OUT" || {
  echo "FAIL: libc++abi fingerprint missing in $OUT -- external EH runtime not linked" >&2
  exit 1
}
"$ROOT/wasi/toolchain/check-eh-encoding.sh" "$OUT"
echo "built $OUT (LÖVE core + real love.sound decoders: Wuff/Vorbis/FLAC/MP3/ModPlug; external EH confirmed)"
