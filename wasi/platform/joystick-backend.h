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

// love-wasi platform seam — build-order step 6.5: the real love.joystick /
// love.gamepad backend for wasm32-wasi, on the host-import love_gamepad seam over
// the browser Gamepad API. It replaces SDL's joystick/gamepad backend (which
// polls a native controller subsystem the browser has no access to) with one fed
// by navigator.getGamepads() the host reads.
//
// UNLIKE the 6.4 love_input seam (host->guest PUSH: the host queues DOM events),
// the browser Gamepad API is POLL-based — there is no gamepad-event stream, only
// a per-frame snapshot array. So this seam is guest->host PULL, like fs/window/
// gl: once per frame the guest reads the current gamepad slots and DIFFS them
// against the previous poll to SYNTHESIZE the joystickpressed/released,
// joystickaxis, gamepadpressed/released, gamepadaxis, joystickadded/removed
// events SDL would have delivered. That synthesis reuses 6.4's push mechanism:
// the diffed events are love::event::Message objects pushed onto the same
// love.event queue the unchanged Lua dispatch drains.
//
// WHERE the poll happens: love.event's pump() is the one per-frame drain point.
// A weak hook (wasi_poll_gamepad_events, declared in input-backend.cpp and left
// null there) is called at the START of pump(); this TU defines it strong, so
// linking joystick-backend.cpp wires the gamepad poll into the existing pump
// without the 6.4 event backend depending on the joystick module.
//
// The W3C "standard gamepad" mapping is ~1:1 with LÖVE's (SDL's) standard
// controller mapping, so love.gamepad rides it directly. The button-index and
// axis translation lives here, in C++, next to LÖVE's GamepadButton/GamepadAxis
// enums — the same split the input backend has (host forwards browser truth, the
// backend owns LÖVE semantics).
//
// Warn-once edges (honest, non-fatal — the input path itself is real): vibration
// (the windowless witness can't drive a real vibrationActuator), the SDL
// controller-DB mapping string (no controller DB in the browser), and joystick
// motion sensors (no gamepad sensor stream here).
//
// This header lives out-of-tree (readme.md: the src tree stays upstream-shaped);
// wrap_JoystickModule.cpp includes it under LOVE_WASI via -I wasi/platform and
// constructs the wasm:: module in place of the sdl:: one at its one guarded
// factory.
#ifndef LOVE_WASI_PLATFORM_JOYSTICK_BACKEND_H
#define LOVE_WASI_PLATFORM_JOYSTICK_BACKEND_H

#include "common/config.h"
#include "common/int.h"
#include "joystick/Joystick.h"
#include "joystick/JoystickModule.h"

#include <cstdint>
#include <string>
#include <vector>

namespace love
{
namespace joystick
{
namespace wasm
{

// One poll's worth of a single gamepad, decoded from the 224-byte host record
// (see joystick-backend.cpp for the wire layout). A Joystick keeps its CURRENT
// snapshot (what the query methods read) and its PREVIOUS one (what the poll
// diffs against to synthesize events) — the same reader/writer split the 6.4
// input backend has, one poll being the single writer.
struct GamepadSnapshot
{
	static const int MAX_AXES = 8;
	static const int MAX_BUTTONS = 24;

	bool connected = false;
	int mapping = 0;       // 0 = none, 1 = W3C "standard"
	int axisCount = 0;     // <= MAX_AXES
	int buttonCount = 0;   // <= MAX_BUTTONS
	uint32_t buttonMask = 0; // bit i = button i pressed
	float axes[MAX_AXES] = {0};
	float buttonValues[MAX_BUTTONS] = {0};
	std::string id;
};

class Joystick final : public love::joystick::Joystick
{
public:

	Joystick(int id);
	virtual ~Joystick() {}

	// The gamepad SLOT (navigator.getGamepads() index) this stick tracks, and the
	// poll ingest that swaps current<-previous and loads a fresh snapshot from the
	// host record. loadSnapshot leaves `prev` untouched so the diff (in
	// wasi_poll_gamepad_events) can compare, then commit() promotes cur -> prev.
	int getSlot() const { return slot; }
	void setInstanceID(int inst) { instanceid = inst; }
	void loadSnapshot(const uint8_t *rec);
	void commit() { prev = cur; }
	const GamepadSnapshot &current() const { return cur; }
	const GamepadSnapshot &previous() const { return prev; }

	// W3C standard button index <-> LÖVE GamepadButton (both directions). Returns
	// false for indices/buttons with no counterpart (e.g. W3C 6/7 are the analog
	// triggers, which LÖVE models as AXES, not buttons).
	static bool w3cButtonToGamepad(int w3cIndex, GamepadButton &out);
	static bool gamepadToW3cButton(GamepadButton in, int &out);

	// love::joystick::Joystick
	bool open(int64 deviceid) override;
	void close() override;
	bool isConnected() const override;
	const char *getName() const override;
	JoystickType getJoystickType() const override;
	int getAxisCount() const override;
	int getButtonCount() const override;
	int getHatCount() const override;
	float getAxis(int axisindex) const override;
	std::vector<float> getAxes() const override;
	Hat getHat(int hatindex) const override;
	bool isDown(const std::vector<int> &buttonlist) const override;
	void setPlayerIndex(int index) override;
	int getPlayerIndex() const override;
	bool openGamepad(int64 deviceid) override;
	bool isGamepad() const override;
	GamepadType getGamepadType() const override;
	float getGamepadAxis(GamepadAxis axis) const override;
	bool isGamepadDown(const std::vector<GamepadButton> &blist) const override;
	JoystickInput getGamepadMapping(const GamepadInput &input) const override;
	std::string getGamepadMappingString() const override;
	void *getHandle() const override;
	std::string getGUID() const override;
	int getInstanceID() const override;
	int getID() const override;
	void getDeviceInfo(int &vendorID, int &productID, int &productVersion) const override;
	bool isVibrationSupported() override;
	bool setVibration(float left, float right, float duration = -1.0f) override;
	bool setVibration() override;
	void getVibration(float &left, float &right) override;
	bool hasSensor(Sensor::SensorType type) const override;
	bool isSensorEnabled(Sensor::SensorType type) const override;
	void setSensorEnabled(Sensor::SensorType type, bool enabled) override;
	std::vector<float> getSensorData(Sensor::SensorType type) const override;
	PowerType getPowerInfo(int &batteryPercent) const override;
	ConnectionType getConnectionState() const override;

	// The value of a mapped GAMEPAD axis for a given snapshot (used by both the
	// query getGamepadAxis and the poll's gamepadaxis diff).
	static float mappedAxis(const GamepadSnapshot &s, GamepadAxis axis);

private:

	int id;         // 0-based joystick index (getID)
	int slot;       // navigator.getGamepads() slot
	int instanceid; // stable per-connection instance id
	int playerIndex = -1;

	GamepadSnapshot cur;
	GamepadSnapshot prev;

}; // Joystick

class JoystickModule final : public love::joystick::JoystickModule
{
public:

	JoystickModule();
	virtual ~JoystickModule();

	// The stick tracking a given gamepad slot, or null. Used by the per-frame
	// poll (wasi_poll_gamepad_events) to find or create the stick for a slot.
	Joystick *getJoystickBySlot(int slot) const;

	// love::joystick::JoystickModule
	love::joystick::Joystick *addJoystick(int64 deviceid) override;
	void removeJoystick(love::joystick::Joystick *joystick) override;
	love::joystick::Joystick *getJoystickFromID(int instanceid) override;
	love::joystick::Joystick *getJoystick(int joyindex) override;
	int getIndex(const love::joystick::Joystick *joystick) override;
	int getJoystickCount() const override;
	void setBackgroundEvents(bool enable) override;
	bool hasBackgroundEvents() const override;
	bool setGamepadMapping(const std::string &guid, Joystick::GamepadInput gpinput, Joystick::JoystickInput joyinput) override;
	void loadGamepadMappings(const std::string &mappings) override;
	std::string saveGamepadMappings() override;
	std::string getGamepadMappingString(const std::string &guid) const override;

private:

	std::vector<love::joystick::Joystick *> activeSticks; // owns a ref each
	int nextInstanceID = 0;
	bool backgroundEvents = true;

}; // JoystickModule

} // wasm
} // joystick
} // love

#endif // LOVE_WASI_PLATFORM_JOYSTICK_BACKEND_H
