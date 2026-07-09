#!/usr/bin/env bash
# One-command witness for vendored libvorbis: build libogg + libvorbis, link a
# pure-C command module that decodes LÖVE's bundled tone.ogg via the vorbisfile
# API, and require VORBIS-WITNESS: PASS under node:wasi, real Chromium, and
# wasmtime.
#
#   wasi/vendor/libvorbis/run.sh
#
# No sysroot needed: plain C, no exceptions/setjmp, so the witness links without
# libc++ and there is no wasm-EH encoding to gate.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
OGG="$ROOT/wasi/vendor/libogg"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

OUT="$TMP/libogg.a" "$OGG/build.sh"
OUT="$TMP/libvorbis.a" "$HERE/build.sh"

# Embed the test clip.
python3 - "$ROOT/testing/resources/tone.ogg" > "$TMP/tone_ogg.h" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
print("unsigned char tone_ogg[] = {" + ",".join(str(b) for b in d) + "};")
print("unsigned int tone_ogg_len = %d;" % len(d))
PY

clang-20 --target=wasm32-wasi -O2 \
  -I"$HERE/include" -I"$OGG/include" -I"$TMP" \
  -c "$HERE/witness.c" -o "$TMP/witness.o"
clang-20 --target=wasm32-wasi -O2 \
  "$TMP/witness.o" "$TMP/libvorbis.a" "$TMP/libogg.a" -o "$TMP/vorbis-witness.wasm"

W="$ROOT/wasi/witness"
echo "== node:wasi =="
node --no-warnings "$W/run-node.mjs" "$TMP/vorbis-witness.wasm"
echo "== chromium =="
node "$W/run-browser.mjs" "$TMP/vorbis-witness.wasm" "VORBIS-WITNESS: PASS"
if python3 -c 'import wasmtime' 2>/dev/null; then
  echo "== wasmtime (Cranelift, non-V8) =="
  python3 "$W/run-wasmtime.py" "$TMP/vorbis-witness.wasm" "VORBIS-WITNESS: PASS"
else
  echo "== wasmtime: skipped (wasmtime python package not installed) =="
fi

echo "libvorbis witness: decoded Ogg Vorbis in wasm on node + browser$(python3 -c 'import wasmtime' 2>/dev/null && echo ' + wasmtime')"
