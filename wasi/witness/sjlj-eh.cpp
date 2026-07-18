// Step-0 SjLj+EH witness. Ubuntu's wasi-libc ships no setjmp/longjmp, but
// LÖVE's FreeType dependency needs it (smooth/ftgrays.c, sfnt/ttcmap.c). On
// wasm, setjmp is implemented ON TOP OF wasm exception handling (wasi-libc's
// rt.c throws a __c_longjmp tag), so it rides on the same standardized-EH
// runtime this repo already builds — installed into the sysroot by
// wasi/toolchain/build-libcxx-eh.sh (setjmp.h + wasi-setjmp.o).
//
// This witness proves the two mechanisms coexist in ONE linked module, the way
// vendored FreeType (C, SjLj) will link with the engine (C++, wasm-EH): the C
// half (sjlj-part.c, $SJLJ_FLAGS) does a setjmp/longjmp roundtrip; this C++
// half (wasm-EH, no SjLj flag) catches a thrown exception. A command module —
// writes the transcript to stdout and exits 0 only if both hold. Driven by
// wasi/witness/run.sh under node:wasi, real Chromium, and Firefox — the same
// three engines as the EH witness.
#include <cstdio>
#include <cstring>
#include <stdexcept>

extern "C" int sjlj_roundtrip(void);

int main()
{
    int fails = 0;

    // Leg 1: setjmp/longjmp via the sysroot's wasm SjLj runtime.
    int s = sjlj_roundtrip();
    bool sjlj_ok = s == 42;
    printf("%s setjmp/longjmp roundtrip (got %d)\n", sjlj_ok ? "ok  " : "FAIL", s);
    if (!sjlj_ok) fails++;

    // Leg 2: a standardized-wasm-EH catch in the same module.
    bool eh_ok = false;
    try {
        throw std::runtime_error("sjlj-eh witness throw");
    } catch (const std::exception &e) {
        eh_ok = std::strcmp(e.what(), "sjlj-eh witness throw") == 0;
    }
    printf("%s C++ wasm-EH catch alongside SjLj\n", eh_ok ? "ok  " : "FAIL");
    if (!eh_ok) fails++;

    printf(fails == 0 ? "SJLJ-EH-WITNESS: PASS\n" : "SJLJ-EH-WITNESS: FAIL\n");
    return fails == 0 ? 0 : 1;
}
