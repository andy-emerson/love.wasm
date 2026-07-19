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

// love-wasi platform seam — build-order step 6.3. The real love.window backend
// on the love_win host seam. See window-backend.h for the shape and the design;
// this file declares the imports and implements every method.
//
// love_win import surface (declared here with the same import_module attribute
// 6.2's fs-backend.cpp and the gl-imports use, so lld emits them as wasm imports
// — no --allow-undefined). The host (wasi/host/webgl-win-host.mjs) fulfils them:
//   window_setmode(w,h,stencil,depth,msaa,vsync) -> 1 ok / 0 fail
//       Creates the real <canvas> + WebGL2 context (preserveDrawingBuffer:true,
//       depth, stencil) and makes it the context the love_gl imports target.
//       MUST run BEFORE graphics->setMode, which calls gl.initContext() against
//       whatever context love_gl currently points at (it ignores its context
//       argument — opengl/Graphics.cpp).
//   window_get_pixel_dimensions(int32* outW, int32* outH)
//       The canvas's real backing pixel size, host-reported (never assumed).
//   window_present(void)   Presents the drawn backbuffer (swapBuffers path).

#include "window-backend.h"

#include "common/Exception.h"
#include "common/Module.h"

#include <algorithm>
#include <cstdint>

#define WIN_IMPORT(sym) __attribute__((import_module("love_win"), import_name(sym)))

extern "C" {
WIN_IMPORT("window_setmode") int32_t wwin_setmode(int32_t w, int32_t h,
	int32_t stencil, int32_t depth, int32_t msaa, int32_t vsync);
WIN_IMPORT("window_get_pixel_dimensions") void wwin_get_pixel_dimensions(int32_t *out_w, int32_t *out_h);
WIN_IMPORT("window_present") void wwin_present(void);
}

namespace love
{
namespace window
{

// See src/modules/window/Window.cpp. On desktop this lives in sdl/Window.cpp;
// once wrap_Window links on wasm it becomes a mandatory symbol (the base
// Window::setHighDPIAllowed calls it), so the wasm backend must define it too.
// The browser canvas has no separate "high-DPI framebuffer" toggle — the canvas
// backing size IS the pixel size — so there is nothing to configure here.
void setHighDPIAllowedImplementation(bool enable)
{
	(void) enable;
}

namespace wasm
{

Window::Window()
	: love::window::Window("love.window.wasm")
	, open(false)
	, mouseGrabbed(false)
	, windowWidth(0)
	, windowHeight(0)
	, pixelWidth(0)
	, pixelHeight(0)
	, title("")
{
}

Window::~Window()
{
	graphics.set(nullptr);
}

void Window::setGraphics(graphics::Graphics *g)
{
	graphics.set(g);
}

bool Window::setWindow(int width, int height, WindowSettings *settings)
{
	// Mirror sdl/Window::setWindow: if the window was created before graphics
	// existed, adopt the registered graphics instance now.
	if (!graphics.get())
		graphics.set(Module::getInstance<graphics::Graphics>(M_GRAPHICS));

	if (graphics.get() && graphics->isRenderTargetActive())
		throw love::Exception("love.window.setMode cannot be called while a render target is active in love.graphics.");

	WindowSettings f;
	if (settings)
		f = *settings;

	f.minwidth = std::max(f.minwidth, 1);
	f.minheight = std::max(f.minheight, 1);

	if (width <= 0) width = 800;
	if (height <= 0) height = 600;

	// (1) Create the real canvas + WebGL2 context HOST-side and make it current
	// for the love_gl imports, BEFORE graphics->setMode runs. This is the crux
	// of the context handoff: setMode calls gl.initContext() against whatever
	// context love_gl targets, so the context must exist and be current first.
	if (wwin_setmode(width, height, f.stencil ? 1 : 0, f.depth ? 1 : 0, f.msaa, f.vsync) != 1)
		throw love::Exception("Could not create window: the host could not create a WebGL2 context.");

	// (2) Read the canvas's real backing dimensions from the host. DPI scale is
	// 1.0 on the canvas, so window units and pixels coincide. The host writes
	// both out-params unconditionally, so there is no fallback to seed.
	int32_t pw = 0, ph = 0;
	wwin_get_pixel_dimensions(&pw, &ph);
	pixelWidth = pw;
	pixelHeight = ph;
	windowWidth = width;
	windowHeight = height;

	open = true;

	this->settings = f;

	// (3) Hand the now-current context to the opengl backend, exactly as
	// sdl/Window does (context pointer ignored by setMode; pass nullptr like the
	// graphics witnesses did). Backbuffer dims are the host-reported pixel size,
	// window dims via fromPixels (DPI 1.0).
	if (graphics.get())
	{
		double scaledw, scaledh;
		fromPixels((double) pixelWidth, (double) pixelHeight, scaledw, scaledh);

		graphics::Graphics::BackbufferSettings backbufferSettings;
		backbufferSettings.width = (int) scaledw;
		backbufferSettings.height = (int) scaledh;
		backbufferSettings.pixelWidth = pixelWidth;
		backbufferSettings.pixelHeight = pixelHeight;
		backbufferSettings.stencil = f.stencil;
		backbufferSettings.depth = f.depth;
		backbufferSettings.msaa = f.msaa;

		graphics->setMode(nullptr, backbufferSettings);

		this->settings.msaa = graphics->getBackbufferMSAA();
	}

	return true;
}

void Window::getWindow(int &width, int &height, WindowSettings &settings)
{
	width = windowWidth;
	height = windowHeight;
	settings = this->settings;
}

void Window::close()
{
	// The canvas persists (there is no OS window to destroy); drop the open flag
	// so isActive() gates graphics off, matching close semantics.
	open = false;
}

bool Window::setFullscreen(bool /*fullscreen*/, FullscreenType /*fstype*/)
{
	// No native fullscreen mode-set on a canvas; report unchanged.
	return false;
}

bool Window::setFullscreen(bool /*fullscreen*/)
{
	return false;
}

bool Window::onSizeChanged(int width, int height)
{
	// Mirror sdl/Window::onSizeChanged: record the new size and tell graphics the
	// backbuffer changed. The host canvas is authoritative for pixel size.
	windowWidth = width;
	windowHeight = height;
	pixelWidth = width;
	pixelHeight = height;

	if (graphics.get())
	{
		double scaledw, scaledh;
		fromPixels((double) pixelWidth, (double) pixelHeight, scaledw, scaledh);
		graphics->backbufferChanged((int) scaledw, (int) scaledh, pixelWidth, pixelHeight);
	}

	return true;
}

int Window::getDisplayCount() const
{
	return 1;
}

const char *Window::getDisplayName(int /*displayindex*/) const
{
	return "canvas";
}

Window::DisplayOrientation Window::getDisplayOrientation(int /*displayindex*/) const
{
	return ORIENTATION_UNKNOWN;
}

std::vector<Window::DisplayMode> Window::getFullscreenModes(int /*displayindex*/) const
{
	// The one "mode" is the current canvas size.
	std::vector<DisplayMode> modes;
	DisplayMode m;
	m.width = windowWidth;
	m.height = windowHeight;
	m.refreshRate = 0.0;
	modes.push_back(m);
	return modes;
}

void Window::getDesktopDimensions(int /*displayindex*/, int &width, int &height) const
{
	width = windowWidth;
	height = windowHeight;
}

void Window::setPosition(int /*x*/, int /*y*/, int /*displayindex*/, bool /*waitForSync*/)
{
	// A canvas has no freestanding position; no-op.
}

void Window::getPosition(int &x, int &y, int &displayindex)
{
	x = 0;
	y = 0;
	displayindex = 0;
}

Rect Window::getSafeArea() const
{
	Rect r = {0, 0, windowWidth, windowHeight};
	return r;
}

bool Window::isOpen() const
{
	return open;
}

void Window::setWindowTitle(const std::string &title)
{
	this->title = title;
}

const std::string &Window::getWindowTitle() const
{
	return title;
}

bool Window::setIcon(love::image::ImageData * /*imgd*/)
{
	// A canvas has no window icon.
	return false;
}

love::image::ImageData *Window::getIcon()
{
	return nullptr;
}

void Window::setVSync(int vsync)
{
	// The browser paces presentation via requestAnimationFrame; record the
	// requested value so getVSync round-trips, but there is nothing to toggle.
	settings.vsync = vsync;
}

int Window::getVSync() const
{
	return settings.vsync;
}

void Window::setDisplaySleepEnabled(bool /*enable*/)
{
}

bool Window::isDisplaySleepEnabled() const
{
	return true;
}

void Window::minimize() {}
void Window::maximize() {}
void Window::restore() {}
void Window::focus() {}

bool Window::isMaximized() const
{
	return false;
}

bool Window::isMinimized() const
{
	return false;
}

void Window::swapBuffers()
{
	// The present path: hand the drawn backbuffer to the host. Called by
	// Graphics::present() after flush/resolve/screenshot readback.
	wwin_present();
}

bool Window::hasFocus() const
{
	return true;
}

bool Window::hasMouseFocus() const
{
	return true;
}

bool Window::isVisible() const
{
	return open;
}

bool Window::isOccluded() const
{
	return false;
}

void Window::setMouseGrab(bool grab)
{
	mouseGrabbed = grab;
}

bool Window::isMouseGrabbed() const
{
	return mouseGrabbed;
}

int Window::getWidth() const
{
	return windowWidth;
}

int Window::getHeight() const
{
	return windowHeight;
}

int Window::getPixelWidth() const
{
	return pixelWidth;
}

int Window::getPixelHeight() const
{
	return pixelHeight;
}

void Window::clampPositionInWindow(double *wx, double *wy) const
{
	// No window open (dimensions 0): nothing to clamp against — leave unchanged
	// rather than clamp every coordinate to -1.
	if (getWidth() <= 0 || getHeight() <= 0)
		return;
	if (wx != nullptr)
		*wx = std::min(std::max(0.0, *wx), (double) getWidth() - 1);
	if (wy != nullptr)
		*wy = std::min(std::max(0.0, *wy), (double) getHeight() - 1);
}

void Window::windowToPixelCoords(double *x, double *y) const
{
	if (windowWidth <= 0 || windowHeight <= 0)  // no window: avoid x/0 -> inf/NaN
		return;
	if (x != nullptr)
		*x = (*x) * ((double) pixelWidth / (double) windowWidth);
	if (y != nullptr)
		*y = (*y) * ((double) pixelHeight / (double) windowHeight);
}

void Window::pixelToWindowCoords(double *x, double *y) const
{
	if (pixelWidth <= 0 || pixelHeight <= 0)  // no window: avoid x/0 -> inf/NaN
		return;
	if (x != nullptr)
		*x = (*x) * ((double) windowWidth / (double) pixelWidth);
	if (y != nullptr)
		*y = (*y) * ((double) windowHeight / (double) pixelHeight);
}

void Window::windowToDPICoords(double *x, double *y) const
{
	double px = x != nullptr ? *x : 0.0;
	double py = y != nullptr ? *y : 0.0;

	windowToPixelCoords(&px, &py);

	double dpix = 0.0;
	double dpiy = 0.0;

	fromPixels(px, py, dpix, dpiy);

	if (x != nullptr)
		*x = dpix;
	if (y != nullptr)
		*y = dpiy;
}

void Window::DPIToWindowCoords(double *x, double *y) const
{
	double dpix = x != nullptr ? *x : 0.0;
	double dpiy = y != nullptr ? *y : 0.0;

	double px = 0.0;
	double py = 0.0;

	toPixels(dpix, dpiy, px, py);
	pixelToWindowCoords(&px, &py);

	if (x != nullptr)
		*x = px;
	if (y != nullptr)
		*y = py;
}

double Window::getDPIScale() const
{
	return 1.0;
}

double Window::getNativeDPIScale() const
{
	return 1.0;
}

double Window::toPixels(double x) const
{
	return x * getDPIScale();
}

void Window::toPixels(double wx, double wy, double &px, double &py) const
{
	double scale = getDPIScale();
	px = wx * scale;
	py = wy * scale;
}

double Window::fromPixels(double x) const
{
	return x / getDPIScale();
}

void Window::fromPixels(double px, double py, double &wx, double &wy) const
{
	double scale = getDPIScale();
	wx = px / scale;
	wy = py / scale;
}

void *Window::getHandle() const
{
	// The real GL/canvas handle lives host-side; there is no wasm-visible pointer.
	return nullptr;
}

bool Window::showMessageBox(const std::string & /*title*/, const std::string & /*message*/, MessageBoxType /*type*/, bool /*attachtowindow*/)
{
	// No native dialog surface; report the box was not shown.
	return false;
}

int Window::showMessageBox(const MessageBoxData &data)
{
	// Return the enter/default button index, matching a dismissed dialog.
	return data.enterButtonIndex;
}

void Window::showFileDialog(const FileDialogData & /*data*/, FileDialogCallback callback, void *context)
{
	// No native file dialog; invoke the callback with an empty selection so the
	// caller's continuation runs deterministically instead of hanging.
	if (callback != nullptr)
	{
		std::vector<std::string> files;
		callback(context, files, nullptr, nullptr);
	}
}

void Window::requestAttention(bool /*continuous*/)
{
}

Window::SystemTheme Window::getSystemTheme() const
{
	return THEME_UNKNOWN;
}

} // wasm
} // window
} // love
