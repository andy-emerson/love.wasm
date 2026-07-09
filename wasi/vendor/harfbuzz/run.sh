#!/usr/bin/env bash
# One-command witness for vendored HarfBuzz: build HarfBuzz + FreeType, link a
# command module that shapes "Hello" with hb-ft over LÖVE's bundled Vera.ttf,
# and require HB-SHAPE: PASS under node:wasi, real Chromium, and wasmtime.
#
#   PREFIX=/path/to/wasi-eh wasi/vendor/harfbuzz/run.sh
#
# PREFIX is the step-0 sysroot (needs setjmp.h + wasi-setjmp.o for FreeType).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
FT="$ROOT/wasi/vendor/freetype"
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/wasi/toolchain/eh-flags.sh"
source "$ROOT/wasi/witness/legs.sh"

# 1. Build both archives.
PREFIX="$PREFIX" OUT="$TMP/libfreetype.a" "$FT/build.sh"
PREFIX="$PREFIX" OUT="$TMP/libharfbuzz.a" "$HERE/build.sh"

# 2. Embed the font.
python3 "$ROOT/wasi/witness/embed.py" "$ROOT/extra/resources/Vera.ttf" vera_ttf > "$TMP/vera_font.h"

# 3. Link the witness against both archives + the sysroot's setjmp/EH runtime.
# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi -O2 $EH_FLAGS -std=c++17 -DHAVE_FREETYPE=1 \
  -nostdinc++ -I"$PREFIX/include/c++/v1" -I"$PREFIX/include" \
  -I"$HERE/src" -I"$FT/include" -I"$TMP" \
  -c "$HERE/witness.cpp" -o "$TMP/witness.o"
# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi $EH_FLAGS -Wno-unused-command-line-argument \
  "$TMP/witness.o" "$TMP/libharfbuzz.a" "$TMP/libfreetype.a" \
  "$PREFIX/lib/wasi-setjmp.o" "$PREFIX/lib/unwind-wasm.o" \
  -L"$PREFIX/lib" -lc++ -lc++abi \
  -o "$TMP/hb-witness.wasm"

witness_legs "$TMP/hb-witness.wasm" "HB-SHAPE: PASS" check-eh
echo "HarfBuzz witness: shaped text in wasm on node + browser$(witness_wasmtime_suffix)"
