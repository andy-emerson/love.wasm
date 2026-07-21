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

// love-wasi platform seam — build-order step 6.6b. The REDUCED dependency stub
// for the first-frame union build.
//
// wasi/graphics/graphics-deps-stub.cpp (the windowless step-4 graphics build)
// stubbed everything love.graphics links against but that build did not compile:
// filesystem, timer, thread, audio, video. In the 6.6b union build the
// filesystem (real, 6.2), timer (real, 6.6a) modules ARE compiled, so their
// symbols now come from the real TUs — reusing the graphics stub here would
// DUPLICATE File::type, luax_getfiledata/luax_getdata/luax_cangetfiledata,
// and Timer::getTime.
//
// What is still genuinely absent in the frame build is only the audio, video and
// thread module surface love.graphics references at link time but the frame does
// not enable (love.audio/love.video are not ported; love.thread is the step-7
// Workers step). Those three symbols are provided here, honestly:
//   * audio::Source::type / video::VideoStream::type — the RTTI Type objects
//     love.graphics's Video path compares against; never instantiated without the
//     modules, so the definitions suffice.
//   * thread::luax_checkchannel — a loud error: love.thread is not in this build.
#include "common/runtime.h"
#include "audio/Source.h"
#include "video/VideoStream.h"
#include "thread/Channel.h"

namespace love { namespace audio { love::Type Source::type("Source", &Object::type); } }
namespace love { namespace video { love::Type VideoStream::type("VideoStream", &Object::type); } }

namespace love { namespace thread {
Channel *luax_checkchannel(lua_State *L, int /*idx*/)
{
	luaL_error(L, "love.thread is not available in this build (step 7)");
	return nullptr;
}
} } // love::thread
