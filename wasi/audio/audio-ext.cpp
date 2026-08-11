// Step-5 pump extension for the audio build: like wasi/boot/pump-ext.cpp
// (preload love, require stays the booted script's act) but also registers the
// love.sound SoundData type standalone.
//
// Why register SoundData here: love.audio.RecordingDevice:getData() returns a
// love::sound::SoundData, so its Lua methods (getSample, getSampleCount, the
// love.data Data methods) must exist for a game — or this witness — to read
// captured audio. This build does not compile the full love.sound module (no
// decoders); luaopen_sounddata registers just the type (it embeds its own
// wrapper Lua and depends only on love.data), which is all the mic path needs.
#include "common/runtime.h"

extern "C" int luaopen_love(lua_State *L);
extern "C" int luaopen_sounddata(lua_State *L);

extern "C" void pump_open_extensions(lua_State *L)
{
	love::luax_preload(L, luaopen_love, "love");

	// Register the SoundData type, then drop whatever it left on the stack.
	int n = luaopen_sounddata(L);
	lua_pop(L, n);
}
