/**
 * Raw-GL readback witness (build-order step 4, sub-step 4.1a).
 *
 * The graphics analog of the audio witness's tone recovery: prove the WebGL2
 * import plumbing end to end — wasm calls the love_gl imports with the right
 * arguments, the host clears a real (or mock) framebuffer, and glReadPixels
 * writes the cleared pixel BACK into wasm linear memory where wasm reads it —
 * separately from LÖVE's thick opengl::Graphics, so a plumbing failure is told
 * apart from a backend-bringup failure. This isolates the import mechanism +
 * host + readback round-trip; the full backend is witnessed by 4.1c.
 *
 * A command module (main / _start): set a known clear color, clear, read one
 * pixel back, compare within a rounding tolerance, report, exit 0/1. It talks
 * to the same import_module("love_gl") surface the generated shim uses, but
 * declares only the three entry points it needs so it stays dependency-free
 * (no glad, no backend) — a true isolation of the seam.
 */
#include <cstdio>
#include <cstdlib>

#define GL_IMPORT(sym) __attribute__((import_module("love_gl"), import_name(sym)))

extern "C" {
GL_IMPORT("glClearColor") void glClearColor(float r, float g, float b, float a);
GL_IMPORT("glClear")      void glClear(unsigned int mask);
GL_IMPORT("glReadPixels") void glReadPixels(int x, int y, int w, int h,
                                            unsigned int format, unsigned int type, void *pixels);
}

int main()
{
	// GL enum literals (kept inline so the witness needs no glad header).
	const unsigned int GL_COLOR_BUFFER_BIT = 0x00004000;
	const unsigned int GL_RGBA             = 0x1908;
	const unsigned int GL_UNSIGNED_BYTE    = 0x1401;

	// Exact 8-bit values: 0.2*255=51, 0.4*255=102, 0.6*255=153, 1.0*255=255.
	glClearColor(0.2f, 0.4f, 0.6f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);

	unsigned char px[4] = {0, 0, 0, 0};
	glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);

	const int er = 51, eg = 102, eb = 153, ea = 255, tol = 2;
	const bool ok = abs(px[0] - er) <= tol && abs(px[1] - eg) <= tol
	             && abs(px[2] - eb) <= tol && abs(px[3] - ea) <= tol;

	printf("GL-WITNESS: readback rgba=(%d,%d,%d,%d) expected~(%d,%d,%d,%d) -> %s\n",
	       px[0], px[1], px[2], px[3], er, eg, eb, ea, ok ? "PASS" : "FAIL");
	return ok ? 0 : 1;
}
