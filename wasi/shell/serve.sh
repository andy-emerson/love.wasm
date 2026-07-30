#!/usr/bin/env bash
# Serve the interactive shell (Beta step 1) over HTTP.
#
# A server is not a convenience here: ES module imports and fetch() both refuse
# to run from file://, and WebAssembly.compileStreaming needs a real
# application/wasm content type. The document root is the REPOSITORY root, not
# wasi/shell, because the page imports the host modules from ../host/ and LÖVE's
# boot wrapper from ../platform/ — one copy of each, shared with the witnesses.
#
# Static files only, no COOP/COEP headers. That is the point: love.wasm is built
# so a browser needs no cross-origin isolation to run a LÖVE game, and if this
# shell needed those headers the pillar would be broken.
#
#   wasi/shell/serve.sh [port]
#
# Build the artifact it loads first (heavy, ~6 min, and worth keeping around
# rather than rebuilding per iteration):
#
#   PREFIX=/path/to/wasi-eh OUT=wasi/shell/love-game.wasm wasi/platform/build-game.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
PORT=${1:-${PORT:-8080}}

if [ ! -f "$HERE/love-game.wasm" ]; then
  echo "note: $HERE/love-game.wasm is missing — the page will report it." >&2
  echo "      build it with:" >&2
  echo "      PREFIX=\$PREFIX OUT=wasi/shell/love-game.wasm wasi/platform/build-game.sh" >&2
fi

echo "love.wasm shell: http://localhost:$PORT/wasi/shell/"
echo "document root:   $ROOT"
echo "(ctrl-c to stop)"

ROOT="$ROOT" PORT="$PORT" exec node -e '
const http = require("http"), fs = require("fs"), path = require("path");
const root = process.env.ROOT, port = Number(process.env.PORT);
// Only the types this page actually asks for. compileStreaming rejects a wasm
// response served as anything but application/wasm, which is a failure worth
// getting right rather than working around with an ArrayBuffer fallback.
const types = {
  ".html": "text/html; charset=utf-8",
  ".mjs":  "text/javascript; charset=utf-8",
  ".js":   "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".lua":  "text/plain; charset=utf-8",
  ".wasm": "application/wasm",
  ".ogg":  "audio/ogg",
  ".png":  "image/png",
};
http.createServer((req, res) => {
  let p;
  try { p = decodeURIComponent(new URL(req.url, "http://x").pathname); }
  catch { res.writeHead(400).end("bad path"); return; }
  if (p.endsWith("/")) p += "index.html";
  // Resolve, then confirm the result is still inside the root: a served tree is
  // a served tree, and path traversal out of it is not this script to allow.
  const file = path.resolve(root, "." + p);
  if (file !== root && !file.startsWith(root + path.sep)) {
    res.writeHead(403).end("outside the document root");
    return;
  }
  fs.readFile(file, (err, buf) => {
    if (err) { res.writeHead(404, { "content-type": "text/plain" }).end("not found: " + p); return; }
    res.writeHead(200, {
      "content-type": types[path.extname(file).toLowerCase()] || "application/octet-stream",
      "cache-control": "no-store",   // the artifact is rebuilt under you constantly
    });
    res.end(buf);
  });
}).listen(port, () => {});
'
