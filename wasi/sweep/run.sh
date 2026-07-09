#!/usr/bin/env bash
# Compile sweep (issue #9): the dependency-disposition map, witnessed.
#
# For every LÖVE engine-module translation unit and the in-tree libraries the
# map names, try -fsyntax-only under this build's exact contract flags (the
# same clang-20 / wasm-EH / include set wasi/boot/build.sh links). Each file is
# then either OK (compiles under the contract) or FAIL (blocker recorded with
# its first error line) — so no module's status is left unknown. This is a
# HEADER/SYNTASX reachability probe, not a link: it answers "does the C++ even
# parse and resolve its includes for wasm32-wasi", which is where the seam and
# vendoring decisions (steps 4-8) are cheap to discover.
#
#   PREFIX=/path/to/wasi-eh wasi/sweep/run.sh [report.md]
#
# PREFIX is the step-0 sysroot (wasi/toolchain/build-libcxx-eh.sh). Writes a
# grouped summary to stdout and, if a path is given, a Markdown report there.
set -uo pipefail   # NOT -e: individual compile failures are the data, not fatal

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SRC="$ROOT/src"
LUA="$ROOT/wasi/lua/upstream/src"
ZLIB="$ROOT/wasi/vendor/zlib"
CONFIG="$ROOT/wasi/boot/config"
PREFIX=${PREFIX:-$PWD/wasi-eh}
REPORT=${1:-}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

source "$ROOT/wasi/toolchain/eh-flags.sh"

# The parse-affecting subset of wasi/boot/build.sh's flags (drop -O2 and the
# linker/exec-model flags: -fsyntax-only never reaches codegen or link).
CXXFLAGS=(--target=wasm32-wasi $EH_FLAGS -fno-strict-aliasing
  -nostdinc++ -I"$PREFIX/include/c++/v1"
  -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS
  -DLUA_USE_JUMPTABLE=0 -DMAKE_LIB -DLUAW_EXTERNAL_EH
  -DHAVE_CONFIG_H -I"$CONFIG/include"
  -I"$LUA/wasi" -I"$LUA"
  -I"$SRC" -I"$SRC/modules" -I"$SRC/libraries" -I"$ZLIB")
CFLAGS=(--target=wasm32-wasi -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS
  -I"$SRC" -I"$SRC/libraries" -I"$ZLIB")

RESULTS="$TMP/results.tsv"   # group \t file \t status \t firsterror
: > "$RESULTS"

probe() {  # $1 group  $2 file  $3 lang(cxx|c)
  local group=$1 file=$2 lang=$3 rel err rc
  rel=${file#"$ROOT"/}
  # Branch on the EXIT CODE, not on stderr: clang writes warnings to stderr on
  # a successful (rc=0) compile, so "stderr non-empty" is not "failed".
  if [ "$lang" = c ]; then
    err=$(clang-20 "${CFLAGS[@]}" -fsyntax-only "$file" 2>&1); rc=$?
  else
    err=$(clang++-20 "${CXXFLAGS[@]}" -fsyntax-only "$file" 2>&1); rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    printf '%s\t%s\tOK\t\n' "$group" "$rel" >> "$RESULTS"
  else
    local first
    first=$(printf '%s\n' "$err" | grep -m1 -E 'error:|fatal error:' | sed 's/^[^ ]*: //' | cut -c1-140)
    printf '%s\t%s\tFAIL\t%s\n' "$group" "$rel" "${first:-unknown error}" >> "$RESULTS"
  fi
}

# ── engine modules: every .cpp under each module dir (skip Apple .mm/.m) ──────
for moddir in "$SRC"/modules/*/; do
  mod=$(basename "$moddir")
  while IFS= read -r f; do probe "module/$mod" "$f" cxx; done \
    < <(find "$moddir" -name '*.cpp' | sort)
done

# ── in-tree libraries named in the #9 map ────────────────────────────────────
lib_cxx() { while IFS= read -r f; do probe "lib/$1" "$f" cxx; done < <(find "$SRC/libraries/$1" -name '*.cpp' 2>/dev/null | sort); }
lib_c()   { while IFS= read -r f; do probe "lib/$1" "$f" c;   done < <(find "$SRC/libraries/$1" -name '*.c'   2>/dev/null | sort); }

lib_cxx box2d
lib_c   lz4
lib_c   xxHash
lib_cxx noise1234
lib_cxx utf8
lib_c   Wuff
lib_c   dr
lib_cxx ddsparse
lib_cxx lodepng
lib_cxx tinyexr

# stb / dr are header-only; probe via a one-line TU that instantiates them the
# way the image/sound modules do, so the map has a real answer for them.
printf '#define STB_IMAGE_IMPLEMENTATION\n#include "stb_image.h"\n' > "$TMP/stb_probe.c"
clang-20 "${CFLAGS[@]}" -I"$SRC/libraries/stb" -fsyntax-only "$TMP/stb_probe.c" 2>"$TMP/stb.err" \
  && printf 'lib/stb\tstb_image.h (impl TU)\tOK\t\n' >> "$RESULTS" \
  || printf 'lib/stb\tstb_image.h (impl TU)\tFAIL\t%s\n' "$(grep -m1 -E 'error:|fatal error:' "$TMP/stb.err" | sed 's/^[^ ]*: //' | cut -c1-140)" >> "$RESULTS"

# ── report ───────────────────────────────────────────────────────────────────
emit() {
  local total ok fail
  total=$(wc -l < "$RESULTS"); ok=$(grep -cP '\tOK\t' "$RESULTS"); fail=$(grep -cP '\tFAIL\t' "$RESULTS")
  echo "# love-wasi compile sweep (#9)"
  echo
  echo "$ok/$total translation units compile under the contract flags; $fail blocked."
  echo
  echo "| group | ok/total | blockers (first error) |"
  echo "|---|---|---|"
  cut -f1 "$RESULTS" | sort -u | while read -r g; do
    local gt gok
    gt=$(awk -F'\t' -v g="$g" '$1==g' "$RESULTS" | wc -l)
    gok=$(awk -F'\t' -v g="$g" '$1==g && $3=="OK"' "$RESULTS" | wc -l)
    local blurb
    blurb=$(awk -F'\t' -v g="$g" '$1==g && $3=="FAIL"{print $4}' "$RESULTS" | sort | uniq -c | sort -rn \
            | head -3 | sed 's/^ *//' | paste -sd'; ' -)
    [ "$gok" = "$gt" ] && blurb="✅ all compile"
    printf '| %s | %s/%s | %s |\n' "$g" "$gok" "$gt" "${blurb:-—}"
  done
  echo
  echo "<details><summary>Per-file blockers</summary>"
  echo
  echo '```'
  awk -F'\t' '$3=="FAIL"{printf "%-40s %s\n  %s\n", $1, $2, $4}' "$RESULTS"
  echo '```'
  echo "</details>"
}

emit > "$TMP/report.md"
cat "$TMP/report.md"
[ -n "$REPORT" ] && cp "$TMP/report.md" "$REPORT" && echo "(report written to $REPORT)"
