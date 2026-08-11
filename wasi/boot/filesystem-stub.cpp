// love.filesystem seam stub — build-order step 3.
//
// The real love.filesystem for this target is a host-import VFS backed by
// the IDE's project storage (readme.md; PhysFS is replaced at the seam,
// build-order step 6). Until that lands, requiring it fails with THIS
// message — the boot witness asserts it verbatim, so the stop-line of the
// boot sequence is a documented fact, not an accident. boot.lua's
// love.boot() hits this on its first line ("This is absolutely needed."),
// which is exactly where step 3 ends and step 6 begins.
#include "common/runtime.h"
#include "common/Data.h"

extern "C" int luaopen_love_filesystem(lua_State *L)
{
	return luaL_error(L,
		"love.filesystem is not yet ported to wasm32-wasi "
		"(seam: host-import VFS, build-order step 6)");
}

// luax_cangetdata is a love::filesystem utility other modules call to decide
// whether a Lua value can be turned into Data (love.audio's newSource uses it).
// The real version also accepts a filesystem File; this build has no File type
// (the module is a seam stub), and a File cannot exist without the module, so
// the honest domain here is exactly string-or-Data — no silent File pretence.
namespace love
{
namespace filesystem
{

bool luax_cangetdata(lua_State *L, int idx)
{
	return lua_isstring(L, idx) || luax_istype(L, idx, love::Data::type);
}

} // filesystem
} // love
