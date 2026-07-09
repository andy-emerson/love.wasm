// Vendored-libvorbis witness: prove Ogg Vorbis actually decodes in wasm, the way
// LÖVE's love.sound VorbisDecoder does (the vorbisfile ov_* API over an
// in-memory callback source). Decodes LÖVE's bundled testing/resources/tone.ogg
// (embedded by run.sh as tone_ogg.h) and checks a plausible PCM result: real
// sample rate + channel count, a non-trivial number of decoded bytes, and
// actual signal (non-zero samples). A pure-C command module: writes the
// transcript to stdout, exits 0 only on VORBIS-WITNESS: PASS.
#include <vorbis/vorbisfile.h>
#include <string.h>
#include <stdio.h>
#include "tone_ogg.h"   // tone_ogg[], tone_ogg_len

typedef struct { const unsigned char *d; long size; long pos; } memf;

static size_t mr(void *p, size_t s, size_t n, void *v) {
    memf *m = v;
    long want = (long)(s * n), avail = m->size - m->pos;
    if (want > avail) want = avail;
    memcpy(p, m->d + m->pos, (size_t)want);
    m->pos += want;
    return s ? (size_t)(want / (long)s) : 0;
}
static int ms(void *v, ogg_int64_t off, int wh) {
    memf *m = v;
    long np = wh == SEEK_SET ? (long)off : wh == SEEK_CUR ? m->pos + (long)off : m->size + (long)off;
    if (np < 0 || np > m->size) return -1;
    m->pos = np;
    return 0;
}
static long mt(void *v) { return ((memf *)v)->pos; }
static int mc(void *v) { (void)v; return 0; }

int main(void) {
    memf mf = { tone_ogg, (long)tone_ogg_len, 0 };
    ov_callbacks cb = { mr, ms, mc, mt };
    OggVorbis_File vf;
    if (ov_open_callbacks(&mf, &vf, NULL, 0, cb)) { printf("VORBIS-WITNESS: FAIL (open)\n"); return 1; }

    vorbis_info *vi = ov_info(&vf, -1);
    long rate = vi->rate;
    int ch = vi->channels;

    char pcm[4096];
    int bs;
    long total = 0, nonzero = 0, r;
    while ((r = ov_read(&vf, pcm, sizeof pcm, 0, 2, 1, &bs)) > 0) {
        total += r;
        for (long i = 0; i < r; i++) if (pcm[i]) nonzero++;
    }
    printf("ok   decoded ogg vorbis: %ld Hz, %d ch, %ld PCM bytes (%ld non-zero)\n",
           rate, ch, total, nonzero);

    int ok = rate > 0 && ch > 0 && total > 0 && nonzero > 0;
    ov_clear(&vf);
    printf(ok ? "VORBIS-WITNESS: PASS\n" : "VORBIS-WITNESS: FAIL\n");
    return ok ? 0 : 1;
}
