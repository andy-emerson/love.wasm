#pragma once

// love.shim — registering the inbound compatibility tier (D21) into the artifact.
//
// WHY A HEADER. The pump's link-time extension point, pump_open_extensions(), is
// implemented once per artifact family — wasi/boot/pump-ext.cpp,
// wasi/platform/fs-ext.cpp, wasi/audio/audio-ext.cpp and
// wasi/graphics/graphics-ext.cpp — and exactly one is linked into any given
// build. The shim has to be registered in all four or it is absent from
// whichever artifact you happen to be running, which is precisely the failure
// this file exists to prevent: love.shim was a name in a conversation before it
// was a module, and a witness that injected its own copy could not tell.
// One header, four call sites, no copies of the logic.
//
// WHY NOT src/modules/love/love.cpp. That file's module table is where `love`
// and `love.boot` are registered, and it is shared upstream source. Registering
// there would be a twelfth guarded seam for something upstream has no part in.
// The pump extension point is love.wasm's own, and is already defined as "what
// this artifact preloads".
//
// WHY EMBEDDED RATHER THAN HOST-SUPPLIED. D21 asks for a module peer to the
// other love.* modules, and P2 wants consumers to carry as little as possible.
// Embedding means a consumer gets the shim by instantiating the artifact and
// carries no Lua of ours to get it.
//
// HOW THE .lua BECOMES A C STRING. Upstream's own trick, unchanged: the Lua file
// opens with a C++ raw-string delimiter of luastring"-- and closes with its
// match (see src/modules/love/boot.lua), so ONE file is both the Lua source and
// an includable C string. No generator, and no second copy to drift.

// DEPENDS ON LUA ONLY, deliberately. An earlier revision included
// "common/runtime.h" for love::luax_preload and broke wasi/platform/build.sh —
// the step-6.1 love_fs seam artifact, which compiles fs-ext.cpp with only
// -I$LUA because that TU is Lua-and-imports and nothing more. CI caught it;
// reading would not have, since the other three ext files do carry -I$SRC.
//
// So this header includes lua.hpp, as fs-ext.cpp itself does, and inlines what
// luax_preload does (common/runtime.cpp:479) rather than linking to it. Four
// lines of stack manipulation is a cheaper dependency than a header that only
// three of the four call sites can see.
#include "lua.hpp"

namespace love_wasm_shim
{

static const char shim_lua[] =
#include "love-shim.lua"
;

// The chunk name is load-bearing, not cosmetic: the witness asserts on it to
// prove the module came from the artifact rather than from anything the harness
// injected. Changing it breaks that check, which is the intent.
inline int open(lua_State *L)
{
	if (luaL_loadbuffer(L, shim_lua, sizeof(shim_lua) - 1, "=[love.wasm \"shim.lua\"]") == 0)
		lua_call(L, 0, 1);
	return 1;
}

// love::luax_preload, inlined — see the note above on why this does not call it.
inline void preload(lua_State *L)
{
	lua_getglobal(L, "package");
	lua_getfield(L, -1, "preload");
	lua_pushcfunction(L, open);
	lua_setfield(L, -2, "love.shim");
	lua_pop(L, 2);
}

} // namespace love_wasm_shim
