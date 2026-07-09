// Vendored-libmodplug witness: prove tracker/module music actually decodes in
// wasm, the way LÖVE's love.sound ModPlugDecoder does (ModPlug_Load a module
// from memory, then ModPlug_Read PCM). The module is synthesized by
// make-witness-mod.py (a minimal audible MOD, embedded by run.sh as mod_data.h)
// so the input is deterministic and needs no committed binary. Requires the
// module to load and decode to non-silent PCM. A command module (C over the
// libmodplug C API): writes the transcript to stdout, exits 0 only on
// MODPLUG-WITNESS: PASS.
#include <libmodplug/modplug.h>
#include <stdio.h>
#include "mod_data.h"   // mod_bytes[], mod_len

int main(void)
{
    ModPlugFile *f = ModPlug_Load(mod_bytes, (int)mod_len);
    if (!f) { printf("MODPLUG-WITNESS: FAIL (load)\n"); return 1; }

    const char *name = ModPlug_GetName(f);
    int ms = ModPlug_GetLength(f);

    char pcm[8192];
    long total = 0, nonzero = 0;
    int r;
    while ((r = ModPlug_Read(f, pcm, sizeof pcm)) > 0) {
        total += r;
        for (int i = 0; i < r; i++) if (pcm[i]) nonzero++;
        if (total > 131072) break;   // a fraction of a second is plenty
    }
    printf("ok   loaded '%s' (%d ms); decoded %ld PCM bytes (%ld non-zero)\n",
           name ? name : "?", ms, total, nonzero);

    int ok = total > 0 && nonzero > 0;
    ModPlug_Unload(f);
    printf(ok ? "MODPLUG-WITNESS: PASS\n" : "MODPLUG-WITNESS: FAIL\n");
    return ok ? 0 : 1;
}
