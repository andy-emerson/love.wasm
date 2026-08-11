/* Module selection for the wasi build — consumed by src/common/config.h
 * through its HAVE_CONFIG_H mechanism (the same door the autotools build
 * uses), so the module set is chosen without editing shared engine code.
 * Reached via `#include <../config.h>`: the build passes
 * -I wasi/boot/config/include and this file sits one level above it.
 *
 * Build-order step 3's set — grows as the build order advances:
 *   real:     love (registry + boot scripts), love.data (luaopen_love
 *             requires it unconditionally; lz4 + lua53-pack in-tree,
 *             zlib vendored at wasi/vendor/zlib), love.math
 *   stubbed:  love.filesystem (wasi/boot/filesystem-stub.cpp, loud seam)
 *   absent:   everything else (SDL/GL/AL-backed, or not yet reached)
 *
 * No WORDS_BIGENDIAN: wasm32 is little-endian.
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_MATH 1
#define LOVE_ENABLE_FILESYSTEM 1
