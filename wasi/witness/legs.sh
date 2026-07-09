# Shared witness driver, sourced by wasi/witness/run.sh and every
# wasi/vendor/*/run.sh. Runs one wasm command module through every available
# engine — node:wasi, real Chromium, and (when the python package is installed)
# wasmtime's Cranelift, a non-V8 cross-check — asserting each exits 0 and the
# browser/wasmtime legs print the pass sentinel.
#
#   source "<path>/legs.sh"
#   witness_legs <wasm> <sentinel> [check-eh]
#
# The 3rd argument, if non-empty, gates the standardized-encoding check
# (check-eh-encoding.sh): pass it for modules built with wasm-EH, omit it for
# the pure-C witnesses (libogg/libvorbis) that carry no EH to check.
#
# Usage note: run-node.mjs checks the exit code only; run-browser.mjs (argv[3])
# and run-wasmtime.py (argv[2]) also require the sentinel on stdout.

# Directory of this file. The runners live beside it; check-eh-encoding.sh is
# one dir up under toolchain/. Resolved from BASH_SOURCE so it is correct no
# matter which run.sh sources this from which cwd.
_LEGS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# True when the optional wasmtime python package is importable.
witness_have_wasmtime() { python3 -c 'import wasmtime' 2>/dev/null; }

# " + wasmtime" when the wasmtime leg ran, empty otherwise — for summary lines.
witness_wasmtime_suffix() { witness_have_wasmtime && printf ' + wasmtime'; }

witness_legs() {
  local wasm=$1 sentinel=$2 check=${3:-}
  [ -n "$check" ] && "$_LEGS_DIR/../toolchain/check-eh-encoding.sh" "$wasm"
  echo "== node:wasi =="
  node --no-warnings "$_LEGS_DIR/run-node.mjs" "$wasm"
  echo "== chromium =="
  node "$_LEGS_DIR/run-browser.mjs" "$wasm" "$sentinel"
  if witness_have_wasmtime; then
    echo "== wasmtime (Cranelift, non-V8) =="
    python3 "$_LEGS_DIR/run-wasmtime.py" "$wasm" "$sentinel"
  else
    echo "== wasmtime: skipped (wasmtime python package not installed) =="
  fi
}
