/**
 * Copyright (c) 2006-2026 LOVE Development Team
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 **/

// love-wasi platform seam — build-order step 6.2. A non-SDL NativeFile.
//
// The upstream NativeFile (src/modules/filesystem/NativeFile.cpp) is C stdio on
// top of SDL_IOStream (<SDL3/SDL_iostream.h>), which this target has no SDL for,
// so that translation unit is not compiled. But NativeFile is still referenced:
// Filesystem::openNativeFile constructs one, and wrap_NativeFile.cpp registers
// its Lua type (luaopen_nativefile). NativeFile addresses a *system-dependent
// full OS path*, which a browser has no notion of — so every entry point is a
// loud throw here, never a silent fake. love.filesystem.openNativeFile is not
// on the boot/read path this backend serves; if something reaches it, it hears
// exactly why it stopped.
//
// This provides the symbols (constructor + full vtable) that linking needs; the
// SDL-free wrap_NativeFile.cpp compiles unchanged and links against them.

#include "common/config.h"
#include "common/Exception.h"
#include "filesystem/NativeFile.h"

namespace love
{
namespace filesystem
{

static love::Exception unsupported()
{
	return love::Exception("NativeFile (native OS filesystem paths) is not supported on wasm32-wasi.");
}

NativeFile::NativeFile(const std::string &, Mode)
	: file(nullptr)
	, mode(MODE_CLOSED)
	, buffer(nullptr)
	, bufferMode(BUFFER_NONE)
	, bufferSize(0)
	, bufferUsed(0)
{
	throw unsupported();
}

NativeFile::NativeFile(const NativeFile &)
	: file(nullptr)
	, mode(MODE_CLOSED)
	, buffer(nullptr)
	, bufferMode(BUFFER_NONE)
	, bufferSize(0)
	, bufferUsed(0)
{
	throw unsupported();
}

NativeFile::~NativeFile()
{
}

NativeFile *NativeFile::clone() { throw unsupported(); }
int64 NativeFile::read(void *, int64) { throw unsupported(); }
bool NativeFile::write(const void *, int64) { throw unsupported(); }
bool NativeFile::flush() { throw unsupported(); }
int64 NativeFile::getSize() { throw unsupported(); }
int64 NativeFile::tell() { throw unsupported(); }
bool NativeFile::seek(int64, SeekOrigin) { throw unsupported(); }
bool NativeFile::open(Mode) { throw unsupported(); }
bool NativeFile::close() { throw unsupported(); }
bool NativeFile::isOpen() const { return false; }
bool NativeFile::isEOF() { throw unsupported(); }
bool NativeFile::setBuffer(BufferMode, int64) { throw unsupported(); }
NativeFile::BufferMode NativeFile::getBuffer(int64 &) const { throw unsupported(); }
NativeFile::Mode NativeFile::getMode() const { return MODE_CLOSED; }

const std::string &NativeFile::getFilename() const
{
	return filename;
}

} // filesystem
} // love
