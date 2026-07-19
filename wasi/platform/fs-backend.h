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

// love-wasi platform seam — build-order step 6.2: the real love.filesystem
// backend for wasm32-wasi. It replaces PhysFS (which assumes a real OS fd
// layer the browser lacks) with the host-import VFS seam proven in 6.1: every
// read routes through the love_fs imports (fs_size / fs_read / fs_stat), which
// the host (LoveIDE, or the canned wasi/host/fs-host.mjs) fulfils from project
// storage. The backend is read-only and flat: the host store IS the source,
// keyed by the same relative names love.filesystem asks for. Write, mounting,
// and directory enumeration are deliberately unimplemented (loud, not faked) —
// see fs-backend.cpp for exactly which surfaces stop and why.
//
// This header lives out-of-tree (readme.md: the src tree stays upstream-shaped;
// the wasi build compiles the subset). wrap_Filesystem.cpp includes it under
// LOVE_WASI via -I wasi/platform, and constructs wasi_fs::Filesystem in place of
// physfs::Filesystem at the one guarded factory seam.
#ifndef LOVE_WASI_PLATFORM_FS_BACKEND_H
#define LOVE_WASI_PLATFORM_FS_BACKEND_H

#include "common/config.h"
#include "filesystem/Filesystem.h"
#include "filesystem/File.h"

#include <string>
#include <vector>

namespace love
{
namespace filesystem
{
namespace wasi_fs
{

// A read-only File backed by the love_fs host import surface. open(MODE_READ)
// pulls the whole file's bytes across the seam once (size-then-read, NUL-safe,
// exactly the 6.1 contract); reads/seeks/tell then serve from that buffer. This
// mirrors physfs::File's shape (open-throws-on-failure ctor; getSize() works
// even while closed) so the inherited File::read(int64) driver works unchanged.
class File final : public love::filesystem::File
{
public:

	File(const std::string &filename, Mode mode);
	virtual ~File();

	// Implements Stream.
	File *clone() override;
	int64 read(void *dst, int64 size) override;
	bool write(const void *data, int64 size) override;
	bool flush() override;
	int64 getSize() override;
	bool seek(int64 pos, SeekOrigin origin) override;
	int64 tell() override;

	// Implements love::filesystem::File.
	using love::filesystem::File::read;
	using love::filesystem::File::write;
	bool open(Mode mode) override;
	bool close() override;
	bool isOpen() const override;
	bool isEOF() override;
	bool setBuffer(BufferMode bufmode, int64 size) override;
	BufferMode getBuffer(int64 &size) const override;
	Mode getMode() const override;
	const std::string &getFilename() const override;

private:

	File(const File &other);

	std::string filename;

	// The file's bytes, pulled from the host on open(MODE_READ). Empty while
	// closed.
	std::vector<uint8_t> data;
	int64 pos;

	Mode mode;
	BufferMode bufferMode;
	int64 bufferSize;

}; // File

class Filesystem final : public love::filesystem::Filesystem
{
public:

	Filesystem();
	virtual ~Filesystem();

	void init(const char *arg0) override;

	void setFused(bool fused) override;
	bool isFused() const override;

	bool setupWriteDirectory() override;

	bool setIdentity(const char *ident, bool appendToPath = false) override;
	const char *getIdentity() const override;

	bool setSource(const char *source) override;
	const char *getSource() const override;

	bool mount(const char *archive, const char *mountpoint, bool appendToPath = false) override;
	bool mount(Data *data, const char *archivename, const char *mountpoint, bool appendToPath = false) override;

	bool mountFullPath(const char *archive, const char *mountpoint, MountPermissions permissions, bool appendToPath = false) override;
	bool mountCommonPath(CommonPath path, const char *mountpoint, MountPermissions permissions, bool appendToPath = false) override;

	bool unmount(const char *archive) override;
	bool unmount(Data *data) override;
	bool unmount(CommonPath path) override;
	bool unmountFullPath(const char *fullpath) override;

	love::filesystem::File *openFile(const char *filename, File::Mode mode) const override;

	std::string getFullCommonPath(CommonPath path) override;
	const char *getWorkingDirectory() override;
	std::string getUserDirectory() override;
	std::string getAppdataDirectory() override;
	std::string getSaveDirectory() override;
	std::string getSourceBaseDirectory() const override;

	std::string getRealDirectory(const char *filename) const override;

	bool exists(const char *filepath) const override;
	bool getInfo(const char *filepath, Info &info) const override;

	bool createDirectory(const char *dir) override;
	bool remove(const char *file) override;

	FileData *read(const char *filename, int64 size) const override;
	FileData *read(const char *filename) const override;
	void write(const char *filename, const void *data, int64 size) const override;
	void append(const char *filename, const void *data, int64 size) const override;

	bool getDirectoryItems(const char *dir, std::vector<std::string> &items) override;

	void setSymlinksEnabled(bool enable) override;
	bool areSymlinksEnabled() const override;

	std::vector<std::string> &getRequirePath() override;
	std::vector<std::string> &getCRequirePath() override;

	void allowMountingForPath(const std::string &path) override;

	// No <filesystem> on wasm; a VFS path needs only slash normalization.
	std::string canonicalizeRealPath(const std::string &path) const override;

private:

	std::string identity;
	std::string gameSource;
	bool fused;
	bool fusedSet;

	std::vector<std::string> requirePath;
	std::vector<std::string> cRequirePath;

}; // Filesystem

} // wasi_fs
} // filesystem
} // love

#endif // LOVE_WASI_PLATFORM_FS_BACKEND_H
