#!/usr/bin/env bash
# One-command witness for vendored libogg: build the archive, link a pure-C
# command module that round-trips an Ogg packet through the framing layer, and
# require OGG-WITNESS: PASS under node:wasi, real Chromium, and wasmtime.
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

OUT="$TMP/libogg.a" "$HERE/build.sh"

clang-20 --target=wasm32-wasi -O2 -I"$HERE/include" \
  -c "$HERE/witness.c" -o "$TMP/witness.o"
clang-20 --target=wasm32-wasi -O2 \
  "$TMP/witness.o" "$TMP/libogg.a" -o "$TMP/ogg-witness.wasm"

W="$ROOT/wasi/witness"
echo "== node:wasi =="
node --no-warnings "$W/run-node.mjs" "$TMP/ogg-witness.wasm"
echo "== chromium =="
node "$W/run-browser.mjs" "$TMP/ogg-witness.wasm" "OGG-WITNESS: PASS"
if python3 -c 'import wasmtime' 2>/dev/null; then
  echo "== wasmtime (Cranelift, non-V8) =="
  python3 "$W/run-wasmtime.py" "$TMP/ogg-witness.wasm" "OGG-WITNESS: PASS"
else
  echo "== wasmtime: skipped (wasmtime python package not installed) =="
fi

echo "libogg witness: framing round-trip in wasm on node + browser$(python3 -c 'import wasmtime' 2>/dev/null && echo ' + wasmtime')"
