// Vendored-libogg witness: prove the Ogg framing layer actually works in wasm.
// Writes a packet into a stream, flushes it to a page, syncs the raw bytes back
// through a fresh reader, and requires the packet to round-trip — data plus its
// b_o_s/e_o_s flags. That exercises framing.c + bitwise.c end to end (the whole
// library). A pure-C command module: writes the transcript to stdout, exits 0
// only on OGG-WITNESS: PASS.
#include <ogg/ogg.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    ogg_stream_state os_w, os_r;
    ogg_sync_state oy;
    ogg_page og;
    ogg_packet op, op2;

    ogg_stream_init(&os_w, 0x5eed);
    ogg_sync_init(&oy);
    ogg_stream_init(&os_r, 0x5eed);

    const char *msg = "love-wasi ogg framing witness";
    op.packet = (unsigned char *)msg;
    op.bytes = (long)strlen(msg);
    op.b_o_s = 1;
    op.e_o_s = 1;
    op.granulepos = 42;
    op.packetno = 0;
    ogg_stream_packetin(&os_w, &op);

    int pages = 0;
    while (ogg_stream_flush(&os_w, &og)) {
        char *b = ogg_sync_buffer(&oy, og.header_len);
        memcpy(b, og.header, og.header_len);
        ogg_sync_wrote(&oy, og.header_len);
        b = ogg_sync_buffer(&oy, og.body_len);
        memcpy(b, og.body, og.body_len);
        ogg_sync_wrote(&oy, og.body_len);
        pages++;
    }

    ogg_page pg;
    int got = 0;
    while (ogg_sync_pageout(&oy, &pg) == 1) {
        ogg_stream_pagein(&os_r, &pg);
        while (ogg_stream_packetout(&os_r, &op2) == 1) got = 1;
    }

    int ok = got && op2.bytes == op.bytes &&
             memcmp(op2.packet, msg, op.bytes) == 0 &&
             op2.b_o_s != 0 && op2.e_o_s != 0;
    printf("ok   round-trip: %ld bytes, b_o_s=%ld e_o_s=%ld, %d page(s)\n",
           op2.bytes, op2.b_o_s, op2.e_o_s, pages);
    printf(ok ? "OGG-WITNESS: PASS\n" : "OGG-WITNESS: FAIL\n");
    return ok ? 0 : 1;
}
