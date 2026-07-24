#!/usr/bin/env bash
# SessionStart hook — issue #20: bring up the wasm-EH build+witness toolchain in
# an interactive Claude Code (web) session, so wasi/{witness,pump,boot}/run.sh
# work in-session (not just in CI). The recipe mirrors, step for step,
# .github/workflows/witness.yml — with two host substitutions the web network
# policy forces (both are reachable on CI runners but blocked by the web
# session's proxy):
#
#   - clang-20 from Ubuntu 24.04's OWN repos (candidate 1:20.1.2-0ubuntu1,
#     the exact LLVM the sysroot is built against) — not apt.llvm.org.
#   - Node >= 24.15 from the nodejs.org release tarball — not deb.nodesource.com.
#     24.15 is the first 24.x to take the standardized exnref encoding by
#     default, which the witnesses require (lua.wasm #27).
#
# The minutes-long libc++/libc++abi sysroot build is NOT redone per session:
# the container is ephemeral, so a from-source rebuild every start would be
# wasteful. Instead the prebuilt tarball published by
# .github/workflows/publish-sysroot.yml is fetched and extracted. (Chromium is
# already provisioned by the platform at $PLAYWRIGHT_BROWSERS_PATH.)
#
# Everything installs under $HOME/.love-wasi (out of the repo tree, so the
# working copy stays pristine), and the session env is persisted via
# $CLAUDE_ENV_FILE. Idempotent: safe to re-run on resume/clear/compact.
set -euo pipefail

# Only the remote (web) environment needs this; a local checkout already has
# whatever toolchain the developer set up.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

DEPS="$HOME/.love-wasi"
PREFIX="$DEPS/wasi-eh"
NODE_DIR="$DEPS/node"
NPM_DIR="$DEPS/npm"
PW_BROWSERS="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}"

# Overridable knobs (env wins), so a session can pin different versions.
SYSROOT_TAG="${LOVE_WASI_SYSROOT_TAG:-sysroot}"
# The sysroot is published by THIS repo's publish-sysroot.yml as a release asset,
# so fetch it from the same repo the working copy came from — derived from the
# origin remote, so the fork it's developed on (wasiware/love-wasi today) and its
# eventual canonical home both resolve without editing this line. A hardcoded org
# here is the classic skew bug: the workflow publishes to $GITHUB_REPOSITORY, and
# if the hook names a different repo the fetch 404s even though the asset exists.
# Override with LOVE_WASI_SYSROOT_REPO=owner/repo.
sysroot_repo() {
  local url
  url=$(git -C "$(dirname "${BASH_SOURCE[0]}")" remote get-url origin 2>/dev/null) || return 1
  url=${url%.git}                       # drop a trailing .git
  case "$url" in
    *github.com[:/]*) printf '%s\n' "${url#*github.com}" | sed 's#^[:/]##' ;;  # -> owner/repo (https or ssh)
    *) return 1 ;;
  esac
}
SYSROOT_REPO="${LOVE_WASI_SYSROOT_REPO:-$(sysroot_repo || echo wasiware/love-wasi)}"
SYSROOT_URL="https://github.com/$SYSROOT_REPO/releases/download/$SYSROOT_TAG/wasi-eh.tar.gz"
NODE_VER="${LOVE_WASI_NODE_VER:-v24.18.0}"
PLAYWRIGHT_VER="${LOVE_WASI_PLAYWRIGHT_VER:-1.61.1}"

SUDO=""; [ "$(id -u)" = 0 ] || SUDO="sudo"
mkdir -p "$DEPS"
log() { echo "[love-wasi hook] $*"; }

use_node_dir=0   # set when we install our own Node under $NODE_DIR

# 1. clang-20 wasm toolchain (skip if already present) ────────────────────────
if command -v clang-20 >/dev/null 2>&1; then
  log "clang-20 present, skipping apt"
else
  log "installing clang-20 wasm toolchain (apt, Ubuntu repos)"
  $SUDO apt-get update -qq || true
  $SUDO apt-get install -y -qq clang-20 lld-20 llvm-20 \
    libclang-rt-20-dev-wasm32 wasi-libc cmake ninja-build
fi

# 2. Node >= 24.15 from the nodejs.org tarball (skip if system node suffices) ──
node_ok() {
  command -v node >/dev/null 2>&1 && \
  node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>24||(a===24&&b>=15)?0:1)'
}
if node_ok; then
  log "node $(node --version) satisfies >=24.15, skipping"
else
  if [ ! -x "$NODE_DIR/bin/node" ]; then
    case "$(uname -m)" in
      x86_64) narch=x64 ;;
      aarch64|arm64) narch=arm64 ;;
      *) narch="$(uname -m)" ;;
    esac
    log "installing Node $NODE_VER (nodejs.org tarball, $narch)"
    tgz="$DEPS/node-$NODE_VER-linux-$narch.tar.xz"
    curl -fL --retry 3 --retry-delay 3 -o "$tgz" \
      "https://nodejs.org/dist/$NODE_VER/node-$NODE_VER-linux-$narch.tar.xz"
    rm -rf "$NODE_DIR"; mkdir -p "$NODE_DIR"
    tar xf "$tgz" -C "$NODE_DIR" --strip-components=1
    rm -f "$tgz"
  fi
  export PATH="$NODE_DIR/bin:$PATH"
  use_node_dir=1
  log "node now $(node --version)"
fi

# 3. playwright-core (the browser binary is already at $PW_BROWSERS) ───────────
export NODE_PATH="$NPM_DIR/node_modules${NODE_PATH:+:$NODE_PATH}"
if node -e "require.resolve('playwright-core')" >/dev/null 2>&1; then
  log "playwright-core resolvable, skipping npm"
else
  log "installing playwright-core@$PLAYWRIGHT_VER (npm)"
  mkdir -p "$NPM_DIR"
  ( cd "$NPM_DIR" && npm i --no-save --no-audit --no-fund "playwright-core@$PLAYWRIGHT_VER" )
fi

# 4. wasm-EH sysroot — fetch the prebuilt tarball; do NOT rebuild per session ──
if [ -f "$PREFIX/lib/libc++.a" ] && [ -f "$PREFIX/lib/unwind-wasm.o" ] && [ -f "$PREFIX/lib/wasi-setjmp.o" ]; then
  log "sysroot present at $PREFIX, skipping fetch"
else
  log "fetching prebuilt wasm-EH sysroot: $SYSROOT_URL"
  tgz="$DEPS/wasi-eh.tar.gz"
  if curl -fL --retry 3 --retry-delay 3 -o "$tgz" "$SYSROOT_URL"; then
    rm -rf "$PREFIX"; mkdir -p "$PREFIX"
    tar xzf "$tgz" -C "$PREFIX" --strip-components=1
    rm -f "$tgz"
    log "sysroot extracted to $PREFIX"
    [ -f "$PREFIX/PROVENANCE" ] && log "provenance: $(head -2 "$PREFIX/PROVENANCE" | tr '\n' ' ')"
  else
    log "WARNING: could not fetch the sysroot tarball from $SYSROOT_URL."
    log "  Expected a publish-sysroot.yml release asset on $SYSROOT_REPO (tag: $SYSROOT_TAG)."
    log "  If that repo has no such release yet, trigger the workflow (workflow_dispatch),"
    log "  or point at another repo's asset: LOVE_WASI_SYSROOT_REPO=owner/repo. Or build once:"
    log "    WORK=\$HOME/.love-wasi/llvm-eh PREFIX=$PREFIX wasi/toolchain/build-libcxx-eh.sh"
    log "  The witnesses need it; everything else is ready."
  fi
fi

# 5. Persist the session env (PATH, PREFIX, NODE_PATH, CHROMIUM) ───────────────
CHROMIUM=""
for c in "$PW_BROWSERS"/chromium-*/chrome-linux/chrome; do
  [ -x "$c" ] && CHROMIUM="$c" && break
done
ENV_OUT="${CLAUDE_ENV_FILE:-$DEPS/env.sh}"
# Idempotent: SessionStart also fires on resume/clear/compact within the same
# container, so guard on a marker to avoid appending duplicate exports.
MARK="# love-wasi hook env"
if ! grep -qF "$MARK" "$ENV_OUT" 2>/dev/null; then
  {
    echo "$MARK"
    [ "$use_node_dir" = 1 ] && echo "export PATH=\"$NODE_DIR/bin:\$PATH\""
    echo "export PREFIX=\"$PREFIX\""
    echo "export NODE_PATH=\"$NPM_DIR/node_modules\${NODE_PATH:+:\$NODE_PATH}\""
    [ -n "$CHROMIUM" ] && echo "export CHROMIUM=\"$CHROMIUM\""
  } >> "$ENV_OUT"
fi

log "ready — witnesses: wasi/witness/run.sh · wasi/pump/run.sh · wasi/boot/run.sh"
