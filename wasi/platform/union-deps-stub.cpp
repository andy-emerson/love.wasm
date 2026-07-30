// love-wasi platform seam — the UNION "real game" build's reduced dependency stub.
//
// Forked from frame-deps-stub.cpp. The frame build stubbed the audio, video and
// thread module symbols love.graphics references at link time but the frame did
// not enable. The union build LINKS real love.audio (Source::type is now the real
// TU's — stubbing it here would DUPLICATE it), so only video and thread remain
// genuinely absent and stubbed:
//   * video::VideoStream::type — the RTTI Type object love.graphics's Video path
//     compares against; never instantiated without love.video, so the definition
//     suffices.
//   * thread::luax_checkchannel — a loud error: love.thread is not in this build
//     (it is the step-7 Web Workers step).
#include "common/runtime.h"
#include "video/VideoStream.h"
#include "thread/Channel.h"

namespace love { namespace video { love::Type VideoStream::type("VideoStream", &Object::type); } }

namespace love { namespace thread {
Channel *luax_checkchannel(lua_State *L, int /*idx*/)
{
	luaL_error(L, "love.thread is not available in this build (step 7)");
	return nullptr;
}
} } // love::thread
