#!/usr/bin/env bash
# One-command step-0 witness. Two artifacts, each required to pass under every
# available engine (node:wasi, real Chromium, and — when installed — Firefox):
#
#   1. EH witness      — eh-typed-catch.cpp: the standardized wasm-EH claim
#                        (typed catch, carried payload, destructors on unwind).
#   2. SjLj+EH witness — sjlj-eh.cpp + sjlj-part.c: setjmp/longjmp (which
#                        wasi-libc omits, but FreeType needs) working alongside
#                        wasm-EH in one module, on the sysroot's wasi-setjmp
#                        runtime. Same standardized encoding as everything else.
#
#   PREFIX=/path/to/wasi-eh wasi/witness/run.sh
#
# PREFIX is the install prefix produced by wasi/toolchain/build-libcxx-eh.sh
# (default ./wasi-eh). Browser legs need playwright-core resolvable from the
# invoking cwd and either an installed playwright chromium or CHROMIUM set to a
# chromium executable; the Firefox (SpiderMonkey) non-V8 cross-check leg
# additionally needs playwright's firefox installed.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PREFIX=${PREFIX:-$PWD/wasi-eh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

source "$HERE/../toolchain/eh-flags.sh"
source "$HERE/legs.sh"

# ── EH witness ────────────────────────────────────────────────────────────────
# Standardized exnref encoding, matching the sysroot build (one artifact, one
# encoding — clang-20's bare -fwasm-exceptions default is legacy).
# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi $EH_FLAGS -O2 \
  -nostdinc++ -I"$PREFIX/include/c++/v1" \
  "$HERE/eh-typed-catch.cpp" "$PREFIX/lib/unwind-wasm.o" \
  -L"$PREFIX/lib" -lc++ -lc++abi \
  -o "$TMP/eh-witness.wasm"
echo "### EH witness ###"
witness_legs "$TMP/eh-witness.wasm" "EH-WITNESS: PASS" check-eh

# ── SjLj+EH witness ───────────────────────────────────────────────────────────
# sjlj-part.c is the FreeType-shaped C TU (calls setjmp/longjmp, compiled with
# $SJLJ_FLAGS and the sysroot's setjmp.h); sjlj-eh.cpp is the engine-shaped C++
# wasm-EH TU (no SjLj flag). They link with the sysroot's wasi-setjmp runtime.
# shellcheck disable=SC2086
clang-20 --target=wasm32-wasi $EH_FLAGS $SJLJ_FLAGS -O2 \
  -I"$PREFIX/include" -c "$HERE/sjlj-part.c" -o "$TMP/sjlj-part.o"
# shellcheck disable=SC2086
clang++-20 --target=wasm32-wasi $EH_FLAGS -O2 \
  -nostdinc++ -I"$PREFIX/include/c++/v1" -c "$HERE/sjlj-eh.cpp" -o "$TMP/sjlj-eh.o"
# shellcheck disable=SC2086
# Link-only: -Wno-unused-command-line-argument silences the codegen-only -mllvm
# encoding flag carried in $EH_FLAGS (harmless, nothing to compile here).
clang++-20 --target=wasm32-wasi $EH_FLAGS -Wno-unused-command-line-argument \
  "$TMP/sjlj-eh.o" "$TMP/sjlj-part.o" \
  "$PREFIX/lib/wasi-setjmp.o" "$PREFIX/lib/unwind-wasm.o" \
  -L"$PREFIX/lib" -lc++ -lc++abi \
  -o "$TMP/sjlj-eh.wasm"
echo "### SjLj+EH witness ###"
witness_legs "$TMP/sjlj-eh.wasm" "SJLJ-EH-WITNESS: PASS" check-eh

echo "witness: EH + SjLj PASS on node + browser$(witness_firefox_suffix)"
