#!/usr/bin/env bash
# One-command witness for vendored libogg: build the archive, link a pure-C
# command module that round-trips an Ogg packet through the framing layer, and
# require OGG-WITNESS: PASS under node:wasi, real Chromium, and Firefox.
#
#   wasi/vendor/libogg/run.sh
#
# No sysroot needed: libogg is plain C with no exceptions/setjmp, so the witness
# links without libc++ and there is no wasm-EH encoding to gate.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/wasi/witness/legs.sh"

OUT="$TMP/libogg.a" "$HERE/build.sh"

clang-20 --target=wasm32-wasi -O2 -I"$HERE/include" \
  -c "$HERE/witness.c" -o "$TMP/witness.o"
clang-20 --target=wasm32-wasi -O2 \
  "$TMP/witness.o" "$TMP/libogg.a" -o "$TMP/ogg-witness.wasm"

# Pure C, no wasm-EH → no encoding check (3rd arg omitted).
witness_legs "$TMP/ogg-witness.wasm" "OGG-WITNESS: PASS"
echo "libogg witness: framing round-trip in wasm on node + browser$(witness_firefox_suffix)"
