/* Module selection for the wasi build — build-order step 6.6a (timer + system
 * bring-up). Consumed by src/common/config.h via HAVE_CONFIG_H
 * (`#include <../config.h>` resolved through -I config-timer-system/include), the
 * same door as the boot/audio/graphics/window/input configs.
 *
 * Deliberately lean: the LÖVE core plus love.timer and love.system, and love.data
 * (luaopen_love requires it unconditionally). No graphics / window / filesystem
 * here — the timer + system path is witnessed windowlessly (a coroutine that
 * requires the two modules and asserts getTime advances, step() dt, getOS "Web",
 * processor count, the clipboard round-trip and the locale shape), so this
 * artifact runs on BOTH node:wasi and real Chromium, no WebGL2 needed. The union
 * frame build (6.6b) turns everything on together.
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_TIMER 1
#define LOVE_ENABLE_SYSTEM 1
