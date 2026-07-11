/* Module selection for the wasi build (step-4 graphics bring-up) — consumed by
 * src/common/config.h via HAVE_CONFIG_H, same door as the boot/audio configs.
 * Step 4's set: step 3's core plus love.graphics (opengl backend on WebGL2
 * static imports) and the modules graphics depends on to construct — image
 * (ImageData/Image), font (default font raster), and window (the "active" gate;
 * a minimal host-canvas seam). love.audio is left out of this build.
 */
#define LOVE_ENABLE_LOVE 1
#define LOVE_ENABLE_DATA 1
#define LOVE_ENABLE_MATH 1
#define LOVE_ENABLE_FILESYSTEM 1
#define LOVE_ENABLE_GRAPHICS 1
#define LOVE_ENABLE_IMAGE 1
#define LOVE_ENABLE_FONT 1
/* love.window is NOT enabled (its backend is step 6). Graphics only needs the
 * love::window::Window *type* (getInstance<Window> returns null with no window,
 * which is fine — isActive() is a query, not a render gate), so the build links
 * the base window/Window.cpp for that symbol without registering the module. */
