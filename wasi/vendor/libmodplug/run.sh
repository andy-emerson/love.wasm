#!/usr/bin/env bash
# One-command witness for vendored libmodplug: build the archive, synthesize a
# minimal audible MOD, link a command module that loads + decodes it via the
# libmodplug C API, and require MODPLUG-WITNESS: PASS under node:wasi, real
# Chromium, and wasmtime.
#
#   PREFIX=/path/to/wasi-eh wasi/vendor/libmodplug/run.sh
#
# PREFIX is the step-0 sysroot (libmodplug is C++ → needs libc++/libc++abi).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/wasi/toolchain/eh-flags.sh"

PREFIX="$PREFIX" OUT="$TMP/libmodplug.a" "$HERE/build.sh"

# Synthesize the test module and embed it.
python3 "$HERE/make-witness-mod.py" > "$TMP/witness.mod"
python3 - "$TMP/witness.mod" > "$TMP/mod_data.h" <<'PY'
import sys
d = open(sys.argv[1], "rb").read()
print("unsigned char mod_bytes[] = {" + ",".join(str(b) for b in d) + "};")
print("unsigned int mod_len = %d;" % len(d))
PY

clang-20 --target=wasm32-wasi -O2 -I"$HERE/include" -I"$TMP" \
  -c "$HERE/witness.c" -o "$TMP/witness.o"
# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi $EH_FLAGS -Wno-unused-command-line-argument \
  "$TMP/witness.o" "$TMP/libmodplug.a" \
  "$PREFIX/lib/unwind-wasm.o" -L"$PREFIX/lib" -lc++ -lc++abi \
  -o "$TMP/mp-witness.wasm"

"$ROOT/wasi/toolchain/check-eh-encoding.sh" "$TMP/mp-witness.wasm"

W="$ROOT/wasi/witness"
echo "== node:wasi =="
node --no-warnings "$W/run-node.mjs" "$TMP/mp-witness.wasm"
echo "== chromium =="
node "$W/run-browser.mjs" "$TMP/mp-witness.wasm" "MODPLUG-WITNESS: PASS"
if python3 -c 'import wasmtime' 2>/dev/null; then
  echo "== wasmtime (Cranelift, non-V8) =="
  python3 "$W/run-wasmtime.py" "$TMP/mp-witness.wasm" "MODPLUG-WITNESS: PASS"
else
  echo "== wasmtime: skipped (wasmtime python package not installed) =="
fi

echo "libmodplug witness: decoded tracker music in wasm on node + browser$(python3 -c 'import wasmtime' 2>/dev/null && echo ' + wasmtime')"
