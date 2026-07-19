/**
 * Copyright (c) 2006-2026 LOVE Development Team
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 **/

// love-wasi platform seam — the love.sensor WARNED-STUB backend for wasm32-wasi
// (issue #27). It is the witnessed, concrete example of the preview-limitation
// warning mechanism (wasi/platform/preview-warn.h): every method that would need
// real motion hardware (accelerometer / gyroscope) is a NON-FATAL warned stub
// that warns-once on ATTEMPTED USE and returns a benign default. NONE throw.
//
// Two things this backend deliberately does NOT do, and why:
//   - It never touches SDL_sensor (the reference sdl/Sensor.{h,cpp}): a browser
//     has no SDL sensor subsystem, and there is no WASI/WebGL surface for raw
//     accelerometer/gyroscope data in the preview. So rather than a real bridge
//     (like the fs/window backends have), this is an honest capability-absent
//     stub — the module loads, the API is present, and using it is a quiet,
//     one-time preview note instead of an error or a faked reading.
//   - It never THROWS. The SDL backend throws love::Exception when a sensor is
//     used while not enabled; here setEnabled is a no-op so nothing is ever
//     enabled, and getData/getSensorName return safe defaults rather than
//     raising. A LÖVE game that pokes love.sensor keeps running.
//
// By keeping LOVE_ENABLE_SENSOR defined and providing this backend, love.sensor
// stays a first-class (if preview-limited) module; that also moots the upstream
// joystick/sensor coupling bug (#23), which surfaces when sensor is compiled out.
//
// This header lives out-of-tree (the src tree stays upstream-shaped);
// wrap_Sensor.cpp includes it under LOVE_WASI via -I wasi/platform and
// constructs wasm::Sensor in place of sdl::Sensor at the one guarded factory.
#ifndef LOVE_WASI_PLATFORM_SENSOR_BACKEND_H
#define LOVE_WASI_PLATFORM_SENSOR_BACKEND_H

#include "sensor/Sensor.h"

#include <vector>

namespace love
{
namespace sensor
{
namespace wasm
{

class Sensor final : public love::sensor::Sensor
{
public:

	Sensor();
	virtual ~Sensor();

	// Capability queries — benign, no warning (asking "is there a sensor?" is
	// not attempted USE of one; a game may branch on this every frame).
	bool hasSensor(SensorType type) override;   // -> false
	bool isEnabled(SensorType type) override;    // -> false (nothing can enable)

	// Attempted use — warn-once + safe default.
	void setEnabled(SensorType type, bool enabled) override;      // warn + no-op
	std::vector<float> getData(SensorType type) override;         // warn + zeros
	const char *getSensorName(SensorType type) override;          // warn + ""

	// No backend-native handles exist; benign empty list, no warning.
	std::vector<void *> getHandles() override;

}; // Sensor

} // wasm
} // sensor
} // love

#endif // LOVE_WASI_PLATFORM_SENSOR_BACKEND_H
