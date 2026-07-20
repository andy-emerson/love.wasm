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

// love-wasi platform seam — build-order step 6.4 implementation. See the header
// (input-backend.h) for the design: one shared InputState, pump() the single
// writer, keyboard/mouse the readers, and the DOM<->LÖVE name mapping kept here
// in C++ next to LÖVE's Key/Scancode enums.

#include "input-backend.h"
#include "preview-warn.h"

#include "common/Exception.h"
#include "common/Object.h"

#include <cstdint>
#include <cstring>

// ── The love_input host seam ──────────────────────────────────────────────────
//
// input_poll drains one queued DOM event into a fixed 128-byte record; the rest
// are guest->host side effects (cursor, pointer lock, text-input focus) the host
// applies to the real canvas. All fulfilled host-side (wasi/host/input-host.mjs).
#define INPUT_IMPORT(sym) __attribute__((import_module("love_input"), import_name(sym)))

extern "C" {
INPUT_IMPORT("input_poll") int32_t win_input_poll(uint8_t *rec, int32_t cap);
INPUT_IMPORT("input_set_cursor_visible") void win_input_set_cursor_visible(int32_t visible);
INPUT_IMPORT("input_set_cursor_shape") void win_input_set_cursor_shape(int32_t systemCursor);
INPUT_IMPORT("input_warp") void win_input_warp(double x, double y);
INPUT_IMPORT("input_set_relative") int32_t win_input_set_relative(int32_t relative);
INPUT_IMPORT("input_set_text_input") void win_input_set_text_input(int32_t enable, double x, double y, double w, double h);
}

// The event-record wire format (must match the host writer exactly, LE):
//   [0]  double a    mouse x / wheel x
//   [8]  double b    mouse y / wheel y
//   [16] double c    mouse dx
//   [24] double d    mouse dy
//   [32] int32  type (EventType below)
//   [36] int32  i0   DOM button(0/1/2) | repeat | resize w | bool flag
//   [40] int32  i1   clicks | resize h | quit exit code
//   [44] int32  i2   wheel flipped (0/1)
//   [48] char   code[40]  DOM event.code (key events)
//   [88] char   key[40]   DOM event.key, or the textinput UTF-8 payload
static const int32_t REC_SIZE = 128;

enum EventType : int32_t
{
	EV_KEYDOWN = 1,
	EV_KEYUP = 2,
	EV_TEXTINPUT = 3,
	EV_MOUSEMOVED = 4,
	EV_MOUSEPRESSED = 5,
	EV_MOUSERELEASED = 6,
	EV_WHEEL = 7,
	EV_RESIZE = 8,
	EV_FOCUS = 9,
	EV_MOUSEFOCUS = 10,
	EV_VISIBLE = 11,
	EV_QUIT = 12,
};

namespace love
{
namespace wasi_input
{

InputState &state()
{
	static InputState s;
	return s;
}

// DOM KeyboardEvent.code (physical, layout-independent) -> the LÖVE name that
// serves as BOTH the scancode name and, on the default US layout, the key name
// (the two coincide across the whole standard set — see e.g. "left"/"lshift"/
// "return" in keyboard/Keyboard.cpp). The list is the standard 104-key board
// plus the keypad; codes with no LÖVE counterpart return false ("unknown").
struct CodeName { const char *code; const char *name; };

static const CodeName kCodeNames[] = {
	{"KeyA", "a"}, {"KeyB", "b"}, {"KeyC", "c"}, {"KeyD", "d"}, {"KeyE", "e"},
	{"KeyF", "f"}, {"KeyG", "g"}, {"KeyH", "h"}, {"KeyI", "i"}, {"KeyJ", "j"},
	{"KeyK", "k"}, {"KeyL", "l"}, {"KeyM", "m"}, {"KeyN", "n"}, {"KeyO", "o"},
	{"KeyP", "p"}, {"KeyQ", "q"}, {"KeyR", "r"}, {"KeyS", "s"}, {"KeyT", "t"},
	{"KeyU", "u"}, {"KeyV", "v"}, {"KeyW", "w"}, {"KeyX", "x"}, {"KeyY", "y"},
	{"KeyZ", "z"},
	{"Digit1", "1"}, {"Digit2", "2"}, {"Digit3", "3"}, {"Digit4", "4"},
	{"Digit5", "5"}, {"Digit6", "6"}, {"Digit7", "7"}, {"Digit8", "8"},
	{"Digit9", "9"}, {"Digit0", "0"},
	{"Enter", "return"}, {"Escape", "escape"}, {"Backspace", "backspace"},
	{"Tab", "tab"}, {"Space", "space"},
	{"Minus", "-"}, {"Equal", "="}, {"BracketLeft", "["}, {"BracketRight", "]"},
	{"Backslash", "\\"}, {"Semicolon", ";"}, {"Quote", "'"}, {"Backquote", "`"},
	{"Comma", ","}, {"Period", "."}, {"Slash", "/"},
	{"CapsLock", "capslock"},
	{"F1", "f1"}, {"F2", "f2"}, {"F3", "f3"}, {"F4", "f4"}, {"F5", "f5"},
	{"F6", "f6"}, {"F7", "f7"}, {"F8", "f8"}, {"F9", "f9"}, {"F10", "f10"},
	{"F11", "f11"}, {"F12", "f12"},
	{"PrintScreen", "printscreen"}, {"ScrollLock", "scrolllock"}, {"Pause", "pause"},
	{"Insert", "insert"}, {"Home", "home"}, {"PageUp", "pageup"},
	{"Delete", "delete"}, {"End", "end"}, {"PageDown", "pagedown"},
	{"ArrowRight", "right"}, {"ArrowLeft", "left"}, {"ArrowDown", "down"}, {"ArrowUp", "up"},
	{"NumLock", "numlock"},
	{"NumpadDivide", "kp/"}, {"NumpadMultiply", "kp*"}, {"NumpadSubtract", "kp-"},
	{"NumpadAdd", "kp+"}, {"NumpadEnter", "kpenter"}, {"NumpadDecimal", "kp."},
	{"Numpad1", "kp1"}, {"Numpad2", "kp2"}, {"Numpad3", "kp3"}, {"Numpad4", "kp4"},
	{"Numpad5", "kp5"}, {"Numpad6", "kp6"}, {"Numpad7", "kp7"}, {"Numpad8", "kp8"},
	{"Numpad9", "kp9"}, {"Numpad0", "kp0"}, {"NumpadEqual", "kp="},
	{"ControlLeft", "lctrl"}, {"ShiftLeft", "lshift"}, {"AltLeft", "lalt"}, {"MetaLeft", "lgui"},
	{"ControlRight", "rctrl"}, {"ShiftRight", "rshift"}, {"AltRight", "ralt"}, {"MetaRight", "rgui"},
	{"ContextMenu", "menu"},
};

bool domCodeToName(const char *code, const char *&name)
{
	if (!code || !code[0])
		return false;
	for (const CodeName &e : kCodeNames)
	{
		if (std::strcmp(code, e.code) == 0)
		{
			name = e.name;
			return true;
		}
	}
	return false;
}

} // wasi_input
} // love

// ── love.event backend ────────────────────────────────────────────────────────

// The step-6.5 gamepad poll, wired in as a WEAK hook so this 6.4 event backend
// never depends on the joystick module. joystick-backend.cpp (step 6.5) defines
// it STRONG; when that TU is not linked (the 6.4 build), the symbol stays null
// and pump() skips the call — a guarded addition, not a 6.4 behavior change.
extern "C" __attribute__((weak)) void wasi_poll_gamepad_events();

namespace love
{
namespace event
{
namespace wasm
{

using love::keyboard::Keyboard;

Event::Event()
	: love::event::Event("love.event.wasm")
{
}

Event::~Event()
{
}

// Read the fixed record fields (the host writes native LE; wasm32 agrees).
static inline double recDouble(const uint8_t *rec, int off) { double v; std::memcpy(&v, rec + off, 8); return v; }
static inline int32_t recInt(const uint8_t *rec, int off) { int32_t v; std::memcpy(&v, rec + off, 4); return v; }

void Event::pump(float /*waitTimeout*/)
{
	// Poll the browser Gamepad API first (step 6.5), so the synthesized joystick/
	// gamepad Messages land in the same queue this drain feeds. Weak: null (skipped)
	// when the joystick backend is not linked (the 6.4 build).
	if (wasi_poll_gamepad_events)
		wasi_poll_gamepad_events();

	// The rAF-driven browser loop never blocks here: waitTimeout is a desktop
	// busy-wait hint with no browser analog, so we always drain non-blocking.
	auto &st = love::wasi_input::state();

	uint8_t rec[REC_SIZE];
	while (win_input_poll(rec, REC_SIZE) == 1)
	{
		int32_t type = recInt(rec, 32);
		const char *code = reinterpret_cast<const char *>(rec + 48);
		const char *keytext = reinterpret_cast<const char *>(rec + 88);

		std::vector<Variant> vargs;
		vargs.reserve(5);
		Message *msg = nullptr;

		switch (type)
		{
		case EV_KEYDOWN:
		case EV_KEYUP:
		{
			const char *name = "unknown";
			bool mapped = love::wasi_input::domCodeToName(code, name);

			Keyboard::Scancode sc = Keyboard::SCANCODE_UNKNOWN;
			Keyboard::Key key = Keyboard::KEY_UNKNOWN;
			const char *scname = "unknown";
			const char *keyname = "unknown";
			if (mapped)
			{
				if (Keyboard::getConstant(name, sc))
					Keyboard::getConstant(sc, scname);
				if (Keyboard::getConstant(name, key))
					Keyboard::getConstant(key, keyname);
			}

			int32_t repeat = recInt(rec, 36);
			if (type == EV_KEYDOWN)
			{
				// A repeat means the key is already down (state unchanged). Match
				// SDL: drop the extra keypressed unless key-repeat is enabled.
				if (repeat && !st.keyRepeat)
					continue;
				if (sc != Keyboard::SCANCODE_UNKNOWN)
					st.downScancodes.insert((int) sc);
				if (key != Keyboard::KEY_UNKNOWN)
					st.downKeys.insert((uint32_t) key);

				vargs.emplace_back(keyname, std::strlen(keyname));
				vargs.emplace_back(scname, std::strlen(scname));
				vargs.emplace_back(repeat != 0);
				msg = new Message("keypressed", vargs);
			}
			else
			{
				if (sc != Keyboard::SCANCODE_UNKNOWN)
					st.downScancodes.erase((int) sc);
				if (key != Keyboard::KEY_UNKNOWN)
					st.downKeys.erase((uint32_t) key);

				vargs.emplace_back(keyname, std::strlen(keyname));
				vargs.emplace_back(scname, std::strlen(scname));
				msg = new Message("keyreleased", vargs);
			}
			break;
		}
		case EV_TEXTINPUT:
			vargs.emplace_back(keytext, std::strlen(keytext));
			msg = new Message("textinput", vargs);
			break;
		case EV_MOUSEMOVED:
		{
			double x = recDouble(rec, 0), y = recDouble(rec, 8);
			double dx = recDouble(rec, 16), dy = recDouble(rec, 24);
			st.mouseX = x;
			st.mouseY = y;
			vargs.emplace_back(x);
			vargs.emplace_back(y);
			vargs.emplace_back(dx);
			vargs.emplace_back(dy);
			vargs.emplace_back(false); // istouch
			msg = new Message("mousemoved", vargs);
			break;
		}
		case EV_MOUSEPRESSED:
		case EV_MOUSERELEASED:
		{
			double x = recDouble(rec, 0), y = recDouble(rec, 8);
			// DOM button 0/1/2 (left/middle/right) -> LÖVE 1/3/2.
			int32_t dom = recInt(rec, 36);
			int button = dom == 0 ? 1 : dom == 1 ? 3 : dom == 2 ? 2 : dom + 1;
			int32_t clicks = recInt(rec, 40);
			st.mouseX = x;
			st.mouseY = y;
			if (button >= 1 && button <= 32)
			{
				if (type == EV_MOUSEPRESSED)
					st.buttonMask |= (1u << (button - 1));
				else
					st.buttonMask &= ~(1u << (button - 1));
			}
			vargs.emplace_back(x);
			vargs.emplace_back(y);
			vargs.emplace_back((double) button);
			vargs.emplace_back(false); // istouch
			vargs.emplace_back((double) clicks);
			msg = new Message(type == EV_MOUSEPRESSED ? "mousepressed" : "mousereleased", vargs);
			break;
		}
		case EV_WHEEL:
		{
			double wx = recDouble(rec, 0), wy = recDouble(rec, 8);
			const char *dir = recInt(rec, 44) ? "flipped" : "standard";
			vargs.emplace_back(wx);
			vargs.emplace_back(wy);
			vargs.emplace_back(dir, std::strlen(dir));
			msg = new Message("wheelmoved", vargs);
			break;
		}
		case EV_RESIZE:
			vargs.emplace_back((double) recInt(rec, 36));
			vargs.emplace_back((double) recInt(rec, 40));
			msg = new Message("resize", vargs);
			break;
		case EV_FOCUS:
			vargs.emplace_back(recInt(rec, 36) != 0);
			msg = new Message("focus", vargs);
			break;
		case EV_MOUSEFOCUS:
			vargs.emplace_back(recInt(rec, 36) != 0);
			msg = new Message("mousefocus", vargs);
			break;
		case EV_VISIBLE:
			vargs.emplace_back(recInt(rec, 36) != 0);
			msg = new Message("visible", vargs);
			break;
		case EV_QUIT:
			msg = new Message("quit", vargs);
			break;
		default:
			continue;
		}

		if (msg)
		{
			StrongRef<Message> ref(msg, Acquire::NORETAIN);
			push(ref);
		}
	}
}

Message *Event::wait()
{
	// Deprecated blocking wait: no browser analog (the frame loop must not block).
	return nullptr;
}

void Event::clear()
{
	// No OS-side queue to drain (unlike SDL) — just the base in-memory queue.
	love::event::Event::clear();
}

} // wasm
} // event
} // love

// ── love.keyboard backend ─────────────────────────────────────────────────────

namespace love
{
namespace keyboard
{
namespace wasm
{

Keyboard::Keyboard()
	: love::keyboard::Keyboard("love.keyboard.wasm")
{
}

void Keyboard::setKeyRepeat(bool enable) { love::wasi_input::state().keyRepeat = enable; }
bool Keyboard::hasKeyRepeat() const { return love::wasi_input::state().keyRepeat; }

bool Keyboard::isDown(const std::vector<Key> &keylist) const
{
	const auto &down = love::wasi_input::state().downKeys;
	for (Key k : keylist)
		if (down.find((uint32_t) k) != down.end())
			return true;
	return false;
}

bool Keyboard::isScancodeDown(const std::vector<Scancode> &scancodelist) const
{
	const auto &down = love::wasi_input::state().downScancodes;
	for (Scancode s : scancodelist)
		if (down.find((int) s) != down.end())
			return true;
	return false;
}

bool Keyboard::isModifierActive(ModifierKey key) const
{
	// Lock states (num/caps/scroll) and AltGr are toggle/latch states the DOM
	// only surfaces per-event (getModifierState), which this backend does not
	// track between events. Honest false rather than a fabricated latch.
	(void) key;
	preview_warn_once("keyboard.isModifierActive",
		"love.keyboard.isModifierActive always returns false in the browser "
		"(lock-key latch state is not tracked)");
	return false;
}

// Layout-static (US) round-trip through the shared name maps: scancode <-> name
// <-> key. A declared divergence from SDL's live per-layout mapping.
Keyboard::Key Keyboard::getKeyFromScancode(Scancode scancode) const
{
	const char *name = nullptr;
	Key key = KEY_UNKNOWN;
	if (getConstant(scancode, name) && getConstant(name, key))
		return key;
	return KEY_UNKNOWN;
}

Keyboard::Scancode Keyboard::getScancodeFromKey(Key key) const
{
	const char *name = nullptr;
	Scancode sc = SCANCODE_UNKNOWN;
	if (getConstant(key, name) && getConstant(name, sc))
		return sc;
	return SCANCODE_UNKNOWN;
}

void Keyboard::setTextInput(bool enable)
{
	love::wasi_input::state().textInput = enable;
	win_input_set_text_input(enable ? 1 : 0, 0.0, 0.0, 0.0, 0.0);
}

void Keyboard::setTextInput(bool enable, double x, double y, double w, double h)
{
	love::wasi_input::state().textInput = enable;
	win_input_set_text_input(enable ? 1 : 0, x, y, w, h);
}

bool Keyboard::hasTextInput() const { return love::wasi_input::state().textInput; }

bool Keyboard::hasScreenKeyboard() const { return false; }
bool Keyboard::isScreenKeyboardVisible() const { return false; }

} // wasm
} // keyboard
} // love

// ── love.mouse backend ────────────────────────────────────────────────────────

namespace love
{
namespace mouse
{
namespace wasm
{

Cursor::Cursor(SystemCursor sysCursor)
	: cursorType(CURSORTYPE_SYSTEM)
	, systemCursor(sysCursor)
{
}

Cursor::Cursor(CursorType type, SystemCursor sysCursor)
	: cursorType(type)
	, systemCursor(sysCursor)
{
}

void *Cursor::getHandle() const { return nullptr; }
Cursor::CursorType Cursor::getType() const { return cursorType; }
Cursor::SystemCursor Cursor::getSystemType() const { return systemCursor; }

Mouse::Mouse()
	: love::mouse::Mouse("love.mouse.wasm")
{
}

Mouse::~Mouse()
{
}

love::mouse::Cursor *Mouse::newCursor(const std::vector<image::ImageData *> &data, int hotx, int hoty)
{
	(void) data; (void) hotx; (void) hoty;
	// The browser canvas can only show a CSS cursor (a system shape or an image
	// URL). A pixel-data custom cursor is not rendered here; return an honest
	// image-typed cursor that behaves as the default shape.
	preview_warn_once("mouse.newCursor",
		"custom image cursors are not drawn in the browser canvas; the default "
		"cursor shape is used");
	return new Cursor(Cursor::CURSORTYPE_IMAGE, Cursor::CURSOR_ARROW);
}

love::mouse::Cursor *Mouse::getSystemCursor(Cursor::SystemCursor cursortype)
{
	return new Cursor(cursortype);
}

void Mouse::setCursor(love::mouse::Cursor *cursor)
{
	curCursor.set(cursor);
	if (cursor)
		win_input_set_cursor_shape((int32_t) cursor->getSystemType());
}

void Mouse::setCursor()
{
	curCursor.set(nullptr);
	win_input_set_cursor_shape((int32_t) Cursor::CURSOR_ARROW);
}

love::mouse::Cursor *Mouse::getCursor() const { return curCursor.get(); }

bool Mouse::isCursorSupported() const { return true; }

void Mouse::getPosition(double &x, double &y) const
{
	const auto &st = love::wasi_input::state();
	x = st.mouseX;
	y = st.mouseY;
}

void Mouse::setPosition(double x, double y)
{
	auto &st = love::wasi_input::state();
	st.mouseX = x;
	st.mouseY = y;
	win_input_warp(x, y);
}

void Mouse::getGlobalPosition(double &x, double &y, int &displayindex) const
{
	// One canvas, one display: global == local.
	getPosition(x, y);
	displayindex = 0;
}

void Mouse::setVisible(bool visible)
{
	love::wasi_input::state().cursorVisible = visible;
	win_input_set_cursor_visible(visible ? 1 : 0);
}

bool Mouse::isDown(const std::vector<int> &buttons) const
{
	uint32_t mask = love::wasi_input::state().buttonMask;
	for (int b : buttons)
		if (b >= 1 && b <= 32 && (mask & (1u << (b - 1))))
			return true;
	return false;
}

bool Mouse::isVisible() const { return love::wasi_input::state().cursorVisible; }

void Mouse::setGrabbed(bool grab)
{
	// Confining the pointer to the canvas has no direct browser primitive short
	// of Pointer Lock (which is relative mode, a different thing). Honest no-op.
	preview_warn_once("mouse.setGrabbed",
		"love.mouse.setGrabbed has no effect in the browser (pointer confinement "
		"is not available; use setRelativeMode for pointer lock)");
	(void) grab;
}

bool Mouse::isGrabbed() const { return false; }

bool Mouse::setRelativeMode(bool relative)
{
	int32_t ok = win_input_set_relative(relative ? 1 : 0);
	love::wasi_input::state().relativeMode = (ok != 0) && relative;
	return ok != 0;
}

bool Mouse::getRelativeMode() const { return love::wasi_input::state().relativeMode; }

} // wasm
} // mouse
} // love
