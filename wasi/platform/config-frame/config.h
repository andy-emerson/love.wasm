/* Module selection for the wasi build — build-order step 6.6b: the FIRST FULL
 * main.lua FRAME (conf -> canvas -> load -> draw -> present). Consumed by
 * src/common/config.h via HAVE_CONFIG_H (`#include <../config.h>` resolved
 * through -I config-frame/include), the same door as every other wasi config.
 *
 * This is the UNION of the sub-step configs: the real love.filesystem (6.2),
 * love.window (6.3), love.graphics/opengl-on-WebGL2 (step 4) + love.image +
 * love.font, love.event/keyboard/mouse (6.4), love.timer + love.system (6.6a),
 * love.data + love.math (graphics deps). It is exactly the set LÖVE's real
 * boot.lua needs to read conf.lua, open the canvas at the conf dimensions, run
 * love.load, and run love.update/love.draw on the pump.
 *
 * NOT enabled (and NOT linked): love.thread (module — step 7 Workers),
 * love.joystick, love.touch, love.sound, love.sensor, love.audio, love.video,
 * love.physics. conf.lua for the witness disables each of these in t.modules so
 * boot.lua's require loop never tries to open a module this build did not link.
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_MATH 1
#define LOVE_ENABLE_FILESYSTEM 1
#define LOVE_ENABLE_GRAPHICS 1
#define LOVE_ENABLE_IMAGE 1
#define LOVE_ENABLE_FONT 1
#define LOVE_ENABLE_WINDOW 1
#define LOVE_ENABLE_EVENT 1
#define LOVE_ENABLE_KEYBOARD 1
#define LOVE_ENABLE_MOUSE 1
#define LOVE_ENABLE_TIMER 1
#define LOVE_ENABLE_SYSTEM 1
