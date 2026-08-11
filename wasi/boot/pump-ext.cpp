// Step-3 pump extension: put the LÖVE core on the pump's fresh lua_State.
// Preload only — `require("love")` stays an explicit act of the booted
// script, same as desktop love.cpp's runlove().
#include "common/runtime.h"

extern "C" int luaopen_love(lua_State *L);

extern "C" void pump_open_extensions(lua_State *L)
{
	love::luax_preload(L, luaopen_love, "love");
}
