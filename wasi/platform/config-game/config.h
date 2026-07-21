/* Module selection for the wasi build — the UNION "real game" build, the
 * capstone of the pre-step-7 "unblock a real game" work. Consumed by
 * src/common/config.h via HAVE_CONFIG_H (`#include <../config.h>` resolved
 * through -I config-game/include), the same door as every other wasi config.
 *
 * This is the first-frame union (config-frame) PLUS the three modules the
 * pre-step-7 passes linked: love.audio (webaudio backend), love.sound (lullaby
 * decoders), and love.physics (Box2D). It is the module set an actual game uses:
 * read conf/assets through love.filesystem, open the canvas, run love.load /
 * love.update / love.draw on the pump, decode + play a sound, and simulate
 * physics — all in one artifact.
 *
 * NOT enabled (and NOT linked): love.thread (step 7 Workers), love.video
 * (Theora dropped), love.joystick / love.touch / love.sensor (separately
 * witnessed; a game that needs a gamepad enables them in the joystick build).
 * The witness game's conf.lua disables each of these in t.modules so boot.lua's
 * require loop never opens a module this build did not link.
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
#define LOVE_ENABLE_AUDIO 1
#define LOVE_ENABLE_SOUND 1
#define LOVE_ENABLE_PHYSICS 1
