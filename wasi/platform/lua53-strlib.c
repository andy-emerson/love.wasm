/**
 * love.data's string-packing entry points, implemented over Lua 5.4's OWN
 * string.pack / string.unpack / string.packsize.
 *
 * This file replaces src/libraries/lua53/lstrlib.c in the wasm builds. That file
 * is the Kepler lua-compat-5.3 backport, which upstream LÖVE vendors so that
 * LuaJIT — Lua 5.1, where string.pack does not exist — can still serve
 * love.data.pack. It is correct there and wrong here, because this build runs
 * PUC Lua 5.4 (D8), where those three functions are native.
 *
 * It is not merely redundant on 5.4, it is broken. Its buffer layer branches on
 * LUA_VERSION_NUM == 501: off that path luaL_buffinit_53 initialises the NATIVE
 * luaL_Buffer, but luaL_addsize_53 and lua53_pushresult still read the shim's
 * own ptr / nelems / L2 fields, which nothing has set. So lua53_pushresult calls
 * lua_pushlstring on a garbage lua_State and the module traps — "null function
 * or function signature mismatch", sometimes "memory access out of bounds".
 * Someone added a LUA_VERSION_NUM >= 504 arm to one macro, which made it
 * compile under 5.4 without making it work; upstream never runs this path.
 *
 * The interface is five symbols and the contract is set by
 * src/modules/data/wrap_DataModule.cpp, which reads B->ptr and B->nelems
 * directly rather than only through the accessors — so a replacement has to
 * populate those two fields for real, not just produce a Lua string.
 *
 * The functions are taken from the REGISTRY's loaded-module table, not from the
 * `string` global, so a game that reassigns string.pack cannot change what
 * love.data.pack does.
 */
#include <string.h>

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"  /* LUA_STRLIBNAME */

/* Upstream's header, for the luaL_Buffer_53 layout and the prototypes — so a
 * drift in either is a compile error here rather than a trap at runtime. */
#include "libraries/lua53/lstrlib.h"

/* Push package.loaded.string[name] onto the stack. */
static void push_string_fn(lua_State *L, const char *name)
{
	lua_getfield(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
	lua_getfield(L, -1, LUA_STRLIBNAME);
	lua_getfield(L, -1, name);
	lua_remove(L, -2); /* the string table */
	lua_remove(L, -2); /* the loaded table */
	if (!lua_isfunction(L, -1))
		luaL_error(L, "string.%s is unavailable", name);
}

/*
 * Pack the arguments at startidx..top per fmt, leaving the bytes readable at
 * B->ptr / B->nelems. Deliberately does NOT push the result: the caller either
 * memcpy's out of B->ptr (the ByteData and Data paths) or asks for it with
 * lua53_pushresult (the string path).
 *
 * The packed string is kept ON THE STACK, which is what keeps B->ptr alive —
 * Lua owns those bytes and may collect them otherwise. B->capacity carries its
 * absolute stack index so lua53_cleanupbuffer can drop it again; the field is
 * unused for its original meaning here, and 0 means "nothing held".
 */
void lua53_str_pack(lua_State *L, const char *fmt, int startidx, luaL_Buffer_53 *B)
{
	int nargs = lua_gettop(L) - startidx + 1;
	int i;
	size_t len = 0;
	const char *s;

	if (nargs < 0)
		nargs = 0;

	push_string_fn(L, "pack");
	lua_pushstring(L, fmt);
	for (i = 0; i < nargs; i++)
		lua_pushvalue(L, startidx + i);

	/* Errors propagate exactly as the backport's did: as Lua errors. */
	lua_call(L, nargs + 1, 1);

	s = lua_tolstring(L, -1, &len);
	B->L2 = L;
	B->ptr = (char *) s;
	B->nelems = len;
	B->capacity = (size_t) lua_gettop(L);
}

/* Push the packed bytes as a Lua string. A copy, so it does not matter whether
 * the caller cleans the temporary up before or after. */
void lua53_pushresult(luaL_Buffer_53 *B)
{
	lua_pushlstring(B->L2, B->ptr, B->nelems);
}

/* Drop the temporary that was holding the bytes alive. After this B->ptr must
 * not be read again — which matches the backport, where it also released the
 * buffer. */
void lua53_cleanupbuffer(luaL_Buffer_53 *B)
{
	if (B->capacity != 0)
	{
		lua_remove(B->L2, (int) B->capacity);
		B->capacity = 0;
		B->ptr = NULL;
		B->nelems = 0;
	}
}

/*
 * love.data.getPackedSize — registered directly as a lua_CFunction, so fmt is
 * at index 1.
 */
int lua53_str_packsize(lua_State *L)
{
	push_string_fn(L, "packsize");
	lua_pushvalue(L, 1);
	lua_call(L, 1, 1);
	return 1;
}

/*
 * love.data.unpack. `data`/`ld` are the bytes already normalised by the caller
 * out of either a string or a Data, so they are passed to string.unpack as a
 * string; `dataidx` is the caller's stack index for those bytes and is not
 * needed here (the backport used it only to phrase errors). `posidx` is the
 * optional starting position.
 *
 * Returns every value string.unpack produced — the unpacked values followed by
 * the next position — which is love.data.unpack's documented contract.
 */
int lua53_str_unpack(lua_State *L, const char *fmt, const char *data, size_t ld, int dataidx, int posidx)
{
	int base = lua_gettop(L);
	int nargs = 2;
	/* Read BEFORE anything is pushed. posidx is an absolute index, so once the
	 * function and its arguments are on the stack it may point at one of THEM
	 * rather than at the caller's optional position — which is exactly what
	 * happened: an absent position was read back as the pushed function. */
	int havepos = !lua_isnoneornil(L, posidx);

	(void) dataidx;

	push_string_fn(L, "unpack");
	lua_pushstring(L, fmt);
	lua_pushlstring(L, data, ld);
	if (havepos)
	{
		lua_pushvalue(L, posidx);
		nargs = 3;
	}

	lua_call(L, nargs, LUA_MULTRET);
	return lua_gettop(L) - base;
}
