// Vendored-HarfBuzz witness: prove it actually shapes text in wasm, over the
// vendored FreeType (the hb-ft integration LÖVE's HarfbuzzShaper uses). Shapes
// "Hello" with LÖVE's bundled Vera.ttf (embedded by run.sh as vera_font.h) and
// checks the glyph run: five glyphs, all mapped (codepoint != .notdef), a
// positive advance on the first. A command module: writes the transcript to
// stdout, exits 0 only on HB-SHAPE: PASS.
#include <hb.h>
#include <hb-ft.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include <stdio.h>
#include "vera_font.h"   // vera_ttf[], vera_ttf_len

int main(void)
{
    FT_Library lib;
    if (FT_Init_FreeType(&lib)) { printf("HB-SHAPE: FAIL (ft init)\n"); return 1; }
    FT_Face face;
    if (FT_New_Memory_Face(lib, vera_ttf, (FT_Long)vera_ttf_len, 0, &face)) {
        printf("HB-SHAPE: FAIL (face)\n"); return 1;
    }
    FT_Set_Pixel_Sizes(face, 0, 32);

    hb_font_t *font = hb_ft_font_create_referenced(face);
    hb_buffer_t *buf = hb_buffer_create();
    hb_buffer_add_utf8(buf, "Hello", -1, 0, -1);
    hb_buffer_guess_segment_properties(buf);
    hb_shape(font, buf, NULL, 0);

    unsigned int n = 0;
    hb_glyph_info_t *info = hb_buffer_get_glyph_infos(buf, &n);
    hb_glyph_position_t *pos = hb_buffer_get_glyph_positions(buf, &n);
    printf("ok   shaped \"Hello\": %u glyphs\n", n);
    printf("ok   glyph ids:");
    int all_mapped = 1;
    for (unsigned i = 0; i < n; i++) {
        printf(" %u", info[i].codepoint);
        if (info[i].codepoint == 0) all_mapped = 0;   // 0 == .notdef == unmapped
    }
    printf("\n");

    int ok = (n == 5) && all_mapped && (pos[0].x_advance > 0);
    hb_buffer_destroy(buf);
    hb_font_destroy(font);
    FT_Done_Face(face);
    FT_Done_FreeType(lib);

    printf(ok ? "HB-SHAPE: PASS\n" : "HB-SHAPE: FAIL (bad glyph run)\n");
    return ok ? 0 : 1;
}
