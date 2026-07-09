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

# 1. Build both archives.
PREFIX="$PREFIX" OUT="$TMP/libfreetype.a" "$FT/build.sh"
PREFIX="$PREFIX" OUT="$TMP/libharfbuzz.a" "$HERE/build.sh"

# 2. Embed the font.
FONT="$ROOT/extra/resources/Vera.ttf"
if command -v xxd >/dev/null 2>&1; then
  xxd -i -n vera_ttf "$FONT" > "$TMP/vera_font.h"
else
  python3 - "$FONT" > "$TMP/vera_font.h" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
print("unsigned char vera_ttf[] = {" + ",".join(str(b) for b in d) + "};")
print("unsigned int vera_ttf_len = %d;" % len(d))
PY
fi

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

"$ROOT/wasi/toolchain/check-eh-encoding.sh" "$TMP/hb-witness.wasm"

W="$ROOT/wasi/witness"
echo "== node:wasi =="
node --no-warnings "$W/run-node.mjs" "$TMP/hb-witness.wasm"
echo "== chromium =="
node "$W/run-browser.mjs" "$TMP/hb-witness.wasm" "HB-SHAPE: PASS"
if python3 -c 'import wasmtime' 2>/dev/null; then
  echo "== wasmtime (Cranelift, non-V8) =="
  python3 "$W/run-wasmtime.py" "$TMP/hb-witness.wasm" "HB-SHAPE: PASS"
else
  echo "== wasmtime: skipped (wasmtime python package not installed) =="
fi

echo "HarfBuzz witness: shaped text in wasm on node + browser$(python3 -c 'import wasmtime' 2>/dev/null && echo ' + wasmtime')"
