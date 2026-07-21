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

// love-wasi platform seam — build-order step 6.6: the real love.system backend
// for wasm32-wasi, on the host-import love_system seam. It replaces the SDL
// backend (which reads native OS power/clipboard/CPU state) with a thin bridge
// over a handful of host imports that map onto GENUINE browser capabilities.
//
// The split follows the whole seam's rule (readme.md): things the browser really
// has are real host imports, things it does not have are honest defaults, never
// faked native calls.
//   * getOS()               -> "Web" (the guarded seam in System.cpp getOS()).
//   * getProcessorCount()   -> navigator.hardwareConcurrency (host import).
//   * getClipboardText /
//     setClipboardText      -> a host clipboard cell (host import). The async
//                              Clipboard API is fronted by a host-held string so
//                              the synchronous LÖVE contract is preserved, the
//                              same eager-cache shape the save-dir uses.
//   * openURL()             -> window.open (host import).
//   * getPreferredLocales() -> navigator.languages (host import).
//   * getMemorySize()       -> 0 (the browser does not expose total RAM;
//                              navigator.deviceMemory is a coarse, privacy-capped
//                              bucket, not the MiB figure this returns — honest 0
//                              rather than a misleading bucket).
//   * getPowerInfo()        -> POWER_UNKNOWN (the Battery Status API is removed /
//                              gated in the major engines; unknown is the honest
//                              answer, and is exactly what desktop returns with no
//                              battery reporting).
//
// This header lives out-of-tree (readme.md: the src tree stays upstream-shaped);
// wrap_System.cpp includes it under LOVE_WASI via -I wasi/platform and constructs
// wasm::System in place of sdl::System at the one guarded factory.
#ifndef LOVE_WASI_PLATFORM_SYSTEM_BACKEND_H
#define LOVE_WASI_PLATFORM_SYSTEM_BACKEND_H

#include "common/config.h"
#include "system/System.h"

#include <string>
#include <vector>

namespace love
{
namespace system
{
namespace wasm
{

class System final : public love::system::System
{
public:

	System();
	virtual ~System() {}

	int getProcessorCount() const override;
	int getMemorySize() const override;

	void setClipboardText(const std::string &text) const override;
	std::string getClipboardText() const override;

	PowerState getPowerInfo(int &seconds, int &percent) const override;
	bool openURL(const std::string &url) const override;
	std::vector<std::string> getPreferredLocales() const override;

}; // System

} // wasm
} // system
} // love

#endif // LOVE_WASI_PLATFORM_SYSTEM_BACKEND_H
