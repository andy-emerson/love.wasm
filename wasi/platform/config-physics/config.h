/* Module selection for the wasi build — the love.physics (Box2D) link witness,
 * pre-step-7 "unblock a real game" work. Consumed by src/common/config.h via
 * HAVE_CONFIG_H (`#include <../config.h>` resolved through
 * -I config-physics/include), the same door as the boot/audio/graphics/window/
 * input/timer-system configs.
 *
 * Deliberately lean: the LÖVE core plus love.physics, and love.data (luaopen_love
 * requires it unconditionally). No graphics / window / filesystem / math here —
 * love.physics is pure compute (the in-tree Box2D 2.4, single-threaded, no host
 * seam), witnessed windowlessly by a coroutine that requires the module, builds a
 * world + a dynamic body with an attached shape, steps it, and asserts the body
 * falls under gravity — so this artifact runs on BOTH node:wasi and real Chromium,
 * no WebGL2 needed. The union "real game" build turns everything on together.
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_PHYSICS 1
