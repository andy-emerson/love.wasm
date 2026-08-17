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
 * love.joystick + love.sensor are linked here too. Both have real, witnessed
 * wasm backends (joystick-backend.cpp over the Gamepad API; the #27 warned-stub
 * sensor-backend.cpp). love.joystick used not to compile with LOVE_ENABLE_SENSOR
 * off at all — #23, two non-sensor device wrappers trapped inside the sensor
 * guard — which is fixed in wrap_Joystick.cpp, so the two modules are now
 * independent and this pairing is a choice rather than a constraint. Stubbing a
 * module whose backend already exists and is
 * CI-enforced would hide a working feature: a game's `if love.joystick then`
 * would take the absent path and silently lose gamepad support.
 *
 * love.touch is linked too, over the browser's TouchEvent API
 * (wasi/platform/touch-backend.cpp), on the same love_input record as the mouse
 * and keyboard.
 *
 * NOT enabled (and NOT linked): love.thread (step 7 Workers), love.video
 * (Theora dropped). LOVE enables all twenty modules by default and
 * boot.lua hard-errors on a missing one, so the boot wrapper
 * (wasi/platform/witness-frame.lua) preloads the absent ones and reports them
 * when a game USES them.
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
#define LOVE_ENABLE_JOYSTICK 1
#define LOVE_ENABLE_SENSOR 1
#define LOVE_ENABLE_TOUCH 1
