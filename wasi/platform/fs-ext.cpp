// love-wasi platform seam — build-order step 6, sub-step 6.1: the love_fs VFS
// seam, read round-trip. ISOLATES THE HOST<->WASM FILE-BYTES PLUMBING before
// the real love.filesystem module rides on it (6.2), the same way graphics'
// 4.1a raw-GL leg isolated the WebGL2 import plumbing before the reused opengl
// backend rode on it (4.1c). No LÖVE core is linked here on purpose: this proves
// only that the seam carries a file's bytes intact, both directions, under a
// real WASI host (node) and a real browser instantiate (Chromium).
//
// The seam ABI is deliberately the minimum a synchronous pull-based reader
// needs — ask the size, allocate, ask the bytes — which is exactly the shape
// the 6.2 Filesystem backend will call (readme.md: "host-import VFS backed by
// the IDE's project storage, replacing PhysFS"). WASI preopens are NOT used:
// the design routes the filesystem through a custom import so the one host
// contract works in the browser, which has no real fd layer (wasi-shim.mjs
// reports fd_prestat_get -> EBADF, "no preopened dirs").
//
//   love_fs.fs_size(path, path_len)            -> byte length, or -1 if absent
//   love_fs.fs_read(path, path_len, buf, cap)  -> bytes copied (<= cap), or -1
//
// The bridge exposes two globals the witness lua drives:
//   __wasi_fs_size(path)  -> integer            (host-reported size, or -1)
//   __wasi_fs_read(path)  -> string | nil, err  (the bytes, NUL-accurate)
//
// NUL-accuracy is the point of the whole witness: a C-string protocol (strlen)
// or lua_pushstring would truncate a binary asset at its first zero byte. The
// seam carries an explicit length end to end and the bridge uses lua_pushlstring
// (via luaL_Buffer), so the recovered Lua string is byte-exact.
#include "lua.hpp"

#include <cstdint>

#define FS_IMPORT(sym) __attribute__((import_module("love_fs"), import_name(sym)))

extern "C" {
FS_IMPORT("fs_size") int32_t wfs_size(const char *path, int32_t path_len);
FS_IMPORT("fs_read") int32_t wfs_read(const char *path, int32_t path_len, uint8_t *buf, int32_t cap);
}

// __wasi_fs_size(path) -> integer   (the host's byte count, or -1 if absent)
static int w_fs_size(lua_State *L)
{
	size_t plen = 0;
	const char *path = luaL_checklstring(L, 1, &plen);
	lua_pushinteger(L, wfs_size(path, static_cast<int32_t>(plen)));
	return 1;
}

// __wasi_fs_read(path) -> string | (nil, errmsg)
// Size-then-read: learn the length, allocate a Lua buffer of exactly that many
// bytes, fill it from the host, and push it length-accurately (NUL-safe).
static int w_fs_read(lua_State *L)
{
	size_t plen = 0;
	const char *path = luaL_checklstring(L, 1, &plen);
	int32_t sz = wfs_size(path, static_cast<int32_t>(plen));
	if (sz < 0) {
		lua_pushnil(L);
		lua_pushfstring(L, "no such file: %s", path);
		return 2;
	}
	luaL_Buffer b;
	char *buf = luaL_buffinitsize(L, &b, static_cast<size_t>(sz));
	int32_t n = wfs_read(path, static_cast<int32_t>(plen), reinterpret_cast<uint8_t *>(buf), sz);
	if (n < 0) {
		luaL_pushresultsize(&b, 0);  // close the buffer before bailing
		lua_pop(L, 1);
		lua_pushnil(L);
		lua_pushfstring(L, "read failed: %s", path);
		return 2;
	}
	luaL_pushresultsize(&b, static_cast<size_t>(n));
	return 1;
}

// The pump's link-time extension point (wasi/pump/pump.cpp): register the seam
// globals on the fresh lua_State. No love preload here — 6.1 is the raw seam.
extern "C" void pump_open_extensions(lua_State *L)
{
	lua_register(L, "__wasi_fs_size", w_fs_size);
	lua_register(L, "__wasi_fs_read", w_fs_read);
}
