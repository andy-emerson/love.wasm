#!/usr/bin/env bash
# Step-0 toolchain bring-up: build LLVM libc++ + libc++abi for wasm32-wasi
# with wasm exception handling, plus the libunwind wasm personality shim.
#
# Why this exists: LOVE's error path needs full C++ EH (typed catches,
# exception-object destructors — see readme.md), and no packaged wasm32
# libc++abi ships the EH runtime (Ubuntu's stock wasm32 libs leave
# __cxa_throw / _Unwind_CallPersonality / __wasm_lpad_context undefined).
#
# Prerequisites (Ubuntu 24.04):
#   apt-get install clang-20 lld-20 libclang-rt-20-dev-wasm32 wasi-libc \
#                   cmake ninja-build
#   (deb-src enabled for the llvm-toolchain-20 source download)
#
# Witnessed 2026-07-06, CI-enforced since: wasi/witness/eh-typed-catch.cpp
# PASSes (typed catch, what() intact, carried payload intact, non-matching
# catch skipped, destructor ran) under node:wasi (Node >= 24.15) and in real
# Chromium 141 via wasi/witness/run-browser.mjs.
#
# Gotchas this script encodes, discovered the hard way:
#  - LLVM 20's libcxxabi/libcxx create their *_shared targets unconditionally;
#    under CMAKE_SYSTEM_NAME=Generic CMake degrades SHARED to STATIC and two
#    rules collide on lib/libc++abi.a. Fix: Platform/WASI.cmake (beside this
#    script) declares the platform unix-like with shared-library support, so
#    the never-built shared targets keep a .so identity.
#  - HandleLLVMOptions.cmake rejects unknown CMAKE_SYSTEM_NAMEs; the platform
#    module's `set(UNIX 1)` is what admits WASI (same trick wasi-sdk uses).
#  - libc++ 20 borrows llvm-libc's shared headers (shared/fp_bits.h): the
#    llvm-project `libc/` directory must be present in the source tree.
#  - wasi-libc has no sys/statvfs.h: -DLIBCXX_ENABLE_FILESYSTEM=OFF (LOVE
#    does not use std::filesystem; love.filesystem is a host-import VFS).
#  - Unwind-wasm.c needs -DNDEBUG (else it calls the debug-trace hooks) and
#    -D_LIBUNWIND_HIDE_SYMBOLS (else it wants __declspec/-fdeclspec). It is
#    compiled standalone: the full libunwind runtime build has the same
#    duplicate-output problem and none of it is needed for wasm EH.
#  - clang-20's -fwasm-exceptions default is the LEGACY encoding
#    (try/catch); the standardized exnref encoding (try_table/throw_ref)
#    that the lua.wasm flag contract requires needs an explicit
#    `-mllvm -wasm-use-legacy-eh=false` (probed 2026-07-07: default emits
#    `try`/`rethrow`, flag emits `try_table`/`throw_ref`). One artifact
#    must not mix encodings, so the flag is baked in here.
set -euo pipefail

WORK=${WORK:-$PWD/build-libcxx-eh}
PREFIX=${PREFIX:-$PWD/wasi-eh}
HERE=$(cd "$(dirname "$0")" && pwd)
JOBS=${JOBS:-$(nproc)}

# The one EH configuration this whole repo links under: wasm-EH with the
# standardized exnref encoding, matching lua.wasm's WASM_EH_ENCODING=standard.
# Single-sourced so the compile sites can't drift (see eh-flags.sh).
source "$HERE/eh-flags.sh"

mkdir -p "$WORK" && cd "$WORK"

# ── source: the exact LLVM release Ubuntu's clang-20 packages are built from ──
# Acquisition order: existing tarball → GitHub release (plain CI networks) →
# apt-get source (mirrors-only networks; needs deb-src enabled).
LLVM_VER=${LLVM_VER:-20.1.2}
if [ ! -d llvm-src/runtimes ]; then
  if ls llvm-*"$LLVM_VER"*.tar.* >/dev/null 2>&1; then
    echo "source: using existing tarball"
  else
    echo "source: fetching llvm-project-$LLVM_VER.src.tar.xz from GitHub releases"
    # -f: fail on HTTP errors; no -s so failures are visible in CI logs.
    # Note --retry does NOT retry 403s (the anonymous rate-limit answer).
    if curl -fL --retry 3 --retry-delay 5 -o "llvm-project-$LLVM_VER.src.tar.xz" \
        "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VER/llvm-project-$LLVM_VER.src.tar.xz"; then
      echo "source: GitHub download ok"
    else
      rc=$?
      echo "source: curl failed (rc=$rc); falling back to apt-get source (needs deb-src)" >&2
      rm -f "llvm-project-$LLVM_VER.src.tar.xz"   # drop curl's partial/empty file
      apt-get source --download-only libc++-20-dev-wasm32
    fi
  fi
  # apt-get source drops several component tarballs — pick the main one only
  # (a multi-file glob would make tar read the 2nd file as a member name).
  # `|| true`: under set -euo pipefail a no-match ls would otherwise kill the
  # script silently with exit 2 at this assignment (witnessed in CI run 3).
  TARBALL=$(ls "llvm-project-$LLVM_VER.src.tar.xz" llvm-*"$LLVM_VER"*.orig.tar.* 2>/dev/null | head -1 || true)
  [ -n "$TARBALL" ] && [ -s "$TARBALL" ] || { echo "error: no LLVM source tarball acquired" >&2; exit 1; }
  echo "source: extracting $TARBALL"
  mkdir -p llvm-src
  tar xf "$TARBALL" -C llvm-src --strip-components=1 --wildcards \
    '*/libcxx/*' '*/libcxxabi/*' '*/libunwind/*' '*/runtimes/*' '*/cmake/*' \
    '*/llvm/utils/llvm-lit/*' '*/libc/*'
fi

# ── configure + build libc++abi / libc++ with wasm-EH ─────────────────────────
cmake -G Ninja -S llvm-src/runtimes -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang-20 -DCMAKE_CXX_COMPILER=clang++-20 \
  -DCMAKE_C_COMPILER_TARGET=wasm32-wasi -DCMAKE_CXX_COMPILER_TARGET=wasm32-wasi \
  -DCMAKE_SYSTEM_NAME=WASI -DCMAKE_SYSTEM_PROCESSOR=wasm32 \
  -DCMAKE_MODULE_PATH="$HERE" \
  -DUNIX=1 \
  -DCMAKE_C_FLAGS="$EH_FLAGS" -DCMAKE_CXX_FLAGS="$EH_FLAGS" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DLLVM_ENABLE_RUNTIMES="libcxxabi;libcxx" \
  -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_THREADS=OFF \
  -DLIBCXXABI_USE_LLVM_UNWINDER=OFF -DLIBCXXABI_SILENT_TERMINATE=ON \
  -DLIBCXXABI_INCLUDE_TESTS=OFF \
  -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_THREADS=OFF \
  -DLIBCXX_ENABLE_FILESYSTEM=OFF \
  -DLIBCXX_HAS_MUSL_LIBC=ON -DLIBCXX_CXX_ABI=libcxxabi \
  -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INCLUDE_TESTS=OFF \
  -DCMAKE_INSTALL_PREFIX="$PREFIX"
ninja -C build -j"$JOBS" install

# ── the wasm-EH personality shim (provides _Unwind_CallPersonality etc.) ─────
clang-20 --target=wasm32-wasi $EH_FLAGS -O2 -DNDEBUG \
  -D_LIBUNWIND_HIDE_SYMBOLS \
  -Illvm-src/libunwind/include -Illvm-src/libunwind/src \
  -c llvm-src/libunwind/src/Unwind-wasm.c -o "$PREFIX/lib/unwind-wasm.o"

# ── wasm setjmp/longjmp support (wasi-libc omits it; FreeType needs it) ───────
# setjmp on wasm is implemented on top of wasm-EH (rt.c throws a __c_longjmp
# tag), so it uses the SAME standardized encoding this sysroot is built for.
# Install the vendored wasi-libc headers and build its runtime; a TU that calls
# setjmp/longjmp compiles with $EH_FLAGS $SJLJ_FLAGS and links wasi-setjmp.o.
# See wasi/toolchain/setjmp/PIN.
mkdir -p "$PREFIX/include/bits"
cp "$HERE/setjmp/setjmp.h"      "$PREFIX/include/setjmp.h"
cp "$HERE/setjmp/bits/setjmp.h" "$PREFIX/include/bits/setjmp.h"
clang-20 --target=wasm32-wasi $EH_FLAGS -O2 \
  -c "$HERE/setjmp/rt.c" -o "$PREFIX/lib/wasi-setjmp.o"

echo "installed to $PREFIX"
echo "link C++-with-EH wasm like:"
echo "  clang++-20 --target=wasm32-wasi -fwasm-exceptions -nostdinc++ \\"
echo "    -I$PREFIX/include/c++/v1 x.cpp $PREFIX/lib/unwind-wasm.o \\"
echo "    -L$PREFIX/lib -lc++ -lc++abi -o x.wasm"
echo "setjmp/longjmp: add \$SJLJ_FLAGS and -I$PREFIX/include, link $PREFIX/lib/wasi-setjmp.o"
