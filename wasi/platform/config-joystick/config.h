/* Module selection for the wasi build — build-order step 6.5 (joystick/gamepad
 * bring-up). Consumed by src/common/config.h via HAVE_CONFIG_H
 * (`#include <../config.h>` resolved through -I config-joystick/include), the
 * same door as the boot/audio/graphics/window/input configs.
 *
 * Superset of config-input (6.4): the LÖVE core + the three input modules (the
 * joystick events flow THROUGH love.event — the witness pumps love.event and
 * reads love.joystick), PLUS love.joystick itself. love.keyboard/love.mouse stay
 * enabled because the event module's registration/headers pull them in exactly
 * as in 6.4; love.filesystem/love.image are needed by love.mouse's file-backed
 * Cursor, as in 6.4.
 *
 * LOVE_ENABLE_SENSOR is set — the real love.sensor module (the warned-stub
 * backend from issue #27, wasi/platform/sensor-backend.cpp) rides along. This is
 * REQUIRED, not optional: wrap_Joystick.cpp's Joystick:getDevicePowerInfo and
 * :getDeviceConnectionState are DEFINED under #ifdef LOVE_ENABLE_SENSOR but
 * REGISTERED in the function table UNCONDITIONALLY (upstream bug #23) — so with
 * sensor compiled out the joystick wrap fails to link. Enabling love.sensor moots
 * #23 by config (exactly as DESIGN.md notes for #27) and gives the joystick
 * sensor wrappers their Sensor::getConstant. The wasm Joystick's own sensor
 * methods stay warn-once stubs. love.sensor links Sensor.cpp + wrap_Sensor.cpp +
 * sensor-backend.cpp (built in build-joystick.sh).
 *
 * No graphics / window / font here — the joystick path is witnessed windowlessly
 * (a coroutine driving love.event.pump — which polls the gamepad seam via the
 * weak hook — then reading love.joystick), so this artifact runs on BOTH
 * node:wasi and real Chromium, no WebGL2 needed.
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_FILESYSTEM 1
#define LOVE_ENABLE_IMAGE 1
#define LOVE_ENABLE_EVENT 1
#define LOVE_ENABLE_KEYBOARD 1
#define LOVE_ENABLE_MOUSE 1
#define LOVE_ENABLE_JOYSTICK 1
#define LOVE_ENABLE_SENSOR 1
