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

extern "C" int luaopen_love_filesystem(lua_State *L)
{
	return luaL_error(L,
		"love.filesystem is not yet ported to wasm32-wasi "
		"(seam: host-import VFS, build-order step 6)");
}
