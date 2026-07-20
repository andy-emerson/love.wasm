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

// love-wasi platform seam — build-order step 6.6. love::sleep for wasm32-wasi.
//
// The desktop implementation (src/common/delay.cpp) is SDL_DelayNS, which is
// EXCLUDED from every wasm build (SDL is not linked). love::sleep is declared in
// common/delay.h and called by love::timer::Timer::sleep (love.timer.sleep).
//
// This is an HONEST NO-OP, not a stub-that-fakes-work. A browser CANNOT block its
// own main thread — the frame the wasm runs on IS the browser's event-loop turn,
// and a busy-wait there would freeze the page (no rAF, no input, no present)
// rather than "wait". Frame cadence in the browser is the host's
// requestAnimationFrame, not a spin inside the guest, so there is nothing to
// sleep on: the correct browser behavior for "pause the frame N seconds" is to
// return and let the host schedule the next frame. love.timer.sleep therefore
// returns immediately here — a declared cross-platform divergence, the same class
// as the async save-dir durability note (browser-native correctness, not desktop
// byte-parity). A game that relies on a blocking sleep for pacing should use
// love.timer.getTime()/dt instead, which is faithful.
#include "common/delay.h"

namespace love
{

void sleep(double /*ms*/)
{
	// Intentionally empty — see the file comment. The browser main thread must
	// not block; the host paces frames via requestAnimationFrame.
}

} // love
