#!/usr/bin/env bash
# Build vendored libvorbis (the decode subset) to a wasm32-wasi static archive.
# Plain C, no exceptions/setjmp — needs neither $EH_FLAGS nor the sysroot, just
# the target and the vendored headers, plus wasi/vendor/libogg for <ogg/ogg.h>.
# The archive links into the EH artifact (love.sound) as neutral objects.
#
#   OUT=libvorbis.a wasi/vendor/libvorbis/build.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
OGGINC="$ROOT/wasi/vendor/libogg/include"
OUT=${OUT:-libvorbis.a}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

objs=()
for f in "$HERE"/lib/*.c; do
  o="$TMP/$(basename "$f" .c).o"
  clang-20 --target=wasm32-wasi -O2 \
    -I"$HERE/include" -I"$HERE/lib" -I"$OGGINC" \
    -c "$f" -o "$o"
  objs+=("$o")
done

rm -f "$OUT"
llvm-ar-20 rcs "$OUT" "${objs[@]}"
echo "built $OUT (libvorbis decode subset, ${#objs[@]} objects, plain C)"
