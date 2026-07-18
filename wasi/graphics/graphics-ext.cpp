// Step-4 (4.1c + 4.2 .. 4.11) pump extension for the graphics build: preload
// love (pump-ext.cpp) and register the witness bridges.
//
// Why a bridge: on desktop, love.window creates the GL context and calls
// Graphics::setMode; that window backend is step-6 work, deliberately not built
// yet. So this ext plays window's one structural role for the witness — call
// setMode against the host's already-current WebGL2 context — then exercises the
// REAL opengl backend. Bridges: __wasi_gfx_clear_read (4.1c) clears to a
// known colour and reads it back; __wasi_gfx_draw_read (4.2) fills half the
// buffer with a rectangle and reads one pixel inside it and one outside, so the
// witness confirms the primitive is positioned (drawn colour inside, clear
// colour outside), not merely that the buffer is coloured; __wasi_gfx_draw_prims
// (4.3) draws the rest of the 2D primitive set — circle, triangle, points,
// line-mode rectangle, polyline — in one frame and reads a covered pixel of each
// back (plus the outline's hollow centre, and a background pixel);
// __wasi_gfx_draw_texture (4.4) uploads a 2x2 four-texel image to a real texture
// and draws it scaled, reading each texel's block back to prove upload + sampler
// + UV mapping; __wasi_gfx_draw_shader (4.5) compiles a user pixel shader that
// inverts the vertex colour and draws with it, proving the glslang -> WebGL2 GLSL
// path runs for shader code that did not ship with the engine; __wasi_gfx_draw_
// canvas (4.6) renders into an off-screen canvas (render-target Texture) and
// samples it back onto the backbuffer, proving the render-to-texture round trip;
// __wasi_gfx_draw_text (4.7) prints text with the embedded default font, proving
// FreeType glyph rasterisation feeds the textured-draw path; __wasi_gfx_draw_
// state (4.8) exercises the cross-cutting render state — additive blend, scissor
// clipping, stencil masking — in one frame, proving each composites/clips draws;
// __wasi_gfx_draw_mesh (4.9) draws a custom-vertex Mesh through a user-owned VBO;
// __wasi_gfx_draw_spritebatch (4.10) batches textured quads (+ a Quad sub-region)
// into one draw; __wasi_gfx_draw_particles (4.11) emits, simulates, and draws a
// ParticleSystem.
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
#include "common/Matrix.h"
#include "graphics/Graphics.h"
#include "graphics/Shader.h"
#include "graphics/Font.h"
#include "graphics/Mesh.h"
#include "graphics/SpriteBatch.h"
#include "graphics/ParticleSystem.h"
#include "graphics/Quad.h"
#include "graphics/vertex.h"
#include "font/TextShaper.h"
#include "font/TrueTypeRasterizer.h"
#include "image/ImageData.h"
#include "libraries/glad/gladfuncs.hpp"

extern "C" int luaopen_love(lua_State *L);

using namespace love;
using namespace glad;

// Fetch the graphics instance for a witness bridge, erroring cleanly if
// love.graphics has not been required yet. luaL_error longjmps out, so on the
// normal path the returned pointer is always non-null.
static graphics::Graphics *witnessGfx(lua_State *L)
{
	auto *gfx = Module::getInstance<graphics::Graphics>(Module::M_GRAPHICS);
	if (gfx == nullptr)
		luaL_error(L, "love.graphics is not registered (require it first)");
	return gfx;
}

// Read `count` LÖVE-space sample points from the bound backbuffer and push each
// as four 0..255 ints. LÖVE space is top-left origin; glReadPixels is bottom-up,
// so y is flipped as H-1-y. Returns count*4 — the number of Lua return values.
static int pushSamples(lua_State *L, int H, const int *sx, const int *sy, int count)
{
	for (int i = 0; i < count; i++)
	{
		unsigned char px[4] = {0, 0, 0, 0};
		glReadPixels(sx[i], H - 1 - sy[i], 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
		for (int j = 0; j < 4; j++)
			lua_pushinteger(L, px[j]);
	}
	return count * 4;
}

// __wasi_gfx_clear_read(r, g, b) -> (R, G, B, A) as 0..255 ints.
// Brings the opengl backend up against the current host WebGL2 context, clears
// the backbuffer to (r,g,b,1), presents, and reads pixel (0,0) back.
static int w_clear_read(lua_State *L)
{
	double r = luaL_checknumber(L, 1);
	double g = luaL_checknumber(L, 2);
	double b = luaL_checknumber(L, 3);

	auto *gfx = witnessGfx(L);

	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = 4;
	bb.height = bb.pixelHeight = 4;

	graphics::OptionalColorD color(ColorD(r, g, b, 1.0));

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(color, OptionalInt(), OptionalDouble());
		gfx->present(nullptr);
	});

	const int sx[1] = {0}, sy[1] = {0}; // uniform clear: any pixel recovers it
	return pushSamples(L, bb.height, sx, sy, 1);
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

	auto *gfx = witnessGfx(L);

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
	// y is arbitrary since the rectangle spans the full height.
	const int sx[2] = {0, 3}, sy[2] = {2, 2};
	return pushSamples(L, bb.height, sx, sy, 2);
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

	auto *gfx = witnessGfx(L);

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
	return pushSamples(L, H, sx, sy, 7);
}

// __wasi_gfx_draw_texture() -> 20 ints: five (R,G,B,A) samples, in this order —
//   texel(0,0) TL, texel(1,0) TR, texel(0,1) BL, texel(1,1) BR, background.
// The step-4 (4.4) witness: the first texture through the backend. It builds a
// 2x2 RGBA8 image with four distinct texels from CPU pixels (image::ImageData ->
// Texture::Slices -> newTexture, which uploads via glTexStorage2D/glTexSubImage),
// sets NEAREST filtering, and draws it scaled 4x over a distinct clear so each
// texel covers a 4x4 block of the 16x16 backbuffer. The constant colour is white
// so the texture's own colour passes through the textured shader unmodified.
// Reading the centre of each block back recovers that texel's colour AND its
// position — proving texture upload, sampler binding, the STANDARD_TEXTURE
// shader, and correct UV mapping (orientation included: texel (0,0) lands
// top-left). A background pixel confirms the clear colour survives off the quad.
// The four texel colours are fixed here and mirrored in witness-texture.lua.
static int w_draw_texture(lua_State *L)
{
	auto *gfx = witnessGfx(L);

	const int W = 16, H = 16;
	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = W; bb.height = bb.pixelHeight = H;
	graphics::OptionalColorD clear(ColorD(0.3, 0.3, 0.3, 1.0)); // (76,76,76)

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(clear, OptionalInt(), OptionalDouble());
		gfx->setColor(Colorf(1, 1, 1, 1)); // white: texture colour passes through

		auto *img = new image::ImageData(2, 2, PIXELFORMAT_RGBA8_UNORM);
		img->setPixel(0, 0, Colorf(0.2f, 0.4f, 0.6f, 1.0f)); // TL (51,102,153)
		img->setPixel(1, 0, Colorf(0.8f, 0.2f, 0.2f, 1.0f)); // TR (204,51,51)
		img->setPixel(0, 1, Colorf(0.2f, 0.6f, 0.2f, 1.0f)); // BL (51,153,51)
		img->setPixel(1, 1, Colorf(0.6f, 0.2f, 0.8f, 1.0f)); // BR (153,51,204)

		graphics::Texture::Slices slices(graphics::TEXTURE_2D);
		slices.set(0, 0, img);
		img->release(); // Slices retains it; drop our creation ref.

		graphics::Texture::Settings st;
		st.width = 2; st.height = 2;
		graphics::Texture *tex = gfx->newTexture(st, &slices);

		graphics::SamplerState ss = tex->getSamplerState();
		ss.minFilter = ss.magFilter = graphics::SamplerState::FILTER_NEAREST;
		tex->setSamplerState(ss);

		Matrix4 m(4.0f, 4.0f, 0.0f, 4.0f, 4.0f, 0.0f, 0.0f, 0.0f, 0.0f); // at (4,4), 4x
		gfx->draw(tex, m);
		gfx->flushBatchedDraws();
		tex->release();
	});

	// Centre of each 4x4 texel block (LÖVE space), plus a background corner.
	const int sx[5] = { 6, 10,  6, 10,  1 };
	const int sy[5] = { 6,  6, 10, 10,  1 };
	return pushSamples(L, H, sx, sy, 5);
}

// __wasi_gfx_draw_shader() -> (Rin, Gin, Bin, Ain,  Rout, Gout, Bout, Aout).
// The step-4 (4.5) witness: the first USER shader through the backend. It
// compiles a LÖVE-GLSL pixel shader whose effect() *inverts* the incoming vertex
// colour (a function of its input, not a constant), sets it active, draws a
// filled rectangle over the left half in setColor (0.8,0.6,0.4), then reads back.
// The left half must be the inverted colour (0.2,0.4,0.6) — proving the custom
// shader was translated by glslang, compiled + linked as real WebGL2 GLSL, bound,
// and actually executed with the vertex colour reaching it — while the right half
// stays the clear colour. If the default shader had run instead, the left half
// would be (0.8,0.6,0.4). The full-height left half sidesteps the Y-flip.
static int w_draw_shader(lua_State *L)
{
	auto *gfx = witnessGfx(L);

	const int W = 16, H = 16;
	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = W; bb.height = bb.pixelHeight = H;
	graphics::OptionalColorD clear(ColorD(0.3, 0.3, 0.3, 1.0)); // (76,76,76)

	const char *pixelsrc =
		"vec4 effect(vec4 vcolor, Image tex, vec2 texcoord, vec2 pixcoord)\n"
		"{\n"
		"    return vec4(1.0 - vcolor.rgb, 1.0);\n"
		"}\n";

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(clear, OptionalInt(), OptionalDouble());

		std::vector<std::string> stages;
		stages.push_back(pixelsrc);
		graphics::Shader::CompileOptions opts;
		graphics::Shader *shader = gfx->newShader(stages, opts);

		gfx->setShader(shader);
		gfx->setColor(Colorf(0.8f, 0.6f, 0.4f, 1.0f)); // inverted by effect() -> (0.2,0.4,0.6)
		gfx->rectangle(graphics::Graphics::DRAW_FILL, 0.0f, 0.0f, 8.0f, 16.0f);
		gfx->flushBatchedDraws();
		gfx->setShader(); // back to the default shader
		shader->release();
	});

	// Left half (x<8): shader output. Right half: clear. Full-height rect, so the
	// exact y is immaterial to the inside/outside split.
	const int sx[2] = {4, 12}, sy[2] = {8, 8};
	return pushSamples(L, H, sx, sy, 2);
}

// __wasi_gfx_draw_canvas() -> 16 ints: four (R,G,B,A) samples, in this order —
//   canvas rect B (top-left), canvas clear A (top-right), canvas clear A
//   (bottom-left), backbuffer background.
// The step-4 (4.6) witness: the first render target. It creates an 8x8 canvas
// (a render-target Texture), switches rendering INTO it (an FBO switch), clears
// it to A and fills its top-left quadrant with B, switches back to the
// backbuffer, then draws the canvas texture onto the backbuffer at 1:1 over a
// distinct background clear. Reading four pixels back proves: render-target
// creation, rendering into a texture then sampling it out (round trip through an
// off-screen FBO), and correct orientation in BOTH axes — B is recovered only at
// the top-left of the canvas region (not flipped), A elsewhere on the canvas,
// and the background clear survives outside it.
static int w_draw_canvas(lua_State *L)
{
	auto *gfx = witnessGfx(L);

	const int W = 16, H = 16;
	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = W; bb.height = bb.pixelHeight = H;
	graphics::OptionalColorD bgclear(ColorD(0.3, 0.3, 0.3, 1.0));     // (76,76,76)
	graphics::OptionalColorD canvasclear(ColorD(0.2, 0.4, 0.6, 1.0)); // A (51,102,153)

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(bgclear, OptionalInt(), OptionalDouble());

		graphics::Texture::Settings st;
		st.width = 8; st.height = 8;
		st.renderTarget = true;
		graphics::Texture *canvas = gfx->newTexture(st, nullptr);

		gfx->setRenderTarget(graphics::Graphics::RenderTarget(canvas), 0);
		gfx->clear(canvasclear, OptionalInt(), OptionalDouble());
		gfx->setColor(Colorf(0.8f, 0.2f, 0.2f, 1.0f)); // B (204,51,51)
		gfx->rectangle(graphics::Graphics::DRAW_FILL, 0.0f, 0.0f, 4.0f, 4.0f); // top-left quadrant
		gfx->flushBatchedDraws();
		gfx->setRenderTarget(); // back to the backbuffer

		gfx->setColor(Colorf(1, 1, 1, 1)); // white: canvas colour passes through
		Matrix4 m(4.0f, 4.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f); // at (4,4), 1:1
		gfx->draw(canvas, m);
		gfx->flushBatchedDraws();
		canvas->release();
	});

	// LÖVE-space samples; the canvas covers (4,4)-(12,12), B its top-left quad.
	const int sx[4] = { 5, 10,  6,  1 };
	const int sy[4] = { 5,  5, 10,  1 };
	return pushSamples(L, H, sx, sy, 4);
}

// __wasi_gfx_draw_text() -> (inkLeft, inkRight,  Rbg, Gbg, Bbg, Abg).
// The step-4 (4.7) witness: the first text — the last major drawing surface. It
// prints "Aj" with the embedded default font (NotoSans) at the top-left of a
// 32x16 backbuffer over a distinct clear, in the ink colour (51,102,153). Text
// is the FreeType rasterizer (a glyph rasterised to a GPU atlas) feeding the
// textured-draw path 4.4 proved — so this exercises real glyph rasterisation,
// the atlas texture, and shaped/positioned glyph quads. Because glyph shapes are
// anti-aliased and font-specific, the witness is coverage-based, not pixel-exact:
// it counts "ink" pixels (blue-dominant, unlike the grey clear) in the left half
// (where the text is) and the right half (which must stay empty), and samples a
// background corner. Real localised coverage + an empty right half + a surviving
// clear background prove the glyphs rasterised and landed where the text was
// drawn — not that a specific pixel took a specific value.
//
// (LA8 note: the glyph atlas's native LA8 format needs texture swizzle, which
// WebGL2 lacks; the OpenGL.cpp pixel-format seam reports LA8 unsupported so the
// atlas falls back to RGBA8 here.)
static int w_draw_text(lua_State *L)
{
	auto *gfx = witnessGfx(L);

	const int W = 32, H = 16;
	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = W; bb.height = bb.pixelHeight = H;
	graphics::OptionalColorD clear(ColorD(0.3, 0.3, 0.3, 1.0)); // (76,76,76)

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(clear, OptionalInt(), OptionalDouble());
		font::TrueTypeRasterizer::Settings fs;
		graphics::Font *font = gfx->newDefaultFont(12, fs);
		gfx->setFont(font);
		gfx->setColor(Colorf(1, 1, 1, 1)); // white; per-glyph colour comes from the string
		std::vector<font::ColoredString> str;
		str.push_back({ "Aj", Colorf(0.2f, 0.4f, 0.6f, 1.0f) }); // ink (51,102,153)
		Matrix4 m(1.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f);
		gfx->print(str, m);
		gfx->flushBatchedDraws();
		font->release();
	});

	unsigned char px[32*16*4];
	glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, px);
	int inkLeft = 0, inkRight = 0;
	for (int y = 0; y < H; y++)
	{
		for (int x = 0; x < W; x++)
		{
			unsigned char *p = &px[(y * W + x) * 4];
			bool ink = ((int)p[2] - (int)p[0]) > 40; // blue-dominant vs grey clear
			if (ink) { if (x < W / 2) inkLeft++; else inkRight++; }
		}
	}
	lua_pushinteger(L, inkLeft);
	lua_pushinteger(L, inkRight);
	unsigned char corner[4] = {0, 0, 0, 0};
	glReadPixels(W - 1, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, corner); // far corner
	for (int j = 0; j < 4; j++) lua_pushinteger(L, corner[j]);
	return 6;
}

// __wasi_gfx_draw_state() -> 20 ints: five (R,G,B,A) samples, in this order —
//   blend result, scissor inside, scissor clipped-out, stencil inside,
//   stencil masked-out.
// The step-4 (4.8) witness: the cross-cutting render state — blend, scissor,
// stencil — exercised in one frame over a distinct grey clear (51,51,51). It
// draws (1) a rectangle top-left with ADDITIVE blend, so the result is grey +
// draw = (153,153,153) not a replace; (2) a full-buffer blue rectangle with a
// SCISSOR set to a 6x6 sub-rect, so blue lands only inside the scissor; and
// (3) a 6x6 STENCIL mask, then a full-buffer red rectangle tested against it, so
// red lands only where the stencil was written. Reading five pixels back proves
// each: the blend sum inside its rect, blue inside the scissor but the clear
// colour just outside it (blue was clipped), red inside the stencil but the
// clear colour just outside it (red was masked). Needs a stencil-capable
// backbuffer (host context depth+stencil; BackbufferSettings.stencil).
static int w_draw_state(lua_State *L)
{
	auto *gfx = witnessGfx(L);

	const int W = 16, H = 16;
	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = W; bb.height = bb.pixelHeight = H;
	bb.stencil = true; bb.depth = true;
	graphics::OptionalColorD clear(ColorD(0.2, 0.2, 0.2, 1.0)); // (51,51,51)

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(clear, OptionalInt(), OptionalDouble());

		// (1) Additive blend, top-left: (0.4,0.4,0.4) added over the grey clear.
		gfx->setBlendMode(graphics::BLEND_ADD, graphics::BLENDALPHA_MULTIPLY);
		gfx->setColor(Colorf(0.4f, 0.4f, 0.4f, 1.0f));
		gfx->rectangle(graphics::Graphics::DRAW_FILL, 1, 1, 6, 6);
		gfx->setBlendMode(graphics::BLEND_ALPHA, graphics::BLENDALPHA_MULTIPLY);

		// (2) Scissor, top-right: full-buffer blue draw clipped to a 6x6 rect.
		gfx->setScissor(FRect{9, 1, 6, 6});
		gfx->setColor(Colorf(0.2f, 0.4f, 0.6f, 1.0f)); // (51,102,153)
		gfx->rectangle(graphics::Graphics::DRAW_FILL, 0, 0, 16, 16);
		gfx->setScissor();

		// (3) Stencil, bottom-left: mark a 6x6 stencil, then full-buffer red
		//     draw tested against it.
		gfx->setStencilMode(graphics::STENCIL_MODE_DRAW, 1);
		gfx->rectangle(graphics::Graphics::DRAW_FILL, 1, 9, 6, 6);
		gfx->setStencilMode(graphics::STENCIL_MODE_TEST, 1);
		gfx->setColor(Colorf(0.8f, 0.2f, 0.4f, 1.0f)); // (204,51,102)
		gfx->rectangle(graphics::Graphics::DRAW_FILL, 0, 0, 16, 16);
		gfx->setStencilMode();

		gfx->flushBatchedDraws();
	});

	// LÖVE-space samples: blend, scissor-in, scissor-out (below its rect),
	// stencil-in, stencil-out (above its rect).
	const int sx[5] = { 3, 11, 11,  3,  3 };
	const int sy[5] = { 3,  3, 10, 11,  7 };
	return pushSamples(L, H, sx, sy, 5);
}

// __wasi_gfx_draw_mesh() -> (Rin, Gin, Bin, Ain,  Rout, Gout, Bout, Aout).
// The step-4 (4.9) witness: the first Mesh — custom vertex geometry through a
// USER-owned vertex buffer, not the batched draw stream. It builds a 3-vertex
// triangle mesh in LÖVE's default vertex format (position + texcoord + per-vertex
// colour), uploads it to a real VBO via newMesh, and draws it. The constant
// colour is white so the mesh's own per-vertex colour (51,102,153) passes
// through. Reading inside the triangle (draw colour) and outside (clear colour)
// proves mesh creation, the custom-format vertex upload, and the mesh draw path.
static int w_draw_mesh(lua_State *L)
{
	auto *gfx = witnessGfx(L);

	const int W = 16, H = 16;
	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = W; bb.height = bb.pixelHeight = H;
	graphics::OptionalColorD clear(ColorD(0.6, 0.4, 0.2, 1.0)); // (153,102,51)

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(clear, OptionalInt(), OptionalDouble());
		gfx->setColor(Colorf(1, 1, 1, 1)); // white: mesh vertex colour passes through

		Color32 c(51, 102, 153, 255);
		graphics::Vertex verts[3] = {
			{  2.0f,  2.0f, 0.0f, 0.0f, c },
			{ 14.0f,  2.0f, 0.0f, 0.0f, c },
			{  8.0f, 14.0f, 0.0f, 0.0f, c },
		};
		auto fmt = graphics::Mesh::getDefaultVertexFormat();
		graphics::Mesh *mesh = gfx->newMesh(fmt, verts, sizeof(verts),
			graphics::PRIMITIVE_TRIANGLES, graphics::BUFFERDATAUSAGE_STATIC);

		Matrix4 m; // identity — mesh drawn in its own coordinates
		gfx->draw(mesh, m);
		gfx->flushBatchedDraws();
		mesh->release();
	});

	const int sx[2] = {8, 1}, sy[2] = {6, 13}; // inside the triangle, then outside it
	return pushSamples(L, H, sx, sy, 2);
}

// Build a 2x2 four-texel NEAREST texture (shared by the spritebatch witness).
static graphics::Texture *makeQuadTexture(graphics::Graphics *gfx)
{
	auto *img = new image::ImageData(2, 2, PIXELFORMAT_RGBA8_UNORM);
	img->setPixel(0, 0, Colorf(0.2f, 0.4f, 0.6f, 1.0f)); // TL (51,102,153)
	img->setPixel(1, 0, Colorf(0.8f, 0.2f, 0.2f, 1.0f)); // TR (204,51,51)
	img->setPixel(0, 1, Colorf(0.2f, 0.6f, 0.2f, 1.0f)); // BL (51,153,51)
	img->setPixel(1, 1, Colorf(0.6f, 0.2f, 0.8f, 1.0f)); // BR (153,51,204)
	graphics::Texture::Slices slices(graphics::TEXTURE_2D);
	slices.set(0, 0, img);
	img->release();
	graphics::Texture::Settings st;
	st.width = 2; st.height = 2;
	graphics::Texture *tex = gfx->newTexture(st, &slices);
	graphics::SamplerState ss = tex->getSamplerState();
	ss.minFilter = ss.magFilter = graphics::SamplerState::FILTER_NEAREST;
	tex->setSamplerState(ss);
	return tex;
}

// __wasi_gfx_draw_spritebatch() -> 16 ints: four (R,G,B,A) samples —
//   sprite-1 texel A (TL), sprite-1 texel D (BR), quad-sprite (TR texel), background.
// The step-4 (4.10) witness: SpriteBatch + Quad. It builds a 2x2 four-texel
// texture, makes a SpriteBatch on it, and adds TWO sprites from ONE batch: a
// full-texture sprite scaled 4x (top-left), and a Quad sprite selecting just the
// texture's top-right texel scaled 4x (lower-right). Drawing the batch once and
// reading back proves batched textured-quad drawing (multiple sprites, one draw),
// per-sprite transforms (the two land in different places), and Quad sub-region
// sampling (the quad sprite is pure TR colour, not the whole texture).
static int w_draw_spritebatch(lua_State *L)
{
	auto *gfx = witnessGfx(L);

	const int W = 16, H = 16;
	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = W; bb.height = bb.pixelHeight = H;
	graphics::OptionalColorD clear(ColorD(0.3, 0.3, 0.3, 1.0)); // (76,76,76)

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(clear, OptionalInt(), OptionalDouble());
		gfx->setColor(Colorf(1, 1, 1, 1));

		graphics::Texture *tex = makeQuadTexture(gfx);
		graphics::SpriteBatch *sb = gfx->newSpriteBatch(tex, 8, graphics::BUFFERDATAUSAGE_STATIC);
		sb->setColor(Colorf(1, 1, 1, 1));

		Matrix4 m1(1.0f, 1.0f, 0.0f, 4.0f, 4.0f, 0, 0, 0, 0); // full texture, top-left, 4x
		sb->add(m1);
		graphics::Quad *q = gfx->newQuad(graphics::Quad::Viewport{1.0, 0.0, 1.0, 1.0}, 2, 2); // TR texel
		Matrix4 m2(9.0f, 9.0f, 0.0f, 4.0f, 4.0f, 0, 0, 0, 0); // quad sprite, lower-right, 4x
		sb->add(q, m2);
		q->release();

		gfx->draw(sb, Matrix4());
		gfx->flushBatchedDraws();
		sb->release();
		tex->release();
	});

	const int sx[4] = { 3,  7, 11, 14 };
	const int sy[4] = { 3,  7, 11,  2 };
	return pushSamples(L, H, sx, sy, 4);
}

// __wasi_gfx_draw_particles() -> (Rin, Gin, Bin, Ain,  Rout, Gout, Bout, Aout).
// The step-4 (4.11) witness: ParticleSystem — emit, simulate, draw. It builds a
// solid (51,102,153) particle texture, creates a ParticleSystem, emits 8
// long-lived particles at the centre with zero speed/spread (so they stack into a
// deterministic blob instead of scattering), advances the sim one frame with
// update(), and draws it. Reading the blob centre (particle colour) and a corner
// (clear colour) proves the particle system emits, updates, and renders its
// particles as textured quads. Chromium only.
static int w_draw_particles(lua_State *L)
{
	auto *gfx = witnessGfx(L);

	const int W = 16, H = 16;
	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = W; bb.height = bb.pixelHeight = H;
	graphics::OptionalColorD clear(ColorD(0.3, 0.3, 0.3, 1.0)); // (76,76,76)

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(clear, OptionalInt(), OptionalDouble());
		gfx->setColor(Colorf(1, 1, 1, 1));

		auto *img = new image::ImageData(2, 2, PIXELFORMAT_RGBA8_UNORM);
		for (int y = 0; y < 2; y++) for (int x = 0; x < 2; x++)
			img->setPixel(x, y, Colorf(0.2f, 0.4f, 0.6f, 1.0f)); // solid (51,102,153)
		graphics::Texture::Slices slices(graphics::TEXTURE_2D);
		slices.set(0, 0, img); img->release();
		graphics::Texture::Settings st; st.width = 2; st.height = 2;
		graphics::Texture *tex = gfx->newTexture(st, &slices);

		graphics::ParticleSystem *ps = gfx->newParticleSystem(tex, 64);
		ps->setParticleLifetime(100.0f, 100.0f);   // long-lived
		ps->setPosition(8.0f, 8.0f);               // emit at centre
		ps->setSpeed(0.0f);                         // no movement -> deterministic blob
		ps->setSpread(0.0f);
		ps->setSizes(std::vector<float>{ 2.0f });   // 2x2 texture * 2 = ~4x4 blob
		ps->emit(8);
		ps->update(0.016f);                         // advance the simulation one frame
		gfx->draw(ps, Matrix4());
		gfx->flushBatchedDraws();
		ps->release();
		tex->release();
	});

	const int sx[2] = {7, 2}, sy[2] = {7, 2}; // inside the particle blob, then corner background
	return pushSamples(L, H, sx, sy, 2);
}

// __wasi_gfx_draw_transform() -> 16 ints: four (R,G,B,A) samples —
//   translate quad, scale quad, rotate(pi) quad, background.
// The step-4 (4.12) witness: the coordinate-system transform stack — the first
// of the compose-only API tail. Every prior witness drew in identity space; this
// drives push/translate/scale/rotate/pop and reads back where each draw landed.
// Three unit rectangles are each drawn inside a push/pop pair with a different
// transform: translate(8,8) puts one at (8..12,8..12); scale(4,4) blows a 1x1 up
// to (0..4,0..4); translate(16,16)+rotate(pi) (180°, direction-agnostic) lands a
// 4x4 at (12..16,12..16). Because each op is push/pop wrapped, the SECOND draw
// landing at the origin (not offset by the first translate) also proves pop
// restored the stack to identity. Reads recover each quad's colour at its
// predicted place plus an untouched background pixel.
static int w_draw_transform(lua_State *L)
{
	auto *gfx = witnessGfx(L);

	const int W = 16, H = 16;
	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = W; bb.height = bb.pixelHeight = H;
	graphics::OptionalColorD clear(ColorD(0.3, 0.3, 0.3, 1.0)); // (76,76,76)

	const float PI = 3.14159265358979f;

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(clear, OptionalInt(), OptionalDouble());

		gfx->push(graphics::Graphics::STACK_TRANSFORM);
		gfx->translate(8.0f, 8.0f);
		gfx->setColor(Colorf(0.2f, 0.4f, 0.6f, 1.0f)); // (51,102,153)
		gfx->rectangle(graphics::Graphics::DRAW_FILL, 0.0f, 0.0f, 4.0f, 4.0f);
		gfx->pop();

		gfx->push(graphics::Graphics::STACK_TRANSFORM);
		gfx->scale(4.0f, 4.0f);
		gfx->setColor(Colorf(0.8f, 0.2f, 0.2f, 1.0f)); // (204,51,51)
		gfx->rectangle(graphics::Graphics::DRAW_FILL, 0.0f, 0.0f, 1.0f, 1.0f);
		gfx->pop();

		gfx->push(graphics::Graphics::STACK_TRANSFORM);
		gfx->translate(16.0f, 16.0f);
		gfx->rotate(PI);
		gfx->setColor(Colorf(0.2f, 0.6f, 0.2f, 1.0f)); // (51,153,51)
		gfx->rectangle(graphics::Graphics::DRAW_FILL, 0.0f, 0.0f, 4.0f, 4.0f);
		gfx->pop();

		gfx->flushBatchedDraws();
	});

	// translate quad, scale quad, rotate quad, background — all LÖVE-space.
	const int sx[4] = { 10, 1, 14, 6 };
	const int sy[4] = { 10, 1, 14, 2 };
	return pushSamples(L, H, sx, sy, 4);
}

// __wasi_gfx_draw_mrt() -> 12 ints: three (R,G,B,A) samples —
//   target-0 colour, target-1 colour, background.
// The step-4 (4.13) witness: multiple render targets — a distinct backend
// mechanism (several colour attachments on one FBO + glDrawBuffers, and a shader
// with multiple outputs), not just composing proven paths. Two 8x8 render-target
// textures are bound together with setRenderTargets, and ONE draw of an MRT pixel
// shader (void effect() writing love_Canvases[0] and love_Canvases[1] to two
// distinct colours) fills both. Unbound, each target is then drawn onto the
// backbuffer side by side and read back: target 0 recovering its colour AND
// target 1 recovering its DIFFERENT colour from that single draw proves the two
// attachments received independent shader outputs. Chromium only.
static int w_draw_mrt(lua_State *L)
{
	auto *gfx = witnessGfx(L);

	const int W = 16, H = 16;
	graphics::Graphics::BackbufferSettings bb;
	bb.width = bb.pixelWidth = W; bb.height = bb.pixelHeight = H;
	graphics::OptionalColorD clear(ColorD(0.3, 0.3, 0.3, 1.0)); // (76,76,76)

	const char *mrtsrc =
		"void effect()\n"
		"{\n"
		"    love_Canvases[0] = vec4(0.2, 0.4, 0.6, 1.0);\n" // (51,102,153)
		"    love_Canvases[1] = vec4(0.8, 0.2, 0.2, 1.0);\n" // (204,51,51)
		"}\n";

	luax_catchexcept(L, [&]() {
		gfx->setMode(nullptr, bb);
		gfx->clear(clear, OptionalInt(), OptionalDouble());

		graphics::Texture::Settings st;
		st.width = 8; st.height = 8; st.renderTarget = true;
		graphics::Texture *ca = gfx->newTexture(st, nullptr);
		graphics::Texture *cb = gfx->newTexture(st, nullptr);

		graphics::Graphics::RenderTargets rts;
		rts.colors.push_back(graphics::Graphics::RenderTarget(ca));
		rts.colors.push_back(graphics::Graphics::RenderTarget(cb));
		gfx->setRenderTargets(rts);

		std::vector<std::string> stages;
		stages.push_back(mrtsrc);
		graphics::Shader::CompileOptions opts;
		graphics::Shader *sh = gfx->newShader(stages, opts);
		gfx->setShader(sh);
		gfx->setColor(Colorf(1, 1, 1, 1));
		gfx->rectangle(graphics::Graphics::DRAW_FILL, 0.0f, 0.0f, 8.0f, 8.0f); // fill both targets
		gfx->flushBatchedDraws();
		gfx->setShader();
		gfx->setRenderTarget(); // back to the backbuffer

		gfx->setColor(Colorf(1, 1, 1, 1)); // white: canvas colour passes through
		Matrix4 ma(0.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f); // target 0 -> left
		gfx->draw(ca, ma);
		Matrix4 mb(8.0f, 0.0f, 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f); // target 1 -> right
		gfx->draw(cb, mb);
		gfx->flushBatchedDraws();
		sh->release(); ca->release(); cb->release();
	});

	// target-0 (left, 51,102,153), target-1 (right, 204,51,51), background below.
	const int sx[3] = { 4, 12, 4 };
	const int sy[3] = { 4,  4, 12 };
	return pushSamples(L, H, sx, sy, 3);
}

extern "C" void pump_open_extensions(lua_State *L)
{
	love::luax_preload(L, luaopen_love, "love");
	lua_register(L, "__wasi_gfx_draw_mrt", w_draw_mrt);
	lua_register(L, "__wasi_gfx_draw_transform", w_draw_transform);
	lua_register(L, "__wasi_gfx_draw_particles", w_draw_particles);
	lua_register(L, "__wasi_gfx_clear_read", w_clear_read);
	lua_register(L, "__wasi_gfx_draw_read", w_draw_read);
	lua_register(L, "__wasi_gfx_draw_prims", w_draw_prims);
	lua_register(L, "__wasi_gfx_draw_texture", w_draw_texture);
	lua_register(L, "__wasi_gfx_draw_shader", w_draw_shader);
	lua_register(L, "__wasi_gfx_draw_canvas", w_draw_canvas);
	lua_register(L, "__wasi_gfx_draw_text", w_draw_text);
	lua_register(L, "__wasi_gfx_draw_state", w_draw_state);
	lua_register(L, "__wasi_gfx_draw_mesh", w_draw_mesh);
	lua_register(L, "__wasi_gfx_draw_spritebatch", w_draw_spritebatch);
}
