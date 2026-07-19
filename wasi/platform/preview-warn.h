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

// love-wasi platform seam — the preview-limitation warning mechanism (issue
// #27). A small, host-routed, ONE-TIME, NON-FATAL warning that a
// preview-limited feature was used.
//
// This is love-wasi's OWN diagnostic surface, NOT an engine one: it is used
// only by the fork's out-of-tree warned-stub backends (e.g. the love.sensor
// wasm backend, wasi/platform/sensor-backend.cpp), never wired into any shared
// engine compute/graphics path — that would be a fork-private, un-upstreamable
// divergence. The src tree stays upstream-shaped; this lives out-of-tree in
// wasi/platform/ and is reached via -I wasi/platform.
//
// Routing: on the FIRST use of a given key, one line
//     [love-wasi preview] <message>
// is emitted to the host over stderr (fd 2). The browser WASI shim's fd_write
// accumulates every fd into its host tap (wasi/host/wasi-shim.mjs), and
// node:wasi routes fd 2 to the process's stderr, so the line reaches the host
// on both witness legs. Repeated use of the same key is silent (deduped by a
// static set). The call NEVER throws and returns nothing — a warned stub can
// call it unconditionally without changing its own (benign) control flow.
#ifndef LOVE_WASI_PLATFORM_PREVIEW_WARN_H
#define LOVE_WASI_PLATFORM_PREVIEW_WARN_H

#ifdef __cplusplus
extern "C"
{
#endif

// Emit `[love-wasi preview] <message>` to the host over stderr the first time
// `key` is seen; subsequent calls with the same `key` are silent. Never throws;
// returns nothing. Both arguments must be non-null, NUL-terminated strings.
void preview_warn_once(const char *key, const char *message);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // LOVE_WASI_PLATFORM_PREVIEW_WARN_H
