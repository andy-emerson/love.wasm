# Single source of the standardized wasm-EH contract flags. Sourced by every
# compile site under wasi/ — the sysroot build, the pump/boot builds, the
# witnesses, the vendor builds (wasi/vendor/*), and the compile sweep (run
# `grep -rl eh-flags.sh wasi` for the current set) — so the load-bearing flag
# can't drift between them. Do NOT inline these anywhere else.
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

# wasm setjmp/longjmp support. It is implemented ON TOP OF wasm exception
# handling (wasi-libc's rt.c throws a __c_longjmp tag), so it must be combined
# with $EH_FLAGS — never used alone — and it emits the SAME standardized
# encoding, so check-eh-encoding.sh still passes. Append $SJLJ_FLAGS to
# $EH_FLAGS ONLY on translation units that actually call setjmp/longjmp (e.g.
# vendored FreeType); the runtime lives at $PREFIX/lib/wasi-setjmp.o and the
# header at $PREFIX/include/setjmp.h (installed by build-libcxx-eh.sh from the
# vendored wasi/toolchain/setjmp/ drop). This file is in the sysroot cache key.
# shellcheck disable=SC2034  # SJLJ_FLAGS is consumed by the sourcing script.
SJLJ_FLAGS="-mllvm -wasm-enable-sjlj"
