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

// love-wasi platform seam — build-order step 6.4: the real love.event /
// love.keyboard / love.mouse backends for wasm32-wasi, on the host-import
// love_input seam. They replace the three SDL backends (which poll a native
// OS event loop the browser has no access to) with backends fed by DOM events
// the host forwards.
//
// The DIRECTION is what is new here. Every prior seam (fs, window, gl, audio)
// is guest->host PULL: the guest asks synchronously and the host answers. Input
// is host->guest PUSH: DOM key/pointer events fire on the browser event loop,
// the host QUEUES them, and love.event::wasm::Event::pump() drains that queue
// once per frame (exactly where the SDL backend calls SDL_PeepEvents), turning
// each record into a love::event::Message the unchanged Lua dispatch in
// callbacks.lua fires as love.keypressed / love.mousepressed / ... .
//
// The three modules share one piece of state (the InputState below): pump()
// is the single writer — it maintains the pressed-key/scancode sets, the mouse
// position, and the button mask as it drains — and the keyboard/mouse backends
// are pure readers of it, the same split SDL has (SDL_PumpEvents updates the
// state that SDL_GetKeyboardState / SDL_GetMouseState read). So love.keyboard
// .isDown and love.mouse.getPosition reflect exactly what the last pump saw.
//
// The DOM<->LÖVE name mapping lives here, in C++, next to LÖVE's own Key /
// Scancode enums (not in the host): the host forwards browser truth (the raw
// DOM event.code / event.key strings) and this backend translates it to LÖVE
// truth, mirroring how the graphics host forwards GL while the opengl backend
// owns LÖVE's semantics. The translation is US-layout-static (physical
// event.code -> the default US key), a declared, documented divergence from
// SDL's live-layout mapping; the actual typed character still rides through
// faithfully as the textinput event's payload (DOM event.key).
//
// This header lives out-of-tree (readme.md: the src tree stays upstream-shaped);
// wrap_Event.cpp / wrap_Keyboard.cpp / wrap_Mouse.cpp each include it under
// LOVE_WASI via -I wasi/platform and construct the wasm:: type in place of the
// sdl:: one at their one guarded factory.
#ifndef LOVE_WASI_PLATFORM_INPUT_BACKEND_H
#define LOVE_WASI_PLATFORM_INPUT_BACKEND_H

#include "common/config.h"
#include "event/Event.h"
#include "keyboard/Keyboard.h"
#include "mouse/Mouse.h"
#include "mouse/Cursor.h"

#include <cstdint>
#include <set>
#include <string>
#include <vector>

namespace love
{
namespace wasi_input
{

// The single shared input snapshot. love::event::wasm::Event::pump() is the ONLY
// writer; the keyboard and mouse backends read it. (Kept process-global rather
// than threaded through the three singletons because that is exactly the
// lifetime SDL's backend assumes — one input device set for the one VM.)
struct InputState
{
	std::set<int> downScancodes; // love::keyboard::Keyboard::Scancode values
	std::set<uint32_t> downKeys; // love::keyboard::Keyboard::Key values

	double mouseX = 0.0;
	double mouseY = 0.0;
	uint32_t buttonMask = 0; // bit (button-1): bit0=left(1), bit1=right(2), bit2=middle(3)

	bool keyRepeat = false;      // love.keyboard.setKeyRepeat
	bool textInput = false;      // love.keyboard.setTextInput
	bool cursorVisible = true;   // love.mouse.setVisible
	bool relativeMode = false;   // love.mouse.setRelativeMode / pointer lock
};

InputState &state();

// DOM event.code (physical) -> the LÖVE name shared by the Scancode and, on the
// default US layout, the Key (see header note). Returns false for codes with no
// LÖVE counterpart, leaving the caller to report "unknown".
bool domCodeToName(const char *code, const char *&name);

} // wasi_input

namespace event
{
namespace wasm
{

class Event final : public love::event::Event
{
public:

	Event();
	virtual ~Event();

	void pump(float waitTimeout = 0.0f) override;
	Message *wait() override;
	void clear() override;

}; // Event

} // wasm
} // event

namespace keyboard
{
namespace wasm
{

class Keyboard final : public love::keyboard::Keyboard
{
public:

	Keyboard();
	virtual ~Keyboard() {}

	void setKeyRepeat(bool enable) override;
	bool hasKeyRepeat() const override;

	bool isDown(const std::vector<Key> &keylist) const override;
	bool isScancodeDown(const std::vector<Scancode> &scancodelist) const override;

	bool isModifierActive(ModifierKey key) const override;

	Key getKeyFromScancode(Scancode scancode) const override;
	Scancode getScancodeFromKey(Key key) const override;

	void setTextInput(bool enable) override;
	void setTextInput(bool enable, double x, double y, double w, double h) override;
	bool hasTextInput() const override;

	bool hasScreenKeyboard() const override;
	bool isScreenKeyboardVisible() const override;

}; // Keyboard

} // wasm
} // keyboard

namespace mouse
{
namespace wasm
{

class Cursor final : public love::mouse::Cursor
{
public:

	Cursor(SystemCursor systemCursor);
	Cursor(CursorType type, SystemCursor systemCursor);
	virtual ~Cursor() {}

	void *getHandle() const override;
	CursorType getType() const override;
	SystemCursor getSystemType() const override;

private:

	CursorType cursorType;
	SystemCursor systemCursor;

}; // Cursor

class Mouse final : public love::mouse::Mouse
{
public:

	Mouse();
	virtual ~Mouse();

	love::mouse::Cursor *newCursor(const std::vector<image::ImageData *> &data, int hotx, int hoty) override;
	love::mouse::Cursor *getSystemCursor(Cursor::SystemCursor cursortype) override;

	void setCursor(love::mouse::Cursor *cursor) override;
	void setCursor() override;
	love::mouse::Cursor *getCursor() const override;

	bool isCursorSupported() const override;

	void getPosition(double &x, double &y) const override;
	void setPosition(double x, double y) override;
	void getGlobalPosition(double &x, double &y, int &displayindex) const override;
	void setVisible(bool visible) override;
	bool isDown(const std::vector<int> &buttons) const override;
	bool isVisible() const override;
	void setGrabbed(bool grab) override;
	bool isGrabbed() const override;
	bool setRelativeMode(bool relative) override;
	bool getRelativeMode() const override;

private:

	StrongRef<love::mouse::Cursor> curCursor;

}; // Mouse

} // wasm
} // mouse
} // love

#endif // LOVE_WASI_PLATFORM_INPUT_BACKEND_H
