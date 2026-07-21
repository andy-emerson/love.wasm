// love-wasi frame pump — build-order step 2.
//
// The engine-side half of the browser main loop: Lua (the lua-wasi source
// drop) runs as a RESIDENT COROUTINE inside this artifact, and the host
// resumes it exactly once per frame (requestAnimationFrame tick). This file
// owns that contract; lua-wasi's luaw_* reactor glue is deliberately not
// used or extended (readme.md, "The three seams").
//
// The ABI is one in-slot and one out-slot over linear memory:
//
//   pump_in(cap)     -> ptr   host-writable buffer of at least cap bytes
//   pump_boot(len)   -> status  in-slot = Lua source; (re)creates the
//                               resident coroutine and runs it to its
//                               first yield
//   pump_frame(len)  -> status  in-slot = this frame's payload (one Lua
//                               string); resumes the coroutine once
//   pump_out()       -> ptr   \  the yielded / returned / error value,
//   pump_out_len()   -> u32   /  valid until the next pump call
//
// The live-edit reload primitive (build-order 6.7, decision D5=A — minimal &
// explicit, whole-chunk re-eval):
//
//   pump_invalidate() -> int  count of GAME Lua modules dropped from
//                             package.loaded (or PUMP_NOBOOT before boot).
//
// The host embeds live-edit like this: edit a game module's source in the VFS
// (the love_fs write path), call pump_invalidate() to drop the stale cached
// module, and the next `require` re-reads and re-evaluates the edited source.
// g_L PERSISTS across pump_boot, so package.loaded caches survive a reboot —
// this is the seam that clears them. love's own C++ modules (`love`, `love.*`)
// and the standard Lua libraries are preserved; only the GAME's Lua modules are
// invalidated. A twin Lua hook `__pump_invalidate()` is registered on the state
// so a witness can drive the full write→invalidate→re-require sequence in-script.
//
// status: >= 0   coroutine yielded; value of pump_out_len() (frame lives on)
//   PUMP_DONE    coroutine returned; out-slot = final value
//   PUMP_ERROR   Lua error; out-slot = message + traceback. The lua_State
//                SURVIVES (LÖVE semantics: an error ends the game loop,
//                not the engine — the host decides what boots next).
//   PUMP_NOBOOT  pump_frame before a successful pump_boot
//
// pump_eh_selftest() witnesses the two EH facts LÖVE's error path stands
// on (luax_catchexcept): a typed C++ catch with destructors run, and a
// Lua error unwinding *through a C++ frame* with that frame's destructors
// run — both through the one real wasm-EH libc++abi this artifact links
// (LUAW_EXTERNAL_EH; no micro-shim anywhere).

#include "lua.hpp"

#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

#define PUMP_EXPORT(name) \
  extern "C" __attribute__((export_name(name), visibility("default")))

enum : int32_t {
  PUMP_DONE = -1,
  PUMP_ERROR = -2,
  PUMP_NOBOOT = -3,
};

static const char PUMP_CO_KEY[] = "love.pump.co";

// Link-time extension point: an artifact that links more than the bare VM
// (step 3+: the LÖVE core) provides this to preload its modules into the
// fresh state. Weak so the step-2 artifact needs no stub TU.
extern "C" __attribute__((weak)) void pump_open_extensions(lua_State *L);

static lua_State *g_L = nullptr;   // the resident VM
static lua_State *g_co = nullptr;  // the resident coroutine (anchored in registry)
static std::string g_in;
static std::string g_out;

PUMP_EXPORT("pump_in") uint8_t *pump_in(uint32_t cap) {
  if (g_in.size() < cap) g_in.resize(cap);
  return reinterpret_cast<uint8_t *>(g_in.data());
}

PUMP_EXPORT("pump_out") const uint8_t *pump_out(void) {
  return reinterpret_cast<const uint8_t *>(g_out.data());
}

PUMP_EXPORT("pump_out_len") uint32_t pump_out_len(void) {
  return static_cast<uint32_t>(g_out.size());
}

// Convert the value at the top of co's stack into the out-slot and pop it.
static void top_to_out(lua_State *co) {
  size_t len = 0;
  const char *s = luaL_tolstring(co, -1, &len);  // pushes the string form
  g_out.assign(s, len);
  lua_pop(co, 2);  // the string form + the original value
}

// Shared tail of boot/frame: interpret lua_resume's outcome.
static int32_t settle(int status, int nres) {
  if (status == LUA_YIELD || status == LUA_OK) {
    if (nres > 0) {
      lua_pop(g_co, nres - 1);  // keep the first yielded/returned value
      top_to_out(g_co);
    } else {
      g_out.clear();
    }
    if (status == LUA_YIELD) return static_cast<int32_t>(g_out.size());
    g_co = nullptr;  // returned: the resident coroutine is spent
    return PUMP_DONE;
  }
  // Error: message on co's stack; traceback built from co's (intact) stack.
  const char *msg = lua_tostring(g_co, -1);
  luaL_traceback(g_L, g_co, msg ? msg : "(non-string error)", 0);
  size_t len = 0;
  const char *tb = lua_tolstring(g_L, -1, &len);
  g_out.assign(tb, len);
  lua_pop(g_L, 1);
  lua_pop(g_co, 1);
  g_co = nullptr;  // the coroutine is dead; the VM lives on
  return PUMP_ERROR;
}

// ── live-edit reload primitive (build-order 6.7, D5=A) ──────────────────────

// A module name is PRESERVED (never invalidated) if it is love or a love.*
// submodule (the engine's real C++ modules) or one of the standard Lua
// libraries opened by luaL_openlibs. Everything else is a GAME Lua module.
static bool pump_is_preserved_module(const char *name, size_t len) {
  if (len >= 4 && name[0] == 'l' && name[1] == 'o' && name[2] == 'v' && name[3] == 'e'
      && (len == 4 || name[4] == '.'))
    return true;
  static const char *std_libs[] = {
    "_G", "package", "coroutine", "table", "io", "os",
    "string", "math", "utf8", "debug", nullptr };
  for (int i = 0; std_libs[i] != nullptr; ++i)
    if (std::strcmp(name, std_libs[i]) == 0)
      return true;
  return false;
}

// Drop every game (non-love, non-standard) module from package.loaded so the
// next require re-reads and re-evaluates its (now host-edited) source. Operates
// on L's registry LOADED table, shared by every thread of L. Returns the count
// cleared.
static int pump_invalidate_modules(lua_State *L) {
  lua_getfield(L, LUA_REGISTRYINDEX, LUA_LOADED_TABLE);  // "_LOADED"
  if (!lua_istable(L, -1)) { lua_pop(L, 1); return 0; }

  // Collect victim keys first — mutating a table mid-traversal (setting a key to
  // nil under lua_next) is undefined. String keys only; reading a string key
  // with lua_tolstring is safe (no in-place number->string conversion).
  std::vector<std::string> victims;
  lua_pushnil(L);
  while (lua_next(L, -2) != 0) {
    if (lua_type(L, -2) == LUA_TSTRING) {
      size_t klen = 0;
      const char *k = lua_tolstring(L, -2, &klen);
      if (!pump_is_preserved_module(k, klen))
        victims.emplace_back(k, klen);
    }
    lua_pop(L, 1);  // pop value, keep key for the next lua_next
  }

  for (const std::string &v : victims) {
    lua_pushnil(L);
    lua_setfield(L, -2, v.c_str());
  }
  lua_pop(L, 1);  // pop _LOADED
  return static_cast<int>(victims.size());
}

// Lua-callable twin: __pump_invalidate() -> number of modules cleared. Lets a
// witness drive write→invalidate→re-require deterministically in one coroutine
// run (identical on node:wasi and Chromium), no host frame coordination needed.
static int pump_l_invalidate(lua_State *L) {
  lua_pushinteger(L, pump_invalidate_modules(L));
  return 1;
}

PUMP_EXPORT("pump_invalidate") int32_t pump_invalidate(void) {
  if (!g_L) return PUMP_NOBOOT;
  return static_cast<int32_t>(pump_invalidate_modules(g_L));
}

PUMP_EXPORT("pump_boot") int32_t pump_boot(uint32_t len) {
  if (!g_L) {
    g_L = luaL_newstate();
    if (!g_L) { g_out.assign("pump: luaL_newstate failed"); return PUMP_ERROR; }
    luaL_openlibs(g_L);
    lua_register(g_L, "__pump_invalidate", pump_l_invalidate);
    if (pump_open_extensions)
      pump_open_extensions(g_L);
  }
  // Fresh resident coroutine; anchoring it in the registry replaces (and
  // frees for GC) any prior one — the pump can be re-booted after DONE or
  // ERROR without tearing the VM down.
  g_co = lua_newthread(g_L);
  lua_setfield(g_L, LUA_REGISTRYINDEX, PUMP_CO_KEY);
  if (luaL_loadbuffer(g_co, g_in.data(), len, "@pump-boot") != LUA_OK) {
    size_t elen = 0;
    const char *e = lua_tolstring(g_co, -1, &elen);
    g_out.assign(e, elen);
    lua_pop(g_co, 1);
    g_co = nullptr;
    return PUMP_ERROR;
  }
  int nres = 0;
  int status = lua_resume(g_co, g_L, 0, &nres);  // run to the first yield
  return settle(status, nres);
}

PUMP_EXPORT("pump_frame") int32_t pump_frame(uint32_t len) {
  if (!g_co) return PUMP_NOBOOT;
  lua_pushlstring(g_co, g_in.data(), len);
  int nres = 0;
  int status = lua_resume(g_co, g_L, 1, &nres);
  return settle(status, nres);
}

// ── EH self-test ────────────────────────────────────────────────────────────

static int g_destroyed = 0;

struct PumpTracker {
  ~PumpTracker() { ++g_destroyed; }
};

struct PumpError : std::runtime_error {
  using std::runtime_error::runtime_error;
};

static void throws_typed_through_a_frame() {
  PumpTracker t;  // must be destroyed by the unwind
  throw PumpError("pump typed message intact");
}

// A lua_CFunction whose C++ frame holds a destructor while lua_error
// unwinds through it — the exact shape of every luax_catchexcept site.
static int lua_error_through_cxx_frame(lua_State *L) {
  PumpTracker t;  // must be destroyed when luaD_throw unwinds this frame
  return luaL_error(L, "lua error through C++ frame");
}

PUMP_EXPORT("pump_eh_selftest") int32_t pump_eh_selftest(void) {
  int32_t failed = 0;

  // Leg 1: our own typed C++ exception, destructor run during unwind.
  g_destroyed = 0;
  bool typed_ok = false;
  try {
    throws_typed_through_a_frame();
  } catch (const std::exception &e) {  // typed catch via base class
    typed_ok = std::string(e.what()) == "pump typed message intact";
  }
  if (!typed_ok) failed |= 1 << 0;
  if (g_destroyed != 1) failed |= 1 << 1;

  // Leg 2: a Lua error unwinding through a C++ frame, same runtime.
  lua_State *L = luaL_newstate();
  if (!L) return failed | (1 << 4);
  g_destroyed = 0;
  lua_pushcfunction(L, lua_error_through_cxx_frame);
  int status = lua_pcall(L, 0, 0, 0);
  const char *msg = lua_tostring(L, -1);
  bool lua_ok = status == LUA_ERRRUN && msg &&
                std::string(msg).find("lua error through C++ frame") != std::string::npos;
  if (!lua_ok) failed |= 1 << 2;
  if (g_destroyed != 1) failed |= 1 << 3;
  lua_close(L);

  return failed;
}
