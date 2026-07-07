#!/usr/bin/env bash
# Encoding gate for the wasm-EH contract with lua-wasi (issue #3): the
# artifact must use ONLY the standardized exnref encoding
# (try_table/throw_ref), never the legacy one (try/end_try/rethrow/
# delegate). clang-20's bare -fwasm-exceptions default is LEGACY, so a
# build script that loses the -mllvm -wasm-use-legacy-eh=false flag would
# otherwise regress silently — engines currently accept both encodings,
# so no witness would catch it at run time.
#
#   wasi/toolchain/check-eh-encoding.sh <module.wasm>
#
# Legacy `catch` is deliberately not in the discriminator set: try_table
# clauses may spell plain `catch`, and legacy-EH code always carries
# try/end_try anyway.
set -euo pipefail

OBJDUMP=${OBJDUMP:-llvm-objdump-20}
MODULE=$1

DIS=$("$OBJDUMP" -d "$MODULE")

std=$(grep -cE '(^|[[:space:]])try_table([[:space:]]|$)' <<<"$DIS" || true)
legacy=$(grep -cE '(^|[[:space:]])(try|end_try|rethrow|delegate)([[:space:]]|$)' <<<"$DIS" || true)

if [ "$std" -lt 1 ] || [ "$legacy" -gt 0 ]; then
  echo "FAIL: $MODULE wasm-EH encoding check: try_table=$std legacy=$legacy" >&2
  echo "      (want: try_table >= 1, legacy = 0 — the standardized encoding only)" >&2
  exit 1
fi
echo "$MODULE: standardized wasm-EH encoding confirmed (try_table=$std, legacy=0)"
