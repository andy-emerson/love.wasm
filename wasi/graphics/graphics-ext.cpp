// Step-4 (4.1c + 4.2 + 4.3) pump extension for the graphics build: preload love
// (like wasi/boot/pump-ext.cpp) and register the bridges the witnesses drive.
//
// Why a bridge: on desktop, love.window creates the GL context and calls
// Graphics::setMode; that window backend is step-6 work, deliberately not built
// yet. So this ext plays window's one structural role for the witness — call
// setMode against the host's already-current WebGL2 context — then exercises the
// REAL opengl backend. Three bridges: __wasi_gfx_clear_read (4.1c) clears to a
// known colour and reads it back; __wasi_gfx_draw_read (4.2) fills half the
// buffer with a rectangle and reads one pixel inside it and one outside, so the
// witness confirms the primitive is positioned (drawn colour inside, clear
// colour outside), not merely that the buffer is coloured; __wasi_gfx_draw_prims
// (4.3) draws the rest of the 2D primitive set — circle, triangle, points,
// line-mode rectangle, polyline — in one frame and reads a covered pixel of each
// back (plus the outline's hollow centre, and a background pixel).
//
// One windowless subtlety the draw path exposed: present() guards on isActive(),
// which requires a window, so windowless it early-returns without flushing the
// batched draw OR advancing the frame (nextFrame(), which orphans the streaming
// vertex/index buffers). clear() writes the bound FBO directly so 4.1c never
// noticed; 4.2/4.3 enqueue geometry, so their bridges call flushBatchedDraws()
// explicitly and read the still-bound internal backbuffer FBO. Because the frame
// never advances, all of a witness's geometry must be drawn between ONE
// setMode+clear and ONE flush (the real per-frame shape) — clearing between
// draws would strand the un-orphaned stream buffers mid-frame. The window seam
// (step 6) restores present()'s flush + resolve + nextFrame path, and the Lua
// wrap over these calls lands then too; the fidelity claim here is the backend,
// not the wrap.
#include "common/runtime.h"
#include "common/Color.h"
#include "common/Optional.h"
#include "common/Vector.h"
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


// __wasi_gfx_draw_prims(dr, dg, db, cr, cg, cb)
//   -> 28 ints: seven (R,G,B,A) samples, in this order —
//      circle-fill, points, triangle-fill, rect-outline-stroke,
//      rect-outline-hollow, polyline, background.
// The step-4 (4.3) witness: the rest of the 2D primitive set, all in ONE frame.
// 4.2 drew a single filled rectangle; 4.3 confirms the fill path generalises to a
// high-vertex fan (circle) and an arbitrary triangle, that the distinct STROKE
// path (LÖVE builds its own quad/join geometry for outlines and lines) draws, and
// that points draw with gl_PointSize — every remaining primitive category.
//
// One frame, on purpose: LÖVE streams all of a frame's geometry into shared
// vertex/index StreamBuffers and only orphans them at present() (nextFrame()).
// present() early-returns while windowless, so the witness must draw every
// primitive between a single setMode+clear and a single flush — exactly the
// per-frame shape real LÖVE uses — rather than clearing between draws (which
// would strand the un-orphaned buffers mid-frame). The five primitives are drawn
// in five corners of a 16x16 backbuffer in the draw colour over a distinct clear,
// then representative pixels are read back: one the shape must cover, plus the
// hollow centre of the line-mode rectangle (must stay the clear colour, proving
// outline not fill) and one untouched background pixel. Lines are LINE_ROUGH (no
// AA feathering) so covered pixels are the exact draw colour. Read coords are
// LÖVE-space (top-left origin); glReadPixels is bottom-up, hence H-1-y.
static int w_draw_prims(lua_State *L)
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

	const int W = 16, H = 16;
	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = W;
	bb.height = bb.pixelHeight = H;

	graphics::OptionalColorD clear(ColorD(cr, cg, cb, 1.0));

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(clear, OptionalInt(), OptionalDouble());
		gfx->setColor(Colorf((float) dr, (float) dg, (float) db, 1.0f));
		gfx->setLineStyle(graphics::Graphics::LINE_ROUGH);
		gfx->setLineWidth(2.0f);
		gfx->setPointSize(2.0f);

		// Five primitives, five regions of the 16x16 backbuffer, one frame.
		gfx->circle(graphics::Graphics::DRAW_FILL, 4, 4, 2);                       // top-left
		{ Vector2 v[3] = { Vector2(12,2), Vector2(10,6), Vector2(14,6) };
		  gfx->polygon(graphics::Graphics::DRAW_FILL, v, 3, false); }              // top-right
		{ Vector2 p[1] = { Vector2(9,3) }; gfx->points(p, nullptr, 1); }           // top-middle
		gfx->rectangle(graphics::Graphics::DRAW_LINE, 2, 10, 4, 4);               // bottom-left (outline)
		{ Vector2 v[2] = { Vector2(10,12), Vector2(14,12) }; gfx->polyline(v, 2); } // bottom-right

		gfx->flushBatchedDraws();
	});

	// Seven LÖVE-space sample points; y flipped for glReadPixels (bottom-up).
	const int sx[7] = { 4,  9, 12,  3,  3, 11,  8 };
	const int sy[7] = { 4,  3,  4,  9, 11, 11,  8 };
	for (int i = 0; i < 7; i++)
	{
		unsigned char px[4] = {0, 0, 0, 0};
		glReadPixels(sx[i], H - 1 - sy[i], 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
		for (int j = 0; j < 4; j++)
			lua_pushinteger(L, px[j]);
	}
	return 28;
}

extern "C" void pump_open_extensions(lua_State *L)
{
	love::luax_preload(L, luaopen_love, "love");
	lua_register(L, "__wasi_gfx_clear_read", w_clear_read);
	lua_register(L, "__wasi_gfx_draw_read", w_draw_read);
	lua_register(L, "__wasi_gfx_draw_prims", w_draw_prims);
}
