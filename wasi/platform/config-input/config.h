/* Module selection for the wasi build — build-order step 6.4 (input bring-up).
 * Consumed by src/common/config.h via HAVE_CONFIG_H (`#include <../config.h>`
 * resolved through -I config-input/include), the same door as the boot/audio/
 * graphics/window configs.
 *
 * The set is deliberately lean: the LÖVE core plus the three input modules and
 * their unavoidable dependencies. love.mouse's Cursor is built from image data
 * (wrap_Mouse.cpp references love::image::ImageData::type and love.filesystem's
 * luax_getdata / File::type to load a cursor from a file), so love.image and
 * love.filesystem (the real 6.2 module on the love_fs seam) are enabled too;
 * love.data backs love.image's compressed formats. No graphics / window / font
 * here — the input path is witnessed windowlessly (a coroutine driving
 * love.event.pump + poll and the love.keyboard/mouse readers), so this artifact
 * runs on BOTH node:wasi and real Chromium, no WebGL2 needed.
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_FILESYSTEM 1
#define LOVE_ENABLE_IMAGE 1
#define LOVE_ENABLE_EVENT 1
#define LOVE_ENABLE_KEYBOARD 1
#define LOVE_ENABLE_MOUSE 1
