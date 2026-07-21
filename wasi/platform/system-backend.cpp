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

// love-wasi platform seam — build-order step 6.6 implementation. See the header
// (system-backend.h) for the design: real browser capabilities ride host imports
// (processor count, clipboard, openURL, locales); genuinely-absent ones are
// honest defaults (memory size 0, power unknown).

#include "system-backend.h"

#include <cstdint>

// ── The love_system host seam ─────────────────────────────────────────────────
//
// Declared with the same import_module attribute the fs/window/gamepad backends
// use, so lld emits them as wasm imports (no --allow-undefined). All fulfilled
// host-side (wasi/host/system-host.mjs). String reads use the same two-call
// size-then-copy shape as the love_fs seam, so the sync LÖVE contract holds over
// values the host may compute lazily.
//   system_processor_count()             -> navigator.hardwareConcurrency (>= 1)
//   system_clipboard_size()              -> current clipboard byte length
//   system_clipboard_read(buf, cap)      -> bytes copied (<= cap)
//   system_clipboard_write(ptr, len)     -> set the clipboard text
//   system_open_url(ptr, len)            -> 1 opened / 0 not
//   system_locale_count()               -> number of preferred locales
//   system_locale_read(index, buf, cap)  -> bytes copied (<= cap), or -1 absent
#define SYS_IMPORT(sym) __attribute__((import_module("love_system"), import_name(sym)))

extern "C" {
SYS_IMPORT("system_processor_count") int32_t wsys_processor_count();
SYS_IMPORT("system_clipboard_size") int32_t wsys_clipboard_size();
SYS_IMPORT("system_clipboard_read") int32_t wsys_clipboard_read(uint8_t *buf, int32_t cap);
SYS_IMPORT("system_clipboard_write") void wsys_clipboard_write(const char *ptr, int32_t len);
SYS_IMPORT("system_open_url") int32_t wsys_open_url(const char *ptr, int32_t len);
SYS_IMPORT("system_locale_count") int32_t wsys_locale_count();
SYS_IMPORT("system_locale_read") int32_t wsys_locale_read(int32_t index, uint8_t *buf, int32_t cap);
}

namespace love
{
namespace system
{
namespace wasm
{

System::System()
	: love::system::System("love.system.wasm")
{
}

int System::getProcessorCount() const
{
	int32_t n = wsys_processor_count();
	// navigator.hardwareConcurrency is >= 1 where present; clamp to a sane floor
	// so a host that reports 0/unknown still yields the "at least one core" the
	// LÖVE contract implies.
	return n >= 1 ? (int) n : 1;
}

int System::getMemorySize() const
{
	// The browser does not expose total system RAM in MiB (navigator.deviceMemory
	// is a coarse, privacy-capped bucket, not this figure). Honest 0/unknown.
	return 0;
}

void System::setClipboardText(const std::string &text) const
{
	wsys_clipboard_write(text.c_str(), (int32_t) text.size());
}

std::string System::getClipboardText() const
{
	int32_t size = wsys_clipboard_size();
	if (size <= 0)
		return std::string();

	std::string out;
	out.resize((size_t) size);
	int32_t n = wsys_clipboard_read(reinterpret_cast<uint8_t *>(&out[0]), size);
	if (n < 0)
		return std::string();
	out.resize((size_t) n);
	return out;
}

System::PowerState System::getPowerInfo(int &seconds, int &percent) const
{
	// The Battery Status API is removed/gated across the major engines; there is
	// no reliable browser source for battery seconds/percent. Report unknown —
	// exactly what desktop returns when the platform has no battery reporting.
	seconds = -1;
	percent = -1;
	return POWER_UNKNOWN;
}

bool System::openURL(const std::string &url) const
{
	return wsys_open_url(url.c_str(), (int32_t) url.size()) != 0;
}

std::vector<std::string> System::getPreferredLocales() const
{
	std::vector<std::string> locales;
	int32_t count = wsys_locale_count();
	for (int32_t i = 0; i < count; i++)
	{
		char buf[128];
		int32_t n = wsys_locale_read(i, reinterpret_cast<uint8_t *>(buf), (int32_t) sizeof(buf));
		if (n < 0)
			continue;
		if (n > (int32_t) sizeof(buf))
			n = (int32_t) sizeof(buf);
		locales.emplace_back(buf, (size_t) n);
	}
	return locales;
}

} // wasm
} // system
} // love
