// love_fs host — the browser/node fulfiller for the step-6.1 filesystem seam.
// It stands in for the IDE's project storage: a small in-memory project whose
// files the wasm side reads back through the love_fs import surface. The real
// host (LoveIDE) will swap this canned store for its live project model; the
// import contract (fs_size / fs_read) stays the same.
//
// Self-contained BY CONTRACT, exactly like wasi-shim.mjs and the driver.mjs
// files: no imports, no outer-scope references, so makeFsHost.toString() can be
// stringified into a Playwright page and rebuilt with new Function(). It runs
// unchanged under node too (TextEncoder/TextDecoder/DataView are globals in
// both), so the node:wasi leg and the Chromium leg share ONE host — the file
// bytes they compare against are the same bytes.
//
//   const fs = makeFsHost();
//   ... instantiate with { love_fs: fs.imports } ...
//   fs.bind(instance.exports.memory);   // before any import fires
//
// The canned project deliberately includes a BINARY asset with embedded NUL and
// high bytes (bin.dat), so the witness can prove the seam is length-accurate and
// NUL-safe rather than a C-string round-trip that would truncate at the first
// zero byte.
export function makeFsHost() {
  let memory;
  const te = new TextEncoder(), td = new TextDecoder();

  // path -> Uint8Array. Text files are UTF-8; bin.dat is raw bytes.
  const files = {
    'main.lua': te.encode(
      'function love.load() end\n' +
      'function love.update(dt) end\n' +
      'function love.draw() love.graphics.print("hi", 10, 10) end\n'),
    'conf.lua': te.encode(
      'function love.conf(t)\n  t.window.title = "step 6.1"\n  t.window.width = 320\nend\n'),
    // 8 bytes, two embedded NULs (indices 0 and 4) and high bytes (0xFF, 0x80,
    // 0xAA): a C-string protocol would report length 0 and read nothing; a
    // length-accurate one recovers all 8 exactly.
    'bin.dat': new Uint8Array([0x00, 0x01, 0x02, 0xFF, 0x00, 0x80, 0x7F, 0xAA]),
  };

  const readPath = (ptr, len) =>
    td.decode(new Uint8Array(memory.buffer, ptr, len));

  const imports = {
    // fs_size(path, path_len) -> byte length, or -1 if the file is absent.
    fs_size(pathPtr, pathLen) {
      const f = files[readPath(pathPtr, pathLen)];
      return f ? f.length : -1;
    },
    // fs_read(path, path_len, buf, cap) -> bytes copied (<= cap), or -1 absent.
    fs_read(pathPtr, pathLen, bufPtr, cap) {
      const f = files[readPath(pathPtr, pathLen)];
      if (!f) return -1;
      const n = Math.min(cap, f.length);
      new Uint8Array(memory.buffer, bufPtr, n).set(f.subarray(0, n));
      return n;
    },
  };

  return {
    imports,
    bind(m) { memory = m; },
    // Exposed so a node leg can assert against the exact source bytes.
    files,
  };
}
