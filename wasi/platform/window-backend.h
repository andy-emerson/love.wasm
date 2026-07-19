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

// love-wasi platform seam — build-order step 6.3: the real love.window backend
// for wasm32-wasi, on the host-import love_win seam. It replaces the SDL window
// backend (which drives a native OS window + GL context the browser has no
// access to) with a thin bridge over three host imports: window_setmode creates
// the real <canvas> + WebGL2 context HOST-side (the same GL handle the love_gl
// static imports already target — see wasi/host/webgl-win-host.mjs), and
// window_present presents it. setWindow then hands that already-current context
// to graphics->setMode(nullptr, ...) exactly the way sdl/Window does, so the
// unchanged opengl backend renders to it.
//
// This is what makes love.graphics::present() run for real: present() early-
// returns unless isActive(), which needs an open window registered as M_WINDOW.
// Once this backend is open, present() flushes, resolves, and reads the system
// backbuffer back for captureScreenshot — closing build-order step 4's last
// item on the real window/present path (not the windowless flush the graphics
// witnesses used).
//
// The backend is deliberately minimal: everything a browser canvas genuinely
// has (dimensions, DPI, present, backbuffer handoff) is real; everything a
// browser canvas does NOT have a native analog for (fullscreen modes, window
// position, icon, system dialogs, vsync control, minimize/maximize) is a quiet
// no-op or honest default rather than a faked native call — see the notes in
// window-backend.cpp at each surface.
//
// This header lives out-of-tree (readme.md: the src tree stays upstream-shaped);
// wrap_Window.cpp includes it under LOVE_WASI via -I wasi/platform and
// constructs wasm::Window in place of sdl::Window at the one guarded factory.
#ifndef LOVE_WASI_PLATFORM_WINDOW_BACKEND_H
#define LOVE_WASI_PLATFORM_WINDOW_BACKEND_H

#include "common/config.h"
#include "common/Object.h"
#include "window/Window.h"
#include "graphics/Graphics.h"

#include <string>
#include <vector>

namespace love
{
namespace window
{
namespace wasm
{

class Window final : public love::window::Window
{
public:

	Window();
	virtual ~Window();

	void setGraphics(graphics::Graphics *graphics) override;

	bool setWindow(int width = 800, int height = 600, WindowSettings *settings = nullptr) override;
	void getWindow(int &width, int &height, WindowSettings &settings) override;

	void close() override;

	bool setFullscreen(bool fullscreen, FullscreenType fstype) override;
	bool setFullscreen(bool fullscreen) override;

	bool onSizeChanged(int width, int height) override;

	int getDisplayCount() const override;
	const char *getDisplayName(int displayindex) const override;
	DisplayOrientation getDisplayOrientation(int displayindex) const override;
	std::vector<DisplayMode> getFullscreenModes(int displayindex) const override;

	void getDesktopDimensions(int displayindex, int &width, int &height) const override;

	void setPosition(int x, int y, int displayindex, bool waitForSync) override;
	void getPosition(int &x, int &y, int &displayindex) override;

	Rect getSafeArea() const override;

	bool isOpen() const override;

	void setWindowTitle(const std::string &title) override;
	const std::string &getWindowTitle() const override;

	bool setIcon(love::image::ImageData *imgd) override;
	love::image::ImageData *getIcon() override;

	void setVSync(int vsync) override;
	int getVSync() const override;

	void setDisplaySleepEnabled(bool enable) override;
	bool isDisplaySleepEnabled() const override;

	void minimize() override;
	void maximize() override;
	void restore() override;
	void focus() override;

	bool isMaximized() const override;
	bool isMinimized() const override;

	void swapBuffers() override;

	bool hasFocus() const override;
	bool hasMouseFocus() const override;

	bool isVisible() const override;
	bool isOccluded() const override;

	void setMouseGrab(bool grab) override;
	bool isMouseGrabbed() const override;

	int getWidth() const override;
	int getHeight() const override;
	int getPixelWidth() const override;
	int getPixelHeight() const override;

	void clampPositionInWindow(double *wx, double *wy) const override;

	void windowToPixelCoords(double *x, double *y) const override;
	void pixelToWindowCoords(double *x, double *y) const override;
	void windowToDPICoords(double *x, double *y) const override;
	void DPIToWindowCoords(double *x, double *y) const override;

	double getDPIScale() const override;
	double getNativeDPIScale() const override;

	double toPixels(double x) const override;
	void toPixels(double wx, double wy, double &px, double &py) const override;
	double fromPixels(double x) const override;
	void fromPixels(double px, double py, double &wx, double &wy) const override;

	void *getHandle() const override;

	bool showMessageBox(const std::string &title, const std::string &message, MessageBoxType type, bool attachtowindow) override;
	int showMessageBox(const MessageBoxData &data) override;

	void showFileDialog(const FileDialogData &data, FileDialogCallback callback, void *context) override;

	void requestAttention(bool continuous) override;

	SystemTheme getSystemTheme() const override;

private:

	StrongRef<graphics::Graphics> graphics;

	bool open;
	bool mouseGrabbed;

	// Window-space (logical) and backing (pixel) dimensions. DPI scale is 1.0 on
	// the browser canvas, so these two agree, but the pair is kept distinct to
	// match the base API and the toPixels/fromPixels contract.
	int windowWidth;
	int windowHeight;
	int pixelWidth;
	int pixelHeight;

	std::string title;
	WindowSettings settings;

}; // Window

} // wasm
} // window
} // love

#endif // LOVE_WASI_PLATFORM_WINDOW_BACKEND_H
