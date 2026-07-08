# Single source of the standardized wasm-EH contract flags. Sourced by every
# compile site in this repo — wasi/toolchain/build-libcxx-eh.sh, wasi/pump/build.sh,
# wasi/boot/build.sh, wasi/witness/run.sh — so the load-bearing flag can't drift
# between them. Do NOT inline these anywhere else.
#
# clang-20's bare -fwasm-exceptions defaults to the LEGACY encoding (try/catch);
# the standardized exnref encoding (try_table/throw_ref) that lua-wasi's flag
# contract requires needs the explicit -mllvm flag. One artifact, one encoding —
# wasi/toolchain/check-eh-encoding.sh gates every output. This file is in the
# witness workflow's sysroot cache key, so changing the flags rebuilds libc++.
#
# Usage: source "<dir>/eh-flags.sh", then use $EH_FLAGS (unquoted) in the clang
# invocation.
# shellcheck disable=SC2034  # EH_FLAGS is consumed by the sourcing script.
EH_FLAGS="-fwasm-exceptions -mllvm -wasm-use-legacy-eh=false"
