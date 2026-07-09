#!/usr/bin/env bash
# Build vendored libogg to a wasm32-wasi static archive. Plain C, no exceptions
# and no setjmp, so it needs neither $EH_FLAGS nor the sysroot — just the target
# and the vendored headers (including our generated config_types.h). The archive
# links cleanly into the EH artifact (love.sound) as neutral objects.
#
#   OUT=libogg.a wasi/vendor/libogg/build.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-libogg.a}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

objs=()
for f in framing bitwise; do
  clang-20 --target=wasm32-wasi -O2 -I"$HERE/include" \
    -c "$HERE/src/$f.c" -o "$TMP/$f.o"
  objs+=("$TMP/$f.o")
done

rm -f "$OUT"
llvm-ar-20 rcs "$OUT" "${objs[@]}"
echo "built $OUT (libogg, ${#objs[@]} objects, plain C)"
