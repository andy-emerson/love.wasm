/* Module selection for the wasi build — consumed by src/common/config.h
 * through its HAVE_CONFIG_H mechanism (the same door the autotools build
 * uses), so the module set is chosen without editing shared engine code.
 * Reached via `#include <../config.h>`: the build passes
 * -I wasi/audio/config/include and this file sits one level above it.
 *
 * Build-order step 5's set — step 3's plus love.audio:
 *   real:     love (registry + boot scripts), love.data, love.math,
 *             love.audio (webaudio backend — deterministic DSP in wasm,
 *             WebAudio does the mix/gain/pan/output; null backend is the
 *             bring-up fallback, exactly the openal/null shape upstream)
 *   stubbed:  love.filesystem (wasi/boot/filesystem-stub.cpp, loud seam)
 *   absent:   everything else (SDL/GL-backed, or not yet reached)
 *
 * love.sound is intentionally NOT enabled yet: the audio witness feeds raw
 * PCM through a queueable Source via love.data (a Data pointer), so the file
 * decoders (lullaby + the vendored codecs) aren't on this build's critical
 * path. They join when a file-loading witness needs them.
 *
 * No WORDS_BIGENDIAN: wasm32 is little-endian.
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_MATH 1
#define LOVE_ENABLE_FILESYSTEM 1
#define LOVE_ENABLE_AUDIO 1
