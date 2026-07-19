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

// love-wasi platform seam — build-order step 6.2. The real love.filesystem
// backend on the love_fs VFS seam (6.1). See fs-backend.h for the shape; this
// file is where the imports are declared and where each honest stop lives.
//
// love_fs import surface (declared here with the same import_module attribute
// 6.1's fs-ext.cpp uses, so lld emits them as wasm imports — no
// --allow-undefined). fs_size / fs_read are 6.1 unchanged; fs_stat is the 6.2
// addition that backs getInfo/exists:
//   fs_size(path,len)                    -> byte length, or -1 if absent
//   fs_read(path,len, buf,cap)           -> bytes copied (<= cap), or -1
//   fs_stat(path,len, *type,*size,*mtime)-> 0 ok / -1 absent; type is the
//                                           FileType enum order (0 file, 1 dir,
//                                           2 symlink, 3 other).

#include "fs-backend.h"

#include "common/Exception.h"
#include "filesystem/FileData.h"

#include <cstdint>
#include <cstring>

#define FS_IMPORT(sym) __attribute__((import_module("love_fs"), import_name(sym)))

extern "C" {
FS_IMPORT("fs_size") int32_t wfs_size(const char *path, int32_t path_len);
FS_IMPORT("fs_read") int32_t wfs_read(const char *path, int32_t path_len, uint8_t *buf, int32_t cap);
FS_IMPORT("fs_stat") int32_t wfs_stat(const char *path, int32_t path_len,
	int32_t *out_type, int64_t *out_size, int64_t *out_mtime);
}

namespace love
{
namespace filesystem
{
namespace wasi_fs
{

// ---------------------------------------------------------------------------
// File
// ---------------------------------------------------------------------------

File::File(const std::string &filename, Mode mode)
	: filename(filename)
	, pos(0)
	, mode(MODE_CLOSED)
	, bufferMode(BUFFER_NONE)
	, bufferSize(0)
{
	if (!open(mode))
		throw love::Exception("Could not open file at path %s", filename.c_str());
}

File::File(const File &other)
	: filename(other.filename)
	, pos(0)
	, mode(MODE_CLOSED)
	, bufferMode(other.bufferMode)
	, bufferSize(other.bufferSize)
{
	if (!open(other.mode))
		throw love::Exception("Could not open file at path %s", filename.c_str());
}

File::~File()
{
	if (mode != MODE_CLOSED)
		close();
}

File *File::clone()
{
	return new File(*this);
}

bool File::open(Mode mode)
{
	if (mode == MODE_CLOSED)
	{
		close();
		return true;
	}

	// The host VFS is read-only: the project store the browser fulfils is not
	// writable from the wasm side (write lands at step 6's save-dir sub-step).
	if (mode == MODE_WRITE || mode == MODE_APPEND)
		throw love::Exception("Could not open file %s for writing: the wasm32-wasi filesystem is read-only.", filename.c_str());

	// Already open?
	if (this->mode != MODE_CLOSED)
		return false;

	int32_t size = wfs_size(filename.c_str(), (int32_t) filename.size());
	if (size < 0)
		throw love::Exception("Could not open file %s. Does not exist.", filename.c_str());

	data.resize((size_t) size);
	if (size > 0)
	{
		int32_t n = wfs_read(filename.c_str(), (int32_t) filename.size(), data.data(), size);
		if (n < 0)
		{
			data.clear();
			throw love::Exception("Could not read file %s.", filename.c_str());
		}
		data.resize((size_t) n);
	}

	pos = 0;
	this->mode = mode;
	return true;
}

bool File::close()
{
	if (mode == MODE_CLOSED)
		return false;

	data.clear();
	data.shrink_to_fit();
	pos = 0;
	mode = MODE_CLOSED;
	return true;
}

bool File::isOpen() const
{
	return mode != MODE_CLOSED;
}

int64 File::getSize()
{
	// Match physfs::File: report the size even while closed, by asking the host
	// (the inherited File::read driver calls getSize before it has opened).
	if (mode == MODE_CLOSED)
		return (int64) wfs_size(filename.c_str(), (int32_t) filename.size());

	return (int64) data.size();
}

int64 File::read(void *dst, int64 size)
{
	if (mode != MODE_READ)
		throw love::Exception("File is not opened for reading.");

	if (size < 0)
		throw love::Exception("Invalid read size.");

	int64 max = (int64) data.size();
	if (pos > max)
		pos = max;

	int64 n = size;
	if (pos + n > max)
		n = max - pos;

	if (n > 0)
	{
		memcpy(dst, data.data() + pos, (size_t) n);
		pos += n;
	}

	return n;
}

bool File::write(const void *, int64)
{
	throw love::Exception("File is not opened for writing.");
}

bool File::flush()
{
	throw love::Exception("File is not opened for writing.");
}

bool File::isEOF()
{
	return mode == MODE_CLOSED || pos >= (int64) data.size();
}

int64 File::tell()
{
	if (mode == MODE_CLOSED)
		return -1;
	return pos;
}

bool File::seek(int64 pos, SeekOrigin origin)
{
	if (mode == MODE_CLOSED)
		return false;

	if (origin == SEEKORIGIN_CURRENT)
		pos += this->pos;
	else if (origin == SEEKORIGIN_END)
		pos += (int64) data.size();

	if (pos < 0 || pos > (int64) data.size())
		return false;

	this->pos = pos;
	return true;
}

bool File::setBuffer(BufferMode bufmode, int64 size)
{
	if (size < 0)
		return false;

	// Reads are already fully buffered (the whole file is pulled on open), so
	// buffering is a no-op we accept honestly rather than reject.
	bufferMode = bufmode;
	bufferSize = size;
	return true;
}

File::BufferMode File::getBuffer(int64 &size) const
{
	size = bufferSize;
	return bufferMode;
}

File::Mode File::getMode() const
{
	return mode;
}

const std::string &File::getFilename() const
{
	return filename;
}

// ---------------------------------------------------------------------------
// Filesystem
// ---------------------------------------------------------------------------

Filesystem::Filesystem()
	: love::filesystem::Filesystem("love.filesystem.wasi")
	, fused(false)
	, fusedSet(false)
{
	// The base ctor does NOT populate these; physfs/Filesystem.cpp sets the same
	// defaults, and the `require` loader in wrap_Filesystem.cpp depends on them.
	requirePath = {"?.lua", "?/init.lua"};
	cRequirePath = {"??"};
}

Filesystem::~Filesystem()
{
}

void Filesystem::init(const char *)
{
	// arg0 anchors PhysFS's search on desktop; the host VFS is flat and keyed by
	// relative name, so there is nothing to initialize here.
}

void Filesystem::setFused(bool fused)
{
	if (fusedSet)
		return;
	this->fused = fused;
	fusedSet = true;
}

bool Filesystem::isFused() const
{
	return fusedSet && fused;
}

bool Filesystem::setupWriteDirectory()
{
	// No write directory exists yet; report success so the unguarded boot path
	// (which calls this) proceeds. Actual writes still stop in File::open.
	return true;
}

bool Filesystem::setIdentity(const char *ident, bool /*appendToPath*/)
{
	// MUST return true: love.boot sets the identity unguarded and treats false
	// as fatal. There is no save directory to (re)mount on this backend yet.
	if (ident != nullptr)
		identity = ident;
	return true;
}

const char *Filesystem::getIdentity() const
{
	return identity.c_str();
}

bool Filesystem::setSource(const char *source)
{
	// Settable once, like physfs. The host store is the source, so this only
	// records the path for getSource()/getSourceBaseDirectory().
	if (!gameSource.empty())
		return false;
	if (source != nullptr)
		gameSource = source;
	return true;
}

const char *Filesystem::getSource() const
{
	return gameSource.c_str();
}

bool Filesystem::mount(const char *, const char *, bool) { return false; }
bool Filesystem::mount(Data *, const char *, const char *, bool) { return false; }
bool Filesystem::mountFullPath(const char *, const char *, MountPermissions, bool) { return false; }
bool Filesystem::mountCommonPath(CommonPath, const char *, MountPermissions, bool) { return false; }
bool Filesystem::unmount(const char *) { return false; }
bool Filesystem::unmount(Data *) { return false; }
bool Filesystem::unmount(CommonPath) { return false; }
bool Filesystem::unmountFullPath(const char *) { return false; }

love::filesystem::File *Filesystem::openFile(const char *filename, File::Mode mode) const
{
	return new File(filename, mode);
}

std::string Filesystem::getFullCommonPath(CommonPath) { return ""; }
const char *Filesystem::getWorkingDirectory() { return ""; }
std::string Filesystem::getUserDirectory() { return ""; }
std::string Filesystem::getAppdataDirectory() { return ""; }
std::string Filesystem::getSaveDirectory() { return ""; }
std::string Filesystem::getSourceBaseDirectory() const { return ""; }

std::string Filesystem::getRealDirectory(const char *) const
{
	// There is no real OS directory behind a host-VFS file. love.boot guards
	// this call; anything else that reaches it should hear so, not get a lie.
	throw love::Exception("getRealDirectory is not available on the wasm32-wasi filesystem backend.");
}

bool Filesystem::exists(const char *filepath) const
{
	int32_t type = 0;
	int64_t size = 0, mtime = 0;
	return wfs_stat(filepath, (int32_t) strlen(filepath), &type, &size, &mtime) == 0;
}

bool Filesystem::getInfo(const char *filepath, Info &info) const
{
	int32_t type = 0;
	int64_t size = 0, mtime = 0;
	if (wfs_stat(filepath, (int32_t) strlen(filepath), &type, &size, &mtime) != 0)
		return false;

	info.size = (int64) size;
	info.modtime = (int64) mtime;
	info.readonly = true;  // the host VFS is read-only

	switch (type)
	{
	case 0: info.type = FILETYPE_FILE; break;
	case 1: info.type = FILETYPE_DIRECTORY; break;
	case 2: info.type = FILETYPE_SYMLINK; break;
	default: info.type = FILETYPE_OTHER; break;
	}

	return true;
}

bool Filesystem::createDirectory(const char *) { return false; }
bool Filesystem::remove(const char *) { return false; }

FileData *Filesystem::read(const char *filename, int64 size) const
{
	File file(filename, File::MODE_READ);
	return file.read(size);
}

FileData *Filesystem::read(const char *filename) const
{
	File file(filename, File::MODE_READ);
	return file.read();
}

void Filesystem::write(const char *, const void *, int64) const
{
	throw love::Exception("The wasm32-wasi filesystem is read-only: write is not supported.");
}

void Filesystem::append(const char *, const void *, int64) const
{
	throw love::Exception("The wasm32-wasi filesystem is read-only: append is not supported.");
}

bool Filesystem::getDirectoryItems(const char *, std::vector<std::string> &)
{
	// Directory enumeration (the fs_list seam) is deferred; report nothing
	// rather than fake entries.
	return false;
}

void Filesystem::setSymlinksEnabled(bool) {}
bool Filesystem::areSymlinksEnabled() const { return false; }

std::vector<std::string> &Filesystem::getRequirePath() { return requirePath; }
std::vector<std::string> &Filesystem::getCRequirePath() { return cRequirePath; }

void Filesystem::allowMountingForPath(const std::string &) {}

std::string Filesystem::canonicalizeRealPath(const std::string &path) const
{
	std::string out = path;
	for (char &c : out)
	{
		if (c == '\\')
			c = '/';
	}
	return out;
}

} // wasi_fs
} // filesystem
} // love
