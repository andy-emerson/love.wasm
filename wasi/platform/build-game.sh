#!/usr/bin/env bash
# Build the UNION "real game" artifact — the capstone of the pre-step-7 "unblock a
# real game" work. It is the first-frame union (build-frame.sh: graphics on WebGL2
# + window + filesystem + image + font + event/keyboard/mouse + timer + system +
# data + math + glslang + FreeType/HarfBuzz) PLUS the three modules the pre-step-7
# passes linked:
#   - love.audio   (webaudio backend + null fallback, from build-audio)
#   - love.sound   (lullaby decoders: Wave/Vorbis/FLAC/MP3/ModPlug, from build-sound)
#   - love.physics (in-tree Box2D, from build-physics)
# so an actual game reads its assets through love.filesystem, opens the canvas,
# decodes + plays a sound, simulates physics, and draws — all in one artifact.
#
# Deltas from build-frame.sh, all in the build — never with rm:
#   - USE config-game (frame set + AUDIO + SOUND + PHYSICS).
#   - ADD the audio module + null/webaudio backends (-DLOVE_AUDIO_NO_OPENAL
#     -DLOVE_AUDIO_WEBAUDIO), the sound module + lullaby decoders (minus Apple-only
#     CoreAudioDecoder) + Wuff (C), and the physics module + in-tree Box2D.
#   - BUILD + link the vendored libogg / libvorbis / libmodplug archives.
#   - SWAP frame-deps-stub.cpp -> union-deps-stub.cpp (audio is real now, so only
#     video + thread stay stubbed). The real love.filesystem provides the three
#     luax_*file helpers love.sound needs, so sound-fs-stub.cpp is NOT linked here.
#
# Chromium-only (needs a real WebGL2 context). Heavy build (~6 min: glslang +
# FreeType + HarfBuzz + all of graphics + audio/sound/physics/Box2D).
#
#   PREFIX=/path/to/wasi-eh OUT=love-game.wasm wasi/platform/build-game.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BOOT="$ROOT/wasi/boot"
GFX="$ROOT/wasi/graphics"
LUA="$ROOT/wasi/lua/upstream/src"
SRC="$ROOT/src"
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-love-game.wasm}
GFXLIBS_DIR=${GFXLIBS_DIR:-$PREFIX/gfxlibs}
SNDLIBS_DIR=${SNDLIBS_DIR:-$PREFIX/soundlibs}

source "$ROOT/wasi/toolchain/eh-flags.sh"

# Vendored FreeType + HarfBuzz (graphics) and libogg + libvorbis + libmodplug
# (sound), cache-built once each.
mkdir -p "$GFXLIBS_DIR" "$SNDLIBS_DIR"
[ -f "$GFXLIBS_DIR/libfreetype.a" ] || \
  PREFIX="$PREFIX" OUT="$GFXLIBS_DIR/libfreetype.a" "$ROOT/wasi/vendor/freetype/build.sh"
[ -f "$GFXLIBS_DIR/libharfbuzz.a" ] || \
  PREFIX="$PREFIX" OUT="$GFXLIBS_DIR/libharfbuzz.a" "$ROOT/wasi/vendor/harfbuzz/build.sh"
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
  $(ls $SRC/modules/audio/*.cpp)
  $(ls $SRC/modules/audio/null/*.cpp)
  $(ls $SRC/modules/audio/webaudio/*.cpp)
  $(ls $SRC/modules/sound/*.cpp)
  $LULLABY
  $(ls $SRC/modules/physics/*.cpp)
  $(ls $SRC/modules/physics/box2d/*.cpp)
  $(find $SRC/libraries/box2d -name '*.cpp')
  $HERE/preview-warn.cpp
  $HERE/union-deps-stub.cpp
  $BOOT/pump-ext.cpp
  $BOOT/threads-wasi.cpp
"

# glslang: LÖVE's shader reflector (same subset as the frame build).
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
  -DLOVE_GRAPHICS_GL_STATIC_IMPORTS \
  -DGLSLANG_DISABLE_FILE_OUTPUT \
  -DLOVE_AUDIO_NO_OPENAL -DLOVE_AUDIO_WEBAUDIO -DDR_FLAC_NO_STDIO \
  -DHAVE_CONFIG_H -I"$HERE/config-game/include" \
  -I"$LUA/wasi" -I"$LUA" \
  -I"$SRC" -I"$SRC/modules" -I"$SRC/libraries" -I"$ZLIB" -I"$HERE" \
  -I"$ROOT/wasi/vendor/freetype/include" -I"$ROOT/wasi/vendor/harfbuzz/src" \
  -I"$OGGINC" -I"$VORBISINC" -I"$MODPLUGINC" \
  -I"$GLSLANG" -I"$GLSLANG/glslang" -I"$GLSLANG/SPIRV" \
  -mexec-model=reactor \
  -Wl,-z,stack-size=8388608 \
  -Wl,--export=malloc \
  -x c++ "$LUA/onelua.c" "$ROOT/wasi/pump/pump.cpp" $LOVE_SOURCES $GLSLANG_SOURCES \
  -x c $C_SOURCES -x none \
  "$GFXLIBS_DIR/libfreetype.a" "$GFXLIBS_DIR/libharfbuzz.a" \
  "$SNDLIBS_DIR/libvorbis.a" "$SNDLIBS_DIR/libogg.a" "$SNDLIBS_DIR/libmodplug.a" \
  "$PREFIX/lib/unwind-wasm.o" "$PREFIX/lib/wasi-setjmp.o" \
  -L"$PREFIX/lib" -lc++ -lc++abi \
  -lwasi-emulated-signal -lwasi-emulated-process-clocks \
  -o "$OUT"

grep -aq "libc++abi" "$OUT" || {
  echo "FAIL: libc++abi fingerprint missing in $OUT -- external EH runtime not linked" >&2
  exit 1
}
"$ROOT/wasi/toolchain/check-eh-encoding.sh" "$OUT"
echo "built $OUT (LÖVE union real-game: graphics+window+filesystem+input+timer+system+audio+sound+physics; external EH confirmed)"
