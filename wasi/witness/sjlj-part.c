// The setjmp/longjmp half of the SjLj+EH witness (wasi/witness/sjlj-eh.cpp).
// A C translation unit compiled with $EH_FLAGS $SJLJ_FLAGS — the exact shape of
// how vendored FreeType uses setjmp (ftgrays.c, ttcmap.c) — linked alongside a
// C++ wasm-EH TU that is NOT compiled with the SjLj flag. Returns 42, delivered
// by a longjmp back through setjmp.
#include <setjmp.h>

static jmp_buf jb;

int sjlj_roundtrip(void)
{
    volatile int v = 0;
    if (setjmp(jb) != 0)
        return v;         // resumes here after the longjmp; v is now 42
    v = 42;
    longjmp(jb, 1);
    return -1;            // unreachable
}
