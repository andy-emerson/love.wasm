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

// love.sensor warned-stub backend for wasm32-wasi (issue #27). See
// sensor-backend.h for the design; each method below is either a benign
// capability query (no warning) or an attempted-use warned stub (warn-once via
// preview_warn_once + safe default, never throws).

#include "sensor-backend.h"
#include "preview-warn.h"

namespace love
{
namespace sensor
{
namespace wasm
{

Sensor::Sensor()
	: love::sensor::Sensor("love.sensor.wasm")
{
}

Sensor::~Sensor()
{
}

bool Sensor::hasSensor(SensorType /*type*/)
{
	// A browser preview exposes no accelerometer/gyroscope. Honest "no",
	// reported the same way the SDL backend reports an absent device — a plain
	// capability answer, so no preview warning (a game polls this to decide
	// whether to even try, and must be able to do so silently).
	return false;
}

bool Sensor::isEnabled(SensorType /*type*/)
{
	// Nothing can be enabled (setEnabled is a no-op), so this is always false.
	// Also a capability query — no warning.
	return false;
}

void Sensor::setEnabled(SensorType /*type*/, bool /*enabled*/)
{
	// Attempted USE: enabling a sensor that does not exist. Warn once, then do
	// nothing — the SDL backend would open a device here; there is none, and we
	// do not fake one. Non-fatal (the SDL path can throw on open failure; we
	// never do).
	preview_warn_once("sensor.setEnabled",
		"love.sensor.setEnabled: motion sensors are not available in the "
		"browser preview; the call is a no-op.");
}

std::vector<float> Sensor::getData(SensorType /*type*/)
{
	// Attempted USE: reading sensor data. Warn once, return a safe default. The
	// SDL backend returns three floats (x, y, z) and throws if the sensor is not
	// enabled; here we return three zeros and never throw, so a game reading
	// love.sensor.getData gets benign, well-shaped data instead of an error.
	preview_warn_once("sensor.getData",
		"love.sensor.getData: motion sensors are not available in the "
		"browser preview; returning zeros.");
	return std::vector<float>(3, 0.0f);
}

const char *Sensor::getSensorName(SensorType /*type*/)
{
	// Attempted USE: naming the underlying device. Warn once, return a stable
	// empty string (the SDL backend throws when the sensor is not enabled; we
	// return a benign default instead).
	preview_warn_once("sensor.getName",
		"love.sensor.getName: motion sensors are not available in the "
		"browser preview; returning an empty name.");
	return "";
}

std::vector<void *> Sensor::getHandles()
{
	// No backend-native sensor handles exist. Benign empty list — matches
	// hasSensor()/isEnabled() being false — and not an attempted read of any
	// device, so no warning.
	return std::vector<void *>();
}

} // wasm
} // sensor
} // love
