// Step-4 (4.1c) link stubs.
//
// love.graphics transitively references a few symbols from modules this build
// does not compile: the love::video::VideoStream and love::audio::Source *type*
// identities (Graphics::newVideo / the Video drawable name them), the
// love.filesystem file-loading helpers (image/font newX-from-file paths), and
// love.thread's luax_checkchannel. The clear/readback witness never exercises
// any of these paths — they exist only so the graphics module LINKS. Real
// implementations arrive with their modules (filesystem step 6, thread step 7);
// the file/channel helpers are loud stubs so a game that DID hit them fails
// clearly rather than silently.
//
// Timer::getTime is real: graphics/Deprecations.cpp calls it unconditionally,
// and timer/Timer.cpp defines it only for LOVE_LINUX/MACOS/WINDOWS (no wasi
// branch), so we supply the POSIX implementation here (wasi-libc has
// clock_gettime) instead of building the timer module.
#include "common/types.h"
#include "common/runtime.h"
#include "audio/Source.h"
#include "video/VideoStream.h"
#include "filesystem/File.h"
#include "filesystem/FileData.h"
#include "filesystem/wrap_Filesystem.h"
#include "thread/Channel.h"
#include "timer/Timer.h"

#include <ctime>

// Deferred-module Type identities. Stub parents (love::Object): the witness
// never RTTI-checks these, and the real modules define the authoritative ones.
namespace love { namespace audio { love::Type Source::type("Source", &Object::type); } }
namespace love { namespace video { love::Type VideoStream::type("VideoStream", &Object::type); } }
namespace love { namespace filesystem { love::Type File::type("File", &Object::type); } }

// love.filesystem file-loading helpers (real module is a step-6 seam). Loud.
namespace love { namespace filesystem {
FileData *luax_getfiledata(lua_State *L, int /*idx*/)
{
	luaL_error(L, "loading files is not available in this preview build (love.filesystem: step 6)");
	return nullptr;
}
bool luax_cangetfiledata(lua_State * /*L*/, int /*idx*/) { return false; }
Data *luax_getdata(lua_State *L, int /*idx*/)
{
	luaL_error(L, "loading files is not available in this preview build (love.filesystem: step 6)");
	return nullptr;
}
} } // love::filesystem

// love.thread channel check (real module is step 7). Loud.
namespace love { namespace thread {
Channel *luax_checkchannel(lua_State *L, int /*idx*/)
{
	luaL_error(L, "love.thread is not available in this preview build (step 7)");
	return nullptr;
}
} } // love::thread

// POSIX Timer::getTime for wasi (Timer.cpp has no wasi branch).
namespace love { namespace timer {
double Timer::getTime()
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (double) t.tv_sec + (double) t.tv_nsec / 1e9;
}
} } // love::timer
