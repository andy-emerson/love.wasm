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

// love-wasi preview-limitation warning mechanism (issue #27). See preview-warn.h
// for the contract. Implementation notes:
//   - Dedup is a function-local static std::set<std::string>: the wasm reactor
//     is single-threaded (a browser tab; the pump drives one lua_State), so no
//     lock is needed. First insert() for a key returns true and emits; every
//     later call with that key is a no-op.
//   - The line goes to stderr (fd 2) via stdio and is flushed immediately, so
//     the host tap sees it the same frame the warned stub ran. stderr is
//     unbuffered by default under wasi-libc, but the explicit fflush keeps the
//     one-line-per-first-use timing exact regardless.
//   - No exception can escape: std::set::insert can only throw std::bad_alloc,
//     which under this reactor means OOM (fatal anyway); everything else here is
//     noexcept stdio. The declared contract is "never throws", so callers in the
//     warned stubs need no guard.

#include "preview-warn.h"

#include <cstdio>
#include <set>
#include <string>

extern "C" void preview_warn_once(const char *key, const char *message)
{
	if (key == nullptr || message == nullptr)
		return;

	static std::set<std::string> seen;

	// insert() returns {iterator, inserted}. Only the first sight of a key emits.
	if (!seen.insert(std::string(key)).second)
		return;

	std::fprintf(stderr, "[love-wasi preview] %s\n", message);
	std::fflush(stderr);
}
