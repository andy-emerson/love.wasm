// Step-4 (4.1c) pump extension for the graphics build: preload love (like
// wasi/boot/pump-ext.cpp) and register the bridge the witness drives.
//
// Why a bridge: on desktop, love.window creates the GL context and calls
// Graphics::setMode; that window backend is step-6 work, deliberately not built
// yet (verified: setMode/clear don't need a window — isActive() is only a Lua
// query, never a render guard). So this ext plays window's one structural role
// for the witness — call setMode against the host's already-current WebGL2
// context — then exercises the REAL opengl backend: clear to a known color,
// present, and read the pixel back via glReadPixels. It drives the actual
// engine Graphics::setMode/clear/present (the Lua wrap over these lands with the
// window seam in step 6); the fidelity claim here is the backend, not the wrap.
#include "common/runtime.h"
#include "common/Color.h"
#include "common/Optional.h"
#include "graphics/Graphics.h"
#include "libraries/glad/gladfuncs.hpp"

extern "C" int luaopen_love(lua_State *L);

using namespace love;
using namespace glad;

// __wasi_gfx_clear_read(r, g, b) -> (R, G, B, A) as 0..255 ints.
// Brings the opengl backend up against the current host WebGL2 context, clears
// the backbuffer to (r,g,b,1), presents, and reads pixel (0,0) back.
static int w_clear_read(lua_State *L)
{
	double r = luaL_checknumber(L, 1);
	double g = luaL_checknumber(L, 2);
	double b = luaL_checknumber(L, 3);

	auto *gfx = Module::getInstance<graphics::Graphics>(Module::M_GRAPHICS);
	if (gfx == nullptr)
		return luaL_error(L, "love.graphics is not registered (require it first)");

	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = 4;
	bb.height = bb.pixelHeight = 4;

	graphics::OptionalColorD color(ColorD(r, g, b, 1.0));

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(color, OptionalInt(), OptionalDouble());
		gfx->present(nullptr);
	});

	unsigned char px[4] = {0, 0, 0, 0};
	glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);

	for (int i = 0; i < 4; i++)
		lua_pushinteger(L, px[i]);
	return 4;
}

extern "C" void pump_open_extensions(lua_State *L)
{
	love::luax_preload(L, luaopen_love, "love");
	lua_register(L, "__wasi_gfx_clear_read", w_clear_read);
}
