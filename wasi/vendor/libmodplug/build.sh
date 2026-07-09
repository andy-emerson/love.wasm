#!/usr/bin/env bash
# Build vendored libmodplug to a wasm32-wasi static archive. C++ (links the
# sysroot libc++/libc++abi); compiled under the repo's $EH_FLAGS so it links
# with the engine. No generated config.h — the sources include it only under
# HAVE_CONFIG_H, which we never define, so upstream defaults apply. The one
# needed override is -DHAVE_SINF (wasi-libc has sinf; without it load_pat.cpp
# redeclares a colliding static sinf).
#
#   PREFIX=/path/to/wasi-eh OUT=libmodplug.a wasi/vendor/libmodplug/build.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
OUT=${OUT:-libmodplug.a}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/wasi/toolchain/eh-flags.sh"

objs=()
for f in "$HERE"/src/*.cpp; do
  o="$TMP/$(basename "$f" .cpp).o"
  # shellcheck disable=SC2086
  clang++-20 --target=wasm32-wasi -O2 $EH_FLAGS -std=c++11 -DHAVE_SINF \
    -Wno-deprecated-register \
    -nostdinc++ -I"$PREFIX/include/c++/v1" \
    -I"$HERE/src" -I"$HERE/src/libmodplug" -I"$HERE/include/libmodplug" \
    -c "$f" -o "$o"
  objs+=("$o")
done

rm -f "$OUT"
llvm-ar-20 rcs "$OUT" "${objs[@]}"
echo "built $OUT (libmodplug, ${#objs[@]} objects, C++/libc++)"
