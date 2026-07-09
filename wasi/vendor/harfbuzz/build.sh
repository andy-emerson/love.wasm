#!/usr/bin/env bash
# Build vendored HarfBuzz (with FreeType integration) to a wasm32-wasi static
# archive, as ONE translation unit via the upstream amalgamation
# src/harfbuzz.cc. Compiled under the repo's wasm-EH flags so it links with the
# engine and libc++abi; HarfBuzz itself doesn't throw or use setjmp.
#
#   PREFIX=/path/to/wasi-eh OUT=libharfbuzz.a wasi/vendor/harfbuzz/build.sh
#
# PREFIX is the step-0 sysroot (libc++ headers + setjmp.h, the latter pulled in
# transitively through FreeType's headers). HarfBuzz needs FreeType's headers
# (hb-ft), so this depends on wasi/vendor/freetype/include — a vendor-to-vendor
# include dependency, not a link one (the consumer links both archives).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-libharfbuzz.a}
FTINC="$ROOT/wasi/vendor/freetype/include"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/wasi/toolchain/eh-flags.sh"

# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi -O2 $EH_FLAGS -std=c++17 \
  -DHAVE_FREETYPE=1 -DHB_NO_MT \
  -nostdinc++ -I"$PREFIX/include/c++/v1" -I"$PREFIX/include" \
  -I"$HERE/src" -I"$FTINC" \
  -c "$HERE/src/harfbuzz.cc" -o "$TMP/harfbuzz.o"

rm -f "$OUT"
llvm-ar-20 rcs "$OUT" "$TMP/harfbuzz.o"
echo "built $OUT (HarfBuzz amalgamation, wasm-EH, +FreeType)"
