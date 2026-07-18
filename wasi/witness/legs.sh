# Shared witness driver, sourced by wasi/witness/run.sh and every
# wasi/vendor/*/run.sh. Runs one wasm command module through every available
# engine — node:wasi, real Chromium, wasmtime's Cranelift (when the python
# package is installed), and real Firefox/SpiderMonkey (when Playwright's firefox
# is installed) — asserting each exits 0 and the browser/wasmtime legs print the
# pass sentinel. wasmtime and Firefox are both non-V8 cross-checks of the wasm
# encoding; Firefox needs no runtime beyond Playwright, which is already the
# browser host.
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

# True when Playwright can resolve an installed browser ENGINE ($1: chromium |
# firefox | webkit). Reuses resolvePlaywright() so detection matches exactly what
# run-browser.mjs will launch — no separate path guessing.
witness_have_browser() {
  node --input-type=module -e "
    import { resolvePlaywright } from '$_LEGS_DIR/../host/witness-harness.mjs';
    import { existsSync } from 'node:fs';
    try { process.exit(existsSync(resolvePlaywright()['$1'].executablePath()) ? 0 : 1); }
    catch { process.exit(1); }
  " 2>/dev/null
}

# " + firefox" when the Firefox leg ran, empty otherwise — for summary lines.
witness_firefox_suffix() { witness_have_browser firefox && printf ' + firefox'; }

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
  if witness_have_browser firefox; then
    echo "== firefox (SpiderMonkey, non-V8) =="
    WITNESS_BROWSER=firefox node "$_LEGS_DIR/run-browser.mjs" "$wasm" "$sentinel"
  else
    echo "== firefox: skipped (playwright firefox not installed) =="
  fi
}
