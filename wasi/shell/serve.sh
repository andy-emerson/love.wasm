#!/usr/bin/env bash
# Serve the interactive shell (Beta step 1) over HTTP, and optionally a game.
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
#   wasi/shell/serve.sh [port] [project-dir]
#
# Given a project directory it is mounted at /__project/, and the shell loads it
# with ?project=/__project/. The directory does NOT have to live in this
# repository — Beta step 2 keeps a local folder of small free LÖVE games, and
# pointing this at one is how they get run:
#
#   wasi/shell/serve.sh 8080 ~/love-games/mygame
#   # then open http://localhost:8080/wasi/shell/?project=/__project/
#
# Build the artifact the page loads first (heavy, ~6 min, and worth keeping
# around rather than rebuilding per iteration):
#
#   PREFIX=/path/to/wasi-eh OUT=wasi/shell/love-game.wasm wasi/platform/build-game.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
PORT=${1:-${PORT:-8080}}
PROJECT=${2:-${PROJECT:-}}

if [ ! -f "$HERE/love-game.wasm" ]; then
  echo "note: $HERE/love-game.wasm is missing — the page will report it." >&2
  echo "      build it with:" >&2
  echo "      PREFIX=\$PREFIX OUT=wasi/shell/love-game.wasm wasi/platform/build-game.sh" >&2
fi

if [ -n "$PROJECT" ]; then
  PROJECT=$(cd "$PROJECT" && pwd)   # fail loudly now if it is not a directory
  [ -f "$PROJECT/main.lua" ] || echo "note: $PROJECT has no main.lua — LÖVE will have nothing to run." >&2
  echo "love.wasm shell: http://localhost:$PORT/wasi/shell/?project=/__project/"
  echo "project:         $PROJECT"
else
  echo "love.wasm shell: http://localhost:$PORT/wasi/shell/"
  echo "project:         (none given — the canned project in fs-host.mjs will run)"
fi
echo "document root:   $ROOT"
echo "(ctrl-c to stop)"

ROOT="$ROOT" PORT="$PORT" PROJECT="$PROJECT" exec node -e '
const http = require("http"), fs = require("fs"), path = require("path");
const root = process.env.ROOT, port = Number(process.env.PORT);
const project = process.env.PROJECT || "";
// Only the types this page actually asks for. compileStreaming rejects a wasm
// response served as anything but application/wasm, which is a failure worth
// getting right rather than working around with an ArrayBuffer fallback.
const types = {
  ".html": "text/html; charset=utf-8",
  ".mjs":  "text/javascript; charset=utf-8",
  ".js":   "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".lua":  "text/plain; charset=utf-8",
  ".txt":  "text/plain; charset=utf-8",
  ".wasm": "application/wasm",
  ".ogg":  "audio/ogg", ".wav": "audio/wav", ".mp3": "audio/mpeg",
  ".png":  "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
  ".ttf":  "font/ttf",  ".otf": "font/otf",
};
const ctype = (f) => types[path.extname(f).toLowerCase()] || "application/octet-stream";

// A resolved path must stay inside the directory it was resolved against. Both
// trees get the same guard: a served tree is a served tree.
const inside = (dir, file) => file === dir || file.startsWith(dir + path.sep);

// The project manifest: the list of files a LÖVE project consists of, relative to
// its base URL. A static host can simply contain a manifest.json; for a local
// folder this synthesizes one by walking it, so pointing the server at a game
// directory is all it takes. Directories LÖVE never reads are skipped, and so is
// anything a project should not be shipping to the engine.
const SKIP = new Set([".git", ".svn", "node_modules", ".DS_Store", ".love-wasm"]);
const walk = (dir, rel = "", out = []) => {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP.has(e.name)) continue;
    const r = rel ? rel + "/" + e.name : e.name;
    if (e.isDirectory()) walk(path.join(dir, e.name), r, out);
    else if (e.isFile()) out.push(r);
  }
  return out;
};

http.createServer((req, res) => {
  let p;
  try { p = decodeURIComponent(new URL(req.url, "http://x").pathname); }
  catch { res.writeHead(400).end("bad path"); return; }

  // The mounted project, served from wherever it lives on disk.
  if (project && p.startsWith("/__project/")) {
    const relRaw = p.slice("/__project/".length);
    if (relRaw === "manifest.json" && !fs.existsSync(path.join(project, "manifest.json"))) {
      let files;
      try { files = walk(project); }
      catch (e) { res.writeHead(500, { "content-type": "text/plain" }).end("cannot read the project: " + e.message); return; }
      const body = JSON.stringify({ files }, null, 1);
      res.writeHead(200, { "content-type": types[".json"], "cache-control": "no-store" });
      res.end(body);
      return;
    }
    const file = path.resolve(project, "." + "/" + relRaw);
    if (!inside(project, file)) { res.writeHead(403).end("outside the project"); return; }
    fs.readFile(file, (err, buf) => {
      if (err) { res.writeHead(404, { "content-type": "text/plain" }).end("not in the project: " + relRaw); return; }
      res.writeHead(200, { "content-type": ctype(file), "cache-control": "no-store" });
      res.end(buf);
    });
    return;
  }

  if (p.endsWith("/")) p += "index.html";
  const file = path.resolve(root, "." + p);
  if (!inside(root, file)) { res.writeHead(403).end("outside the document root"); return; }
  fs.readFile(file, (err, buf) => {
    if (err) { res.writeHead(404, { "content-type": "text/plain" }).end("not found: " + p); return; }
    res.writeHead(200, {
      "content-type": ctype(file),
      "cache-control": "no-store",   // the artifact is rebuilt under you constantly
    });
    res.end(buf);
  });
}).listen(port, () => {});
'
