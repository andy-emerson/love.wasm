#!/usr/bin/env bash
# One-command witness for vendored FreeType: build the archive, link a command
# module that rasterizes glyph 'A' from LÖVE's bundled Vera.ttf, and require
# FT-RENDER: PASS under node:wasi, real Chromium, and Firefox — the same three
# engines as the step-0 witness. Reuses the witness runners.
#
#   PREFIX=/path/to/wasi-eh wasi/vendor/freetype/run.sh
#
# PREFIX is the step-0 sysroot (needs setjmp.h + wasi-setjmp.o; see #24).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/wasi/toolchain/eh-flags.sh"
source "$ROOT/wasi/witness/legs.sh"

# 1. Build the FreeType archive.
PREFIX="$PREFIX" OUT="$TMP/libfreetype.a" "$HERE/build.sh"

# 2. Embed the font (LÖVE's Bitstream Vera) as a C header.
node "$ROOT/wasi/witness/embed.mjs" "$ROOT/extra/resources/Vera.ttf" vera_ttf > "$TMP/vera_font.h"

# 3. Link the witness against the archive + the sysroot's setjmp/EH runtime.
# The witness TU itself calls no setjmp (only FreeType's archive does, built
# with $SJLJ_FLAGS by build.sh), so it compiles with $EH_FLAGS only.
# shellcheck disable=SC2086
clang-20 --target=wasm32-wasi -O2 $EH_FLAGS \
  -I"$HERE/wasi-config" -I"$HERE/include" -I"$PREFIX/include" -I"$TMP" \
  -c "$HERE/witness.c" -o "$TMP/witness.o"
# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi $EH_FLAGS -Wno-unused-command-line-argument \
  "$TMP/witness.o" "$TMP/libfreetype.a" \
  "$PREFIX/lib/wasi-setjmp.o" "$PREFIX/lib/unwind-wasm.o" \
  -L"$PREFIX/lib" -lc++ -lc++abi \
  -o "$TMP/ft-witness.wasm"

witness_legs "$TMP/ft-witness.wasm" "FT-RENDER: PASS" check-eh
echo "FreeType witness: rasterized in wasm on node + browser$(witness_firefox_suffix)"
