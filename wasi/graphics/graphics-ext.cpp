// Step-4 (4.1c + 4.2) pump extension for the graphics build: preload love (like
// wasi/boot/pump-ext.cpp) and register the two bridges the witnesses drive.
//
// Why a bridge: on desktop, love.window creates the GL context and calls
// Graphics::setMode; that window backend is step-6 work, deliberately not built
// yet. So this ext plays window's one structural role for the witness — call
// setMode against the host's already-current WebGL2 context — then exercises the
// REAL opengl backend. Two bridges: __wasi_gfx_clear_read (4.1c) clears to a
// known colour and reads it back; __wasi_gfx_draw_read (4.2) fills half the
// buffer with a rectangle and reads one pixel inside it and one outside, so the
// witness confirms the primitive is positioned (drawn colour inside, clear
// colour outside), not merely that the buffer is coloured.
//
// One windowless subtlety the draw path exposed: present() guards on isActive(),
// which requires a window, so windowless it early-returns without flushing the
// batched draw. clear() writes the bound FBO directly so 4.1c never noticed;
// 4.2's rectangle only enqueues, so its bridge calls flushBatchedDraws()
// explicitly and reads the still-bound internal backbuffer FBO. The window seam
// (step 6) restores present()'s flush + resolve-to-system-backbuffer path, and
// the Lua wrap over these calls lands then too; the fidelity claim here is the
// backend, not the wrap.
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

// __wasi_gfx_draw_read(dr, dg, db, cr, cg, cb)
//   -> (Rin, Gin, Bin, Ain,  Rout, Gout, Bout, Aout) as 0..255 ints.
// The step-4 (4.2) witness: the first real geometry through the backend. Brings
// the opengl backend up against the current host WebGL2 context, clears the
// whole 4x4 backbuffer to (cr,cg,cb,1), then draws a filled rectangle over only
// the LEFT HALF (x 0->2, full height) in the distinct colour (dr,dg,db,1) —
// exercising the batched-draw path (shader compile + vertex stream +
// glDrawArrays), which the clear-only 4.1c witness never touched. It reads back
// two pixels: one inside the rectangle (left column) and one outside it (right
// column). Recovering the DRAW colour on the left AND the CLEAR colour on the
// right proves the geometry landed where it was rasterised — position, not just
// "something is coloured". The left-half rectangle spans full height, so the
// inside/outside distinction is purely horizontal (x is not flipped between
// LÖVE and glReadPixels), sidestepping the framebuffer Y-flip entirely.
static int w_draw_read(lua_State *L)
{
	double dr = luaL_checknumber(L, 1);
	double dg = luaL_checknumber(L, 2);
	double db = luaL_checknumber(L, 3);
	double cr = luaL_checknumber(L, 4);
	double cg = luaL_checknumber(L, 5);
	double cb = luaL_checknumber(L, 6);

	auto *gfx = Module::getInstance<graphics::Graphics>(Module::M_GRAPHICS);
	if (gfx == nullptr)
		return luaL_error(L, "love.graphics is not registered (require it first)");

	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = 4;
	bb.height = bb.pixelHeight = 4;

	graphics::OptionalColorD clear(ColorD(cr, cg, cb, 1.0));

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(clear, OptionalInt(), OptionalDouble());
		gfx->setColor(Colorf((float) dr, (float) dg, (float) db, 1.0f));
		gfx->rectangle(graphics::Graphics::DRAW_FILL, 0.0f, 0.0f, 2.0f, 4.0f);
		// rectangle() only enqueues into the batched-draw stream; the actual
		// glDrawArrays happens on flush. present() would flush, but it early-
		// returns while windowless (isActive() needs the step-6 window), so we
		// flush explicitly and read the still-bound internal backbuffer FBO —
		// the same FBO the clear witness reads. The window seam restores
		// present()'s resolve-to-system-backbuffer path in step 6.
		gfx->flushBatchedDraws();
	});

	// Left column (x=0): inside the rectangle. Right column (x=3): outside it.
	// y is arbitrary (2) since the rectangle spans the full height.
	unsigned char in[4] = {0, 0, 0, 0};
	unsigned char out[4] = {0, 0, 0, 0};
	glReadPixels(0, 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, in);
	glReadPixels(3, 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, out);

	for (int i = 0; i < 4; i++)
		lua_pushinteger(L, in[i]);
	for (int i = 0; i < 4; i++)
		lua_pushinteger(L, out[i]);
	return 8;
}

extern "C" void pump_open_extensions(lua_State *L)
{
	love::luax_preload(L, luaopen_love, "love");
	lua_register(L, "__wasi_gfx_clear_read", w_clear_read);
	lua_register(L, "__wasi_gfx_draw_read", w_draw_read);
}
