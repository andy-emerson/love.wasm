/**
 * love.touch over the browser's TouchEvent API. See touch-backend.h for why the
 * list lives here and the event pump drives it.
 */
#include "touch-backend.h"
#include "preview-warn.h"

#include "common/Exception.h"

#include <algorithm>

namespace love
{
namespace touch
{

// touch/Touch.cpp declares this and expects the backend to define it; on desktop
// that is touch/sdl/Touch.cpp, which this build does not compile.
//
// SDL_HINT_TRACKPAD_IS_TOUCH_ONLY asks the OS to deliver trackpad gestures as
// touches rather than as mouse input. A browser exposes no such control: a
// trackpad arrives as MouseEvent and a touchscreen as TouchEvent, and a page
// cannot swap them.
//
// Only `true` is unsatisfiable, and only `true` is reported. `false` — the
// default, and what boot.lua passes for every game that does not set
// t.trackpadtouch — is precisely what a browser already does, so warning on it
// would fire on every boot of every game and say nothing about what the game
// asked for.
void setTrackpadTouchImplementation(bool enable)
{
	if (enable)
		::preview_warn_once("trackpad-touch",
			"t.trackpadtouch has no effect in the browser (a trackpad arrives as "
			"mouse input and a touchscreen as touch input; a page cannot swap them)");
}

namespace wasm
{

Touch::Touch()
	: love::touch::Touch("love.touch.wasm")
{
}

const std::vector<Touch::TouchInfo> &Touch::getTouches() const
{
	return touches;
}

const Touch::TouchInfo &Touch::getTouch(int64 id) const
{
	for (const auto &touch : touches)
	{
		if (touch.id == id)
			return touch;
	}

	throw love::Exception("Invalid active touch ID: %d", id);
}

void Touch::onEvent(TouchEvent type, const TouchInfo &info)
{
	auto compare = [&](const TouchInfo &touch) -> bool
	{
		return touch.id == info.id;
	};

	switch (type)
	{
	case TOUCH_DOWN:
		// Erase first: a browser reuses an identifier once its touch has ended,
		// and a lost touchend (the tab losing focus mid-gesture) would otherwise
		// leave a stale entry that never clears.
		touches.erase(std::remove_if(touches.begin(), touches.end(), compare), touches.end());
		touches.push_back(info);
		break;
	case TOUCH_MOVED:
		for (TouchInfo &touch : touches)
		{
			if (touch.id == info.id)
				touch = info;
		}
		break;
	case TOUCH_UP:
		touches.erase(std::remove_if(touches.begin(), touches.end(), compare), touches.end());
		break;
	}
}

} // wasm
} // touch
} // love
