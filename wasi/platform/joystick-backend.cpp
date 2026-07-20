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

// love-wasi platform seam — build-order step 6.5 implementation. See the header
// (joystick-backend.h) for the design: a poll-based love_gamepad seam over the
// browser Gamepad API, the per-frame diff that synthesizes the joystick/gamepad
// events SDL would push, and the W3C-standard <-> LÖVE mapping kept in C++.

#include "joystick-backend.h"
#include "preview-warn.h"

#include "common/Module.h"
#include "common/Object.h"
#include "event/Event.h"

#include <cmath>
#include <cstring>

// ── The love_gamepad host seam ────────────────────────────────────────────────
//
// Poll-based, mirroring navigator.getGamepads(). Two imports, both guest->host
// PULL. gamepad_count() returns the slot count for this poll AND advances the
// host's scripted frame (so successive polls see successive scripted states) —
// so it is called EXACTLY ONCE per poll. gamepad_read(slot, rec, cap) writes a
// fixed 224-byte record and returns 1 for a connected slot, 0 for an empty one.
#define GP_IMPORT(sym) __attribute__((import_module("love_gamepad"), import_name(sym)))

extern "C" {
GP_IMPORT("gamepad_count") int32_t gp_count();
GP_IMPORT("gamepad_read") int32_t gp_read(int32_t slot, uint8_t *rec, int32_t cap);
}

// The gamepad-record wire format (must match the host writer exactly, LE):
//   [0]  i32 index          [4]  i32 connected     [8]  i32 mapping(0=none,1=std)
//   [12] i32 axisCount(<=8)  [16] i32 buttonCount(<=24)
//   [20] i32 buttonPressedMask (bit i = button i pressed)  [24] i32 (pad)
//   [32] f32 axes[8]     (offset 32..64)
//   [64] f32 buttonValues[24] (offset 64..160)
//   [160] char id[64]    (offset 160..224)
static const int32_t GP_REC_SIZE = 224;

static inline int32_t recInt(const uint8_t *rec, int off) { int32_t v; std::memcpy(&v, rec + off, 4); return v; }
static inline float recFloat(const uint8_t *rec, int off) { float v; std::memcpy(&v, rec + off, 4); return v; }

namespace love
{
namespace joystick
{
namespace wasm
{

// ── The W3C "standard gamepad" mapping ────────────────────────────────────────
//
// W3C standard button index -> LÖVE GamepadButton. The two mappings coincide
// (LÖVE's is SDL's standard-controller mapping, ~1:1 with W3C's). W3C indices 6
// and 7 (the analog triggers) are absent here on purpose: LÖVE models the
// triggers as AXES (TRIGGERLEFT/TRIGGERRIGHT), read from buttonValues[6]/[7] in
// mappedAxis below, not as buttons. So a trigger pull emits gamepadaxis, not
// gamepadpressed — exactly as SDL delivers it.
struct W3cButton { int w3c; Joystick::GamepadButton button; };
static const W3cButton kW3cButtons[] = {
	{0,  Joystick::GAMEPAD_BUTTON_A},
	{1,  Joystick::GAMEPAD_BUTTON_B},
	{2,  Joystick::GAMEPAD_BUTTON_X},
	{3,  Joystick::GAMEPAD_BUTTON_Y},
	{4,  Joystick::GAMEPAD_BUTTON_LEFTSHOULDER},
	{5,  Joystick::GAMEPAD_BUTTON_RIGHTSHOULDER},
	{8,  Joystick::GAMEPAD_BUTTON_BACK},
	{9,  Joystick::GAMEPAD_BUTTON_START},
	{10, Joystick::GAMEPAD_BUTTON_LEFTSTICK},
	{11, Joystick::GAMEPAD_BUTTON_RIGHTSTICK},
	{12, Joystick::GAMEPAD_BUTTON_DPAD_UP},
	{13, Joystick::GAMEPAD_BUTTON_DPAD_DOWN},
	{14, Joystick::GAMEPAD_BUTTON_DPAD_LEFT},
	{15, Joystick::GAMEPAD_BUTTON_DPAD_RIGHT},
	{16, Joystick::GAMEPAD_BUTTON_GUIDE},
};

bool Joystick::w3cButtonToGamepad(int w3cIndex, GamepadButton &out)
{
	for (const W3cButton &e : kW3cButtons)
		if (e.w3c == w3cIndex) { out = e.button; return true; }
	return false;
}

bool Joystick::gamepadToW3cButton(GamepadButton in, int &out)
{
	for (const W3cButton &e : kW3cButtons)
		if (e.button == in) { out = e.w3c; return true; }
	return false;
}

float Joystick::mappedAxis(const GamepadSnapshot &s, GamepadAxis axis)
{
	// W3C standard axes: 0=leftx 1=lefty 2=rightx 3=righty; triggers are buttons
	// 6/7 read as analog values.
	switch (axis)
	{
	case GAMEPAD_AXIS_LEFTX:        return s.axes[0];
	case GAMEPAD_AXIS_LEFTY:        return s.axes[1];
	case GAMEPAD_AXIS_RIGHTX:       return s.axes[2];
	case GAMEPAD_AXIS_RIGHTY:       return s.axes[3];
	case GAMEPAD_AXIS_TRIGGERLEFT:  return s.buttonValues[6];
	case GAMEPAD_AXIS_TRIGGERRIGHT: return s.buttonValues[7];
	default:                        return 0.0f;
	}
}

// ── Joystick ──────────────────────────────────────────────────────────────────

Joystick::Joystick(int id)
	: id(id)
	, slot(-1)
	, instanceid(-1)
{
}

void Joystick::loadSnapshot(const uint8_t *rec)
{
	GamepadSnapshot s;
	s.connected   = recInt(rec, 4) != 0;
	s.mapping     = recInt(rec, 8);
	s.axisCount   = recInt(rec, 12);
	s.buttonCount = recInt(rec, 16);
	s.buttonMask  = (uint32_t) recInt(rec, 20);
	if (s.axisCount < 0) s.axisCount = 0;
	if (s.axisCount > GamepadSnapshot::MAX_AXES) s.axisCount = GamepadSnapshot::MAX_AXES;
	if (s.buttonCount < 0) s.buttonCount = 0;
	if (s.buttonCount > GamepadSnapshot::MAX_BUTTONS) s.buttonCount = GamepadSnapshot::MAX_BUTTONS;
	for (int i = 0; i < GamepadSnapshot::MAX_AXES; i++)
		s.axes[i] = recFloat(rec, 32 + i * 4);
	for (int i = 0; i < GamepadSnapshot::MAX_BUTTONS; i++)
		s.buttonValues[i] = recFloat(rec, 64 + i * 4);
	const char *idp = reinterpret_cast<const char *>(rec + 160);
	s.id = std::string(idp, strnlen(idp, 64));
	cur = s;
}

bool Joystick::open(int64 deviceid)
{
	slot = (int) deviceid;
	cur.connected = true;
	return true;
}

void Joystick::close()
{
	cur.connected = false;
}

bool Joystick::isConnected() const { return cur.connected; }

const char *Joystick::getName() const { return cur.id.c_str(); }

Joystick::JoystickType Joystick::getJoystickType() const
{
	return cur.mapping == 1 ? JOYSTICK_TYPE_GAMEPAD : JOYSTICK_TYPE_UNKNOWN;
}

int Joystick::getAxisCount() const { return cur.axisCount; }
int Joystick::getButtonCount() const { return cur.buttonCount; }

// The W3C standard mapping models the d-pad as four buttons (12..15), so there is
// no hat. Honest 0 — LÖVE games read the d-pad via isGamepadDown("dpup"/…).
int Joystick::getHatCount() const { return 0; }

float Joystick::getAxis(int axisindex) const
{
	if (axisindex < 0 || axisindex >= cur.axisCount)
		return 0.0f;
	return clampval(cur.axes[axisindex]);
}

std::vector<float> Joystick::getAxes() const
{
	std::vector<float> out;
	out.reserve(cur.axisCount);
	for (int i = 0; i < cur.axisCount; i++)
		out.push_back(clampval(cur.axes[i]));
	return out;
}

Joystick::Hat Joystick::getHat(int /*hatindex*/) const { return HAT_CENTERED; }

bool Joystick::isDown(const std::vector<int> &buttonlist) const
{
	// Raw buttons are 0-indexed here (wrap_Joystick already subtracted 1 from the
	// 1-indexed Lua argument), matching the W3C button array index.
	for (int b : buttonlist)
		if (b >= 0 && b < 32 && (cur.buttonMask & (1u << b)))
			return true;
	return false;
}

void Joystick::setPlayerIndex(int index) { playerIndex = index; }
int Joystick::getPlayerIndex() const { return playerIndex; }

bool Joystick::openGamepad(int64 deviceid) { return open(deviceid); }

bool Joystick::isGamepad() const { return cur.mapping == 1; }

Joystick::GamepadType Joystick::getGamepadType() const
{
	// The Gamepad API exposes only a free-form id string, not a device class the
	// SDL controller DB would resolve. Honest unknown.
	return GAMEPAD_TYPE_UNKNOWN;
}

float Joystick::getGamepadAxis(GamepadAxis axis) const
{
	return clampval(mappedAxis(cur, axis));
}

bool Joystick::isGamepadDown(const std::vector<GamepadButton> &blist) const
{
	for (GamepadButton b : blist)
	{
		int w3c;
		if (gamepadToW3cButton(b, w3c) && w3c < 32 && (cur.buttonMask & (1u << w3c)))
			return true;
	}
	return false;
}

Joystick::JoystickInput Joystick::getGamepadMapping(const GamepadInput &input) const
{
	// The forward mapping is fixed (W3C standard), so we can answer which raw
	// joystick input backs a gamepad input without a controller DB.
	JoystickInput j;
	j.type = INPUT_TYPE_MAX_ENUM;

	if (input.type == INPUT_TYPE_BUTTON)
	{
		int w3c;
		if (gamepadToW3cButton(input.button, w3c))
		{
			j.type = INPUT_TYPE_BUTTON;
			j.button = w3c;
		}
	}
	else if (input.type == INPUT_TYPE_AXIS)
	{
		switch (input.axis)
		{
		case GAMEPAD_AXIS_LEFTX:  j.type = INPUT_TYPE_AXIS; j.axis = 0; break;
		case GAMEPAD_AXIS_LEFTY:  j.type = INPUT_TYPE_AXIS; j.axis = 1; break;
		case GAMEPAD_AXIS_RIGHTX: j.type = INPUT_TYPE_AXIS; j.axis = 2; break;
		case GAMEPAD_AXIS_RIGHTY: j.type = INPUT_TYPE_AXIS; j.axis = 3; break;
		// The triggers are W3C buttons 6/7 (analog); report them as such.
		case GAMEPAD_AXIS_TRIGGERLEFT:  j.type = INPUT_TYPE_BUTTON; j.button = 6; break;
		case GAMEPAD_AXIS_TRIGGERRIGHT: j.type = INPUT_TYPE_BUTTON; j.button = 7; break;
		default: break;
		}
	}
	return j;
}

std::string Joystick::getGamepadMappingString() const
{
	// The SDL controller-DB mapping string has no browser analog (there is no
	// controller DB — the W3C standard mapping is implicit). Honest empty.
	preview_warn_once("joystick.getGamepadMappingString",
		"love.joystick Joystick:getGamepadMappingString returns \"\" in the "
		"browser (the W3C standard-gamepad mapping is implicit; there is no SDL "
		"controller-DB string).");
	return "";
}

void *Joystick::getHandle() const { return nullptr; }

std::string Joystick::getGUID() const
{
	// A synthesized constant standing in for the SDL GUID (the browser exposes no
	// per-device GUID). Stable so a game can at least compare it to itself.
	return "wasmstandardgamepad0";
}

int Joystick::getInstanceID() const { return instanceid; }
int Joystick::getID() const { return id; }

void Joystick::getDeviceInfo(int &vendorID, int &productID, int &productVersion) const
{
	// The Gamepad API exposes no vendor/product IDs (only the free-form id).
	vendorID = 0;
	productID = 0;
	productVersion = 0;
}

bool Joystick::isVibrationSupported()
{
	// The browser gamepad DOES expose a vibrationActuator, but driving it is a
	// host effect the windowless witness cannot observe, so 6.5 reports it
	// unsupported rather than faking a rumble the witness can't confirm. Honest
	// warn-once edge (documented in DESIGN.md); a later sub-step can wire the
	// real actuator through the host once there is a way to witness it.
	preview_warn_once("joystick.isVibrationSupported",
		"love.joystick vibration is reported unsupported in the browser preview "
		"(the gamepad vibrationActuator is a host effect not driven by 6.5).");
	return false;
}

bool Joystick::setVibration(float /*left*/, float /*right*/, float /*duration*/)
{
	preview_warn_once("joystick.setVibration",
		"love.joystick Joystick:setVibration is a no-op in the browser preview "
		"(gamepad rumble is not driven by 6.5); returning false.");
	return false;
}

bool Joystick::setVibration() { return false; }

void Joystick::getVibration(float &left, float &right)
{
	left = 0.0f;
	right = 0.0f;
}

bool Joystick::hasSensor(Sensor::SensorType /*type*/) const { return false; }
bool Joystick::isSensorEnabled(Sensor::SensorType /*type*/) const { return false; }

void Joystick::setSensorEnabled(Sensor::SensorType /*type*/, bool /*enabled*/)
{
	preview_warn_once("joystick.setSensorEnabled",
		"love.joystick gamepad motion sensors are not available in the browser "
		"preview; Joystick:setSensorEnabled is a no-op.");
}

std::vector<float> Joystick::getSensorData(Sensor::SensorType /*type*/) const
{
	preview_warn_once("joystick.getSensorData",
		"love.joystick gamepad motion sensors are not available in the browser "
		"preview; Joystick:getSensorData returns an empty list.");
	return std::vector<float>();
}

Joystick::PowerType Joystick::getPowerInfo(int &batteryPercent) const
{
	// The Gamepad API exposes no battery info.
	batteryPercent = -1;
	return POWER_UNKNOWN;
}

Joystick::ConnectionType Joystick::getConnectionState() const { return CONNECTION_UNKNOWN; }

// ── JoystickModule ────────────────────────────────────────────────────────────

JoystickModule::JoystickModule()
	: love::joystick::JoystickModule("love.joystick.wasm")
{
}

JoystickModule::~JoystickModule()
{
	for (love::joystick::Joystick *j : activeSticks)
		j->release();
	activeSticks.clear();
}

Joystick *JoystickModule::getJoystickBySlot(int slot) const
{
	for (love::joystick::Joystick *j : activeSticks)
	{
		Joystick *w = (Joystick *) j;
		if (w->getSlot() == slot)
			return w;
	}
	return nullptr;
}

love::joystick::Joystick *JoystickModule::addJoystick(int64 deviceid)
{
	int slot = (int) deviceid;

	// If a stick already tracks this slot, reuse it (idempotent add).
	Joystick *existing = getJoystickBySlot(slot);
	if (existing)
		return existing;

	Joystick *j = new Joystick((int) activeSticks.size());
	j->open(slot);
	j->setInstanceID(nextInstanceID++);
	activeSticks.push_back(j); // `new` gives refcount 1 — the module owns it.
	return j;
}

void JoystickModule::removeJoystick(love::joystick::Joystick *joystick)
{
	if (!joystick)
		return;
	for (auto it = activeSticks.begin(); it != activeSticks.end(); ++it)
	{
		if (*it == joystick)
		{
			joystick->close();
			joystick->release();
			activeSticks.erase(it);
			return;
		}
	}
}

love::joystick::Joystick *JoystickModule::getJoystickFromID(int instanceid)
{
	for (love::joystick::Joystick *j : activeSticks)
		if (j->getInstanceID() == instanceid)
			return j;
	return nullptr;
}

love::joystick::Joystick *JoystickModule::getJoystick(int joyindex)
{
	if (joyindex < 0 || joyindex >= (int) activeSticks.size())
		return nullptr;
	return activeSticks[joyindex];
}

int JoystickModule::getIndex(const love::joystick::Joystick *joystick)
{
	for (int i = 0; i < (int) activeSticks.size(); i++)
		if (activeSticks[i] == joystick)
			return i;
	return -1;
}

int JoystickModule::getJoystickCount() const { return (int) activeSticks.size(); }

void JoystickModule::setBackgroundEvents(bool enable) { backgroundEvents = enable; }
bool JoystickModule::hasBackgroundEvents() const { return backgroundEvents; }

bool JoystickModule::setGamepadMapping(const std::string & /*guid*/, Joystick::GamepadInput /*gpinput*/, Joystick::JoystickInput /*joyinput*/)
{
	// No controller DB in the browser; the W3C standard mapping is fixed and not
	// user-overridable. Honest warn-once + false.
	preview_warn_once("joystick.setGamepadMapping",
		"love.joystick.setGamepadMapping has no effect in the browser (the W3C "
		"standard-gamepad mapping is fixed; there is no controller DB); returning "
		"false.");
	return false;
}

void JoystickModule::loadGamepadMappings(const std::string & /*mappings*/)
{
	preview_warn_once("joystick.loadGamepadMappings",
		"love.joystick.loadGamepadMappings is ignored in the browser (no "
		"controller DB; the W3C standard-gamepad mapping is implicit).");
}

std::string JoystickModule::saveGamepadMappings() { return ""; }

std::string JoystickModule::getGamepadMappingString(const std::string & /*guid*/) const
{
	return "";
}

} // wasm
} // joystick
} // love

// ── The per-frame gamepad poll (the weak hook into love.event's pump) ─────────
//
// input-backend.cpp declares this extern-"C" weak and calls it at the START of
// event::wasm::Event::pump(). In the 6.4 build (no joystick-backend linked) the
// weak symbol is null and the call is skipped; linking THIS TU defines it strong,
// so the gamepad poll runs once per pump. Each poll:
//   1. gp_count() ONCE (advances the host's scripted frame),
//   2. gp_read each slot, tracking which slots are present,
//   3. for a newly-present slot -> addJoystick + push joystickadded, then diff,
//   4. for each present stick -> diff cur vs prev, pushing raw joystick* AND
//      mapped gamepad* events per physical change (both, exactly as SDL sends
//      JOYSTICK_ and GAMEPAD_ events for the same press), then commit,
//   5. for a previously-present slot now absent -> push joystickremoved +
//      removeJoystick.

namespace
{

using love::event::Event;
using love::event::Message;
using love::joystick::Joystick;
using love::joystick::wasm::GamepadSnapshot;

const float kAxisEpsilon = 1e-4f;

void pushMessage(Event *ev, Message *msg)
{
	love::StrongRef<Message> ref(msg, love::Acquire::NORETAIN);
	ev->push(ref);
}

// The Joystick is passed as Variant(&Joystick::type, stick); build the vargs and
// push, mirroring event/sdl/Event.cpp's convertJoystickEvent.
void pushStickOnly(Event *ev, const char *name, love::joystick::Joystick *stick)
{
	std::vector<love::Variant> vargs;
	vargs.reserve(1);
	vargs.emplace_back(&Joystick::type, stick);
	pushMessage(ev, new Message(name, vargs));
}

void pushJoystickButton(Event *ev, love::joystick::Joystick *stick, int rawButtonIndex, bool down)
{
	std::vector<love::Variant> vargs;
	vargs.reserve(2);
	vargs.emplace_back(&Joystick::type, stick);
	vargs.emplace_back((double)(rawButtonIndex + 1));
	pushMessage(ev, new Message(down ? "joystickpressed" : "joystickreleased", vargs));
}

void pushJoystickAxis(Event *ev, love::joystick::Joystick *stick, int rawAxisIndex, float value)
{
	std::vector<love::Variant> vargs;
	vargs.reserve(3);
	vargs.emplace_back(&Joystick::type, stick);
	vargs.emplace_back((double)(rawAxisIndex + 1));
	vargs.emplace_back((double) Joystick::clampval(value));
	pushMessage(ev, new Message("joystickaxis", vargs));
}

void pushGamepadButton(Event *ev, love::joystick::Joystick *stick, Joystick::GamepadButton button, bool down)
{
	const char *txt;
	if (!Joystick::getConstant(button, txt))
		return;
	std::vector<love::Variant> vargs;
	vargs.reserve(2);
	vargs.emplace_back(&Joystick::type, stick);
	vargs.emplace_back(txt, std::strlen(txt));
	pushMessage(ev, new Message(down ? "gamepadpressed" : "gamepadreleased", vargs));
}

void pushGamepadAxis(Event *ev, love::joystick::Joystick *stick, Joystick::GamepadAxis axis, float value)
{
	const char *txt;
	if (!Joystick::getConstant(axis, txt))
		return;
	std::vector<love::Variant> vargs;
	vargs.reserve(3);
	vargs.emplace_back(&Joystick::type, stick);
	vargs.emplace_back(txt, std::strlen(txt));
	vargs.emplace_back((double) Joystick::clampval(value));
	pushMessage(ev, new Message("gamepadaxis", vargs));
}

// Diff cur vs prev for one connected stick and push every physical change.
void diffAndPush(Event *ev, love::joystick::wasm::Joystick *stick)
{
	const GamepadSnapshot &cur = stick->current();
	const GamepadSnapshot &prev = stick->previous();

	bool standard = cur.mapping == 1;

	// Buttons: raw joystickpressed/released for every button whose pressed bit
	// changed, plus gamepadpressed/released for the mapped gamepad button (both,
	// as SDL sends both event families for one physical press).
	int nbuttons = cur.buttonCount;
	if (nbuttons > GamepadSnapshot::MAX_BUTTONS)
		nbuttons = GamepadSnapshot::MAX_BUTTONS;
	for (int b = 0; b < nbuttons; b++)
	{
		bool nowDown = (cur.buttonMask & (1u << b)) != 0;
		bool wasDown = (prev.buttonMask & (1u << b)) != 0;
		if (nowDown == wasDown)
			continue;

		pushJoystickButton(ev, stick, b, nowDown);

		Joystick::GamepadButton gb;
		if (standard && love::joystick::wasm::Joystick::w3cButtonToGamepad(b, gb))
			pushGamepadButton(ev, stick, gb, nowDown);
	}

	// Raw axes: joystickaxis for every raw axis that moved beyond epsilon.
	int naxes = cur.axisCount;
	if (naxes > GamepadSnapshot::MAX_AXES)
		naxes = GamepadSnapshot::MAX_AXES;
	for (int a = 0; a < naxes; a++)
	{
		if (std::fabs(cur.axes[a] - prev.axes[a]) > kAxisEpsilon)
			pushJoystickAxis(ev, stick, a, cur.axes[a]);
	}

	// Mapped gamepad axes: gamepadaxis for every mapped axis that moved. Triggers
	// (buttonValues 6/7) are included here — a trigger emits gamepadaxis, not a
	// gamepad button, matching SDL and the W3C-standard model.
	if (standard)
	{
		static const Joystick::GamepadAxis kAxes[] = {
			Joystick::GAMEPAD_AXIS_LEFTX, Joystick::GAMEPAD_AXIS_LEFTY,
			Joystick::GAMEPAD_AXIS_RIGHTX, Joystick::GAMEPAD_AXIS_RIGHTY,
			Joystick::GAMEPAD_AXIS_TRIGGERLEFT, Joystick::GAMEPAD_AXIS_TRIGGERRIGHT,
		};
		for (Joystick::GamepadAxis ax : kAxes)
		{
			float now = love::joystick::wasm::Joystick::mappedAxis(cur, ax);
			float was = love::joystick::wasm::Joystick::mappedAxis(prev, ax);
			if (std::fabs(now - was) > kAxisEpsilon)
				pushGamepadAxis(ev, stick, ax, now);
		}
	}
}

} // anonymous namespace

extern "C" void wasi_poll_gamepad_events()
{
	using love::Module;

	auto joymodule = Module::getInstance<love::joystick::wasm::JoystickModule>(Module::M_JOYSTICK);
	auto ev = Module::getInstance<love::event::Event>(Module::M_EVENT);
	if (!joymodule || !ev)
		return;

	int32_t count = gp_count(); // ONCE per poll — advances the host's scripted frame.
	if (count < 0)
		count = 0;

	// Which existing sticks we saw present this poll (by slot).
	std::vector<int> seenSlots;
	seenSlots.reserve(count);

	uint8_t rec[GP_REC_SIZE];
	for (int32_t slot = 0; slot < count; slot++)
	{
		if (gp_read(slot, rec, GP_REC_SIZE) != 1)
			continue; // empty/disconnected slot

		seenSlots.push_back(slot);

		love::joystick::wasm::Joystick *stick = joymodule->getJoystickBySlot(slot);
		bool isNew = (stick == nullptr);
		if (isNew)
		{
			// addJoystick creates + opens the stick; its `prev` is all-zero, so the
			// first diff yields the pressed/axis events for the initial state.
			stick = (love::joystick::wasm::Joystick *) joymodule->addJoystick(slot);
			pushStickOnly(ev, "joystickadded", stick);
		}

		stick->loadSnapshot(rec);
		diffAndPush(ev, stick);
		stick->commit();
	}

	// Any previously-present stick whose slot was NOT read this poll is gone.
	// Collect first (removeJoystick mutates the module's list).
	std::vector<love::joystick::wasm::Joystick *> removed;
	for (int i = 0; i < joymodule->getJoystickCount(); i++)
	{
		auto *w = (love::joystick::wasm::Joystick *) joymodule->getJoystick(i);
		int slot = w->getSlot();
		bool seen = false;
		for (int s : seenSlots)
			if (s == slot) { seen = true; break; }
		if (!seen)
			removed.push_back(w);
	}
	for (auto *w : removed)
	{
		pushStickOnly(ev, "joystickremoved", w);
		joymodule->removeJoystick(w);
	}
}
