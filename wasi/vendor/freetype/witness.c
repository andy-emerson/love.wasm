// Vendored-FreeType witness: prove the archive actually rasterizes in wasm, not
// just that it links. Loads LÖVE's bundled Vera.ttf (embedded by run.sh as
// vera_font.h), then rasterizes glyph 'A' via FT_LOAD_RENDER — which drives the
// smooth rasterizer (smooth/ftgrays.c), the exact code path that needs
// setjmp/longjmp. A non-empty bitmap means the whole chain — FreeType + the
// sysroot's wasm setjmp support + wasm-EH — works. Command module: writes the
// transcript to stdout, exits 0 only on FT-RENDER: PASS.
#include <ft2build.h>
#include FT_FREETYPE_H
#include <stdio.h>
#include "vera_font.h"   // const unsigned char vera_ttf[]; unsigned int vera_ttf_len;

int main(void)
{
    FT_Library lib;
    if (FT_Init_FreeType(&lib)) { printf("FT-RENDER: FAIL (init)\n"); return 1; }

    FT_Face face;
    if (FT_New_Memory_Face(lib, vera_ttf, (FT_Long)vera_ttf_len, 0, &face)) {
        printf("FT-RENDER: FAIL (face)\n"); return 1;
    }
    printf("ok   face: %s %s, %ld glyphs\n",
           face->family_name ? face->family_name : "?",
           face->style_name ? face->style_name : "?", face->num_glyphs);

    FT_Set_Pixel_Sizes(face, 0, 32);
    if (FT_Load_Char(face, 'A', FT_LOAD_RENDER)) {   // rasterizes via ftgrays (setjmp path)
        printf("FT-RENDER: FAIL (load/render)\n"); return 1;
    }

    FT_Bitmap *bm = &face->glyph->bitmap;
    int inked = 0;
    for (unsigned r = 0; r < bm->rows; r++)
        for (unsigned c = 0; c < bm->width; c++)
            if (bm->buffer[r * bm->pitch + c]) inked++;
    printf("ok   rasterized 'A': %ux%u, %d inked px\n", bm->width, bm->rows, inked);

    int ok = bm->width > 0 && bm->rows > 0 && inked > 0;
    FT_Done_Face(face);
    FT_Done_FreeType(lib);

    printf(ok ? "FT-RENDER: PASS\n" : "FT-RENDER: FAIL (empty bitmap)\n");
    return ok ? 0 : 1;
}
