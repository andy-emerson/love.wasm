/**
 * love.touch over the browser's TouchEvent API — the wasm backend, the sibling
 * of src/modules/touch/sdl/Touch.{h,cpp}.
 *
 * The shape is upstream's, deliberately. SDL's backend does not poll the OS for
 * touch state; it keeps a vector of live touches that the EVENT layer updates as
 * finger events are converted (touch/sdl/Touch.h says why: SDL's own query
 * functions are updated on another thread, which breaks a game iterating
 * getTouches()). So love::touch::sdl::Touch::onEvent is called from
 * event/sdl/Event.cpp, and getTouches() just returns the vector.
 *
 * This backend keeps exactly that division: the list lives here, and
 * wasi/platform/input-backend.cpp — which is this build's event pump — calls
 * onEvent() as it converts the host's touch records, the same place and for the
 * same reason. That is why love.touch needs no host import of its own: touch
 * arrives as three new event types on the existing love_input record, next to
 * the mouse and keyboard ones, exactly as finger events arrive next to them in
 * an SDL event queue.
 *
 * Coordinates are canvas-backing-store pixels, already converted by the host
 * (the browser reports client coordinates; the host maps them through the
 * bounding rect, the same mapping love.mouse gets). SDL's backend converts from
 * normalized coordinates here instead; the destination is the same, and it is
 * the space love.graphics draws in.
 */
#ifndef LOVE_WASM_TOUCH_BACKEND_H
#define LOVE_WASM_TOUCH_BACKEND_H

#include "common/config.h"
#include "touch/Touch.h"

namespace love
{
namespace touch
{
namespace wasm
{

// What kind of change a record carries. Deliberately this backend's own enum
// rather than the wire tags, so the event format and the module do not have to
// agree on numbers.
enum TouchEvent
{
	TOUCH_DOWN,
	TOUCH_MOVED,
	TOUCH_UP,
};

class Touch final : public love::touch::Touch
{
public:

	Touch();
	virtual ~Touch() {}

	const std::vector<TouchInfo> &getTouches() const override;
	const TouchInfo &getTouch(int64 id) const override;

	// Called by the event pump (input-backend.cpp) as it converts a touch
	// record, mirroring love::touch::sdl::Touch::onEvent.
	void onEvent(TouchEvent type, const TouchInfo &info);

private:

	std::vector<TouchInfo> touches;

}; // Touch

} // wasm
} // touch
} // love

#endif // LOVE_WASM_TOUCH_BACKEND_H
