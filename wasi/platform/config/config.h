/* Module selection for the wasi build (step-6.3 window bring-up) — consumed by
 * src/common/config.h via HAVE_CONFIG_H, same door as the boot/audio/graphics
 * configs. Step 6.3's set is step 4's graphics set PLUS love.window: the real
 * love.window backend (wasi/platform/window-backend.cpp) on the love_win host
 * seam, which creates the real canvas + WebGL2 context and drives
 * graphics->setMode against it. With love.window enabled, Graphics::isActive()
 * finds a registered, open M_WINDOW, so present() runs for real (and with it
 * captureScreenshot's backbuffer readback — build-order step 4's last item).
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_MATH 1
#define LOVE_ENABLE_FILESYSTEM 1
#define LOVE_ENABLE_GRAPHICS 1
#define LOVE_ENABLE_IMAGE 1
#define LOVE_ENABLE_FONT 1
#define LOVE_ENABLE_WINDOW 1
