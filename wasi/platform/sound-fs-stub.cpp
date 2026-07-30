// love.sound filesystem-helper stub — pre-step-7 "unblock a real game" pass 2.
//
// love.sound's wrap_Sound.cpp references three love::filesystem helpers so it can
// accept a filepath / File argument (w_newDecoder: luax_cangetfile, then
// luax_getfile / luax_getfiledata). This build links love.sound WITHOUT
// love.filesystem — it decodes from a Data directly (wrap_Sound's `else if
// Data::type` branch → data::DataStream) — so those three symbols are satisfied
// here rather than by the real module:
//
//   * luax_cangetfile returns false, so EVERY value is routed to the Data branch;
//   * luax_getfile / luax_getfiledata are consequently never reached — they throw
//     loudly if they ever are, rather than fake a File this build has no type for.
//
// Not the shared wasi/boot/filesystem-stub.cpp: that stub carries
// luaopen_love_filesystem + luax_cangetdata for the boot/audio builds; the sound
// build needs only these three, so keeping them local gives the sound pass zero
// blast radius on other builds. The `Data`-accepting path (luax_cangetdata) is
// unused by love.sound (it type-checks Data::type inline), so it is not needed.
//
// File / FileData are forward-declared: the three functions are matched to the
// engine's calls by mangled name (parameters only — the Itanium ABI does not
// mangle return types for free functions), so complete definitions are not
// required to link.
#include "common/runtime.h"
#include "common/Exception.h"

namespace love
{
namespace filesystem
{

class File;
class FileData;

bool luax_cangetfile(lua_State *, int)
{
	// Report "not a file" for every value, so love.sound takes the Data branch.
	return false;
}

File *luax_getfile(lua_State *, int)
{
	throw love::Exception("love.filesystem File access is not available in this build "
		"(love.sound decodes from a Data directly)");
}

FileData *luax_getfiledata(lua_State *, int)
{
	throw love::Exception("love.filesystem FileData access is not available in this build "
		"(love.sound decodes from a Data directly)");
}

} // filesystem
} // love
