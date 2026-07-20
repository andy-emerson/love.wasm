// love_fs host — the browser/node fulfiller for the step-6.1/6.2 filesystem
// seam. It stands in for the IDE's project storage: a small in-memory project
// whose files the wasm side reads back through the love_fs import surface. The
// real host (LoveIDE) will swap this canned store for its live project model;
// the import contract (fs_size / fs_read / fs_stat) stays the same.
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
  //
  // main.lua / conf.lua are a REAL, runnable LÖVE 12 game — the canned project
  // LÖVE's boot.lua reads and runs for the step-6.6b first-frame witness
  // (conf -> canvas -> load -> draw -> present). They are ALSO the fixtures the
  // 6.1/6.2 filesystem witnesses read back (which only require: main.lua is a
  // loadable chunk containing "love.draw", conf.lua contains "love.conf",
  // main.lua >= 8 bytes). love.load prints a UNIQUE MARKER (host tap / fd 1) so
  // the frame witness can prove love.load ran through the real boot; love.draw
  // clears BLACK then fills the whole canvas RED — a known, unambiguous colour the
  // frame witness reads back from the presented backbuffer.
  const files = {
    'main.lua': te.encode(
      'function love.load()\n' +
      '  print("STEP66B-LOVE-LOAD-MARKER-7F3A9C")\n' +
      '  io.write("STEP66B-IO-WRITE-MARKER\\n")\n' +
      'end\n' +
      'local frame = 0\n' +
      'function love.update(dt)\n' +
      '  frame = frame + 1\n' +
      '  if frame == 1 then print("STEP66B-FIRST-UPDATE dt=" .. tostring(dt)) end\n' +
      'end\n' +
      'function love.draw()\n' +
      '  love.graphics.clear(0, 0, 0, 1)\n' +
      '  love.graphics.setColor(1, 0, 0, 1)\n' +
      '  love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())\n' +
      'end\n'),
    'conf.lua': te.encode(
      'function love.conf(t)\n' +
      '  t.identity = "step66frame"\n' +
      '  t.window.width = 64\n' +
      '  t.window.height = 64\n' +
      '  t.window.title = "step 6.6b frame"\n' +
      '  -- Enable ONLY the modules the frame build links; boot.lua requires each\n' +
      '  -- enabled module, so anything not linked must be turned off here.\n' +
      '  t.modules.audio = false\n' +
      '  t.modules.video = false\n' +
      '  t.modules.sound = false\n' +
      '  t.modules.physics = false\n' +
      '  t.modules.joystick = false\n' +
      '  t.modules.touch = false\n' +
      '  t.modules.sensor = false\n' +
      '  t.modules.thread = false\n' +
      'end\n'),
    // 8 bytes, two embedded NULs (indices 0 and 4) and high bytes (0xFF, 0x80,
    // 0xAA): a C-string protocol would report length 0 and read nothing; a
    // length-accurate one recovers all 8 exactly.
    'bin.dat': new Uint8Array([0x00, 0x01, 0x02, 0xFF, 0x00, 0x80, 0x7F, 0xAA]),
    // A Lua module file, so the 6.2 witness can prove `require("lib")` resolves
    // through the real love.filesystem `loader` searcher (requirePath "?.lua")
    // to host-provided bytes and returns the module's table.
    'lib.lua': te.encode(
      'local lib = {}\n' +
      'function lib.greet() return "hello from lib" end\n' +
      'lib.answer = 42\n' +
      'return lib\n'),
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
    // fs_stat(path, path_len, outType, outSize, outMtime) -> 0 ok / -1 absent.
    // The out-params are written into wasm linear memory (little-endian, same
    // convention fs_read's buf uses). outType is the FileType enum order the
    // 6.2 backend maps from: 0=file 1=dir 2=symlink 3=other. The canned store
    // is all regular files, so type is always 0; mtime is a fixed stand-in
    // (the IDE host will report real project timestamps).
    fs_stat(pathPtr, pathLen, outType, outSize, outMtime) {
      const f = files[readPath(pathPtr, pathLen)];
      if (!f) return -1;
      const dv = new DataView(memory.buffer);
      dv.setInt32(outType, 0, true);              // FILETYPE_FILE
      dv.setBigInt64(outSize, BigInt(f.length), true);
      dv.setBigInt64(outMtime, 0n, true);
      return 0;
    },
  };

  return {
    imports,
    bind(m) { memory = m; },
    // Exposed so a node leg can assert against the exact source bytes.
    files,
  };
}
