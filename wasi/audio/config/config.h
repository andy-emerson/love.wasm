/* Module selection for the wasi build — consumed by src/common/config.h
 * through its HAVE_CONFIG_H mechanism (the same door the autotools build
 * uses), so the module set is chosen without editing shared engine code.
 * Reached via `#include <../config.h>`: the build passes
 * -I wasi/audio/config/include and this file sits one level above it.
 *
 * Build-order step 5's set — step 3's plus love.audio:
 *   real:     love (registry + boot scripts), love.data, love.math,
 *             love.audio (webaudio backend — pushes deterministic PCM to the
 *             host; WebAudio does the mix/gain/pan/output and the resampling,
 *             so love-wasi owns no DSP; null is the always-linked fallback,
 *             the openal/null shape upstream)
 *   stubbed:  love.filesystem (wasi/boot/filesystem-stub.cpp, loud seam)
 *   absent:   everything else (SDL/GL-backed, or not yet reached)
 *
 * The full love.sound MODULE (decoders/lullaby) is NOT enabled. The SoundData
 * *type* IS compiled and registered (sound/wrap_SoundData.cpp +
 * wasi/audio/audio-ext.cpp) so love.audio's RecordingDevice:getData() returns a
 * usable SoundData; playback also accepts raw PCM through a queueable Source via
 * a love.data pointer. The file decoders (the vendored codecs) aren't on this
 * build's critical path yet; they join when a file-loading witness needs them.
 *
 * No WORDS_BIGENDIAN: wasm32 is little-endian.
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_MATH 1
#define LOVE_ENABLE_FILESYSTEM 1
#define LOVE_ENABLE_AUDIO 1
