/* Module selection for the wasi build — the love.sound decoder witness,
 * pre-step-7 "unblock a real game" pass 2. Consumed by src/common/config.h via
 * HAVE_CONFIG_H (`#include <../config.h>` resolved through -I config-sound/include),
 * the same door as the boot/audio/graphics/window/input/timer-system configs.
 *
 * Deliberately lean: the LÖVE core plus love.sound, and love.data (luaopen_love
 * requires it unconditionally, and love.sound decodes from a Data — love.data's
 * ByteData — through data::DataStream). No love.audio and no love.filesystem: the
 * decoders are pure compute (encoded bytes -> PCM), witnessed windowlessly by a
 * coroutine that decodes a real Ogg Vorbis asset and inspects the SoundData, so
 * this artifact runs on BOTH node:wasi and real Chromium, no host seam needed. The
 * three love::filesystem helpers wrap_Sound references are satisfied by the local
 * sound-fs-stub.cpp (the Data path is taken instead). love.audio's playback seam
 * joins in the union "real game" build.
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_SOUND 1
