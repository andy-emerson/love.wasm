/* Module selection for the wasi build (issue #27: love.sensor warned-stub +
 * preview-limitation warning) — consumed by src/common/config.h via
 * HAVE_CONFIG_H, the same door as the boot/graphics/window configs.
 *
 * This is the step-3 boot core's module set (LOVE + DATA + MATH +
 * FILESYSTEM-stub — the known-good set the boot witness already proves loads and
 * boots) PLUS love.sensor: with LOVE_ENABLE_SENSOR defined, love.cpp registers
 * love.sensor -> luaopen_love_sensor, whose LOVE_WASI factory seam constructs
 * love::sensor::wasm::Sensor (wasi/platform/sensor-backend.cpp) in place of
 * sdl::Sensor. Keeping SENSOR enabled also moots the upstream joystick/sensor
 * coupling bug (#23), which surfaces when the module is compiled out.
 *
 * No WORDS_BIGENDIAN: wasm32 is little-endian.
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_MATH 1
#define LOVE_ENABLE_FILESYSTEM 1
#define LOVE_ENABLE_SENSOR 1
