#!/usr/bin/env bash
# One-command witness for vendored FreeType: build the archive, link a command
# module that rasterizes glyph 'A' from LÖVE's bundled Vera.ttf, and require
# FT-RENDER: PASS under node:wasi, real Chromium, and wasmtime — the same three
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

# 1. Build the FreeType archive.
PREFIX="$PREFIX" OUT="$TMP/libfreetype.a" "$HERE/build.sh"

# 2. Embed the font (LÖVE's Bitstream Vera) as a C header.
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

# 3. Link the witness against the archive + the sysroot's setjmp/EH runtime.
# shellcheck disable=SC2086
clang-20 --target=wasm32-wasi -O2 $EH_FLAGS $SJLJ_FLAGS \
  -I"$HERE/wasi-config" -I"$HERE/include" -I"$PREFIX/include" -I"$TMP" \
  -c "$HERE/witness.c" -o "$TMP/witness.o"
# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi $EH_FLAGS -Wno-unused-command-line-argument \
  "$TMP/witness.o" "$TMP/libfreetype.a" \
  "$PREFIX/lib/wasi-setjmp.o" "$PREFIX/lib/unwind-wasm.o" \
  -L"$PREFIX/lib" -lc++ -lc++abi \
  -o "$TMP/ft-witness.wasm"

"$ROOT/wasi/toolchain/check-eh-encoding.sh" "$TMP/ft-witness.wasm"

W="$ROOT/wasi/witness"
echo "== node:wasi =="
node --no-warnings "$W/run-node.mjs" "$TMP/ft-witness.wasm"
echo "== chromium =="
node "$W/run-browser.mjs" "$TMP/ft-witness.wasm" "FT-RENDER: PASS"
if python3 -c 'import wasmtime' 2>/dev/null; then
  echo "== wasmtime (Cranelift, non-V8) =="
  python3 "$W/run-wasmtime.py" "$TMP/ft-witness.wasm" "FT-RENDER: PASS"
else
  echo "== wasmtime: skipped (wasmtime python package not installed) =="
fi

echo "FreeType witness: rasterized in wasm on node + browser$(python3 -c 'import wasmtime' 2>/dev/null && echo ' + wasmtime')"
