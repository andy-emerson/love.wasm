#!/usr/bin/env bash
# Build vendored FreeType (the TTF/OTF subset) to a wasm32-wasi static archive
# under this build's EH contract. FreeType calls setjmp/longjmp (ftgrays.c,
# ttcmap.c), so its TUs take $SJLJ_FLAGS and the sysroot's setjmp.h; the runtime
# (wasi-setjmp.o) is linked by whatever consumes libfreetype.a.
#
#   PREFIX=/path/to/wasi-eh OUT=libfreetype.a wasi/vendor/freetype/build.sh
#
# PREFIX is the step-0 sysroot (wasi/toolchain/build-libcxx-eh.sh); it provides
# libc++ headers and, crucially here, setjmp.h. Our build config lives in
# wasi-config/ and overrides upstream via -DFT_CONFIG_OPTIONS_H / _MODULES_H so
# the vendored source is never edited in place.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-libfreetype.a}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/wasi/toolchain/eh-flags.sh"

# The compiled subset — keep in sync with wasi-config/ftmodule.h.
FILES="
  base/ftsystem base/ftinit base/ftdebug base/ftbase base/ftbbox base/ftbitmap
  base/ftglyph base/ftstroke base/ftgasp base/ftmm base/ftsynth
  sfnt/sfnt truetype/truetype cff/cff
  psnames/psnames pshinter/pshinter psaux/psaux
  autofit/autofit smooth/smooth raster/raster
"

objs=()
for f in $FILES; do
  o="$TMP/$(basename "$f").o"
  # shellcheck disable=SC2086
  clang-20 --target=wasm32-wasi -O2 $EH_FLAGS $SJLJ_FLAGS \
    -DFT2_BUILD_LIBRARY \
    -DFT_CONFIG_OPTIONS_H='<ftoption.h>' -DFT_CONFIG_MODULES_H='<ftmodule.h>' \
    -I"$HERE/wasi-config" -I"$HERE/include" -I"$PREFIX/include" \
    -c "$HERE/src/$f.c" -o "$o"
  objs+=("$o")
done

rm -f "$OUT"
llvm-ar-20 rcs "$OUT" "${objs[@]}"
echo "built $OUT (${#objs[@]} objects, FreeType TTF/OTF subset, wasm-EH + SjLj)"
