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

source "$ROOT/wasi/witness/legs.sh"

OUT="$TMP/libogg.a" "$OGG/build.sh"
OUT="$TMP/libvorbis.a" "$HERE/build.sh"

# Embed the test clip.
python3 "$ROOT/wasi/witness/embed.py" "$ROOT/testing/resources/tone.ogg" tone_ogg > "$TMP/tone_ogg.h"

clang-20 --target=wasm32-wasi -O2 \
  -I"$HERE/include" -I"$OGG/include" -I"$TMP" \
  -c "$HERE/witness.c" -o "$TMP/witness.o"
clang-20 --target=wasm32-wasi -O2 \
  "$TMP/witness.o" "$TMP/libvorbis.a" "$TMP/libogg.a" -o "$TMP/vorbis-witness.wasm"

# Pure C, no wasm-EH → no encoding check (3rd arg omitted).
witness_legs "$TMP/vorbis-witness.wasm" "VORBIS-WITNESS: PASS"
echo "libvorbis witness: decoded Ogg Vorbis in wasm on node + browser$(witness_wasmtime_suffix)"
