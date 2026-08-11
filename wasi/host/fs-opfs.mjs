// The OPFS-backed save store (#55) — D2's design, implemented as an UPGRADE of
// the reference fs host rather than a fork of it. makeFsHost() stays the
// in-memory host every node witness stringifies and runs unchanged; this wraps
// one, so the love_fs import surface does not move and no witness has to know
// OPFS exists. Browser-only by nature (navigator.storage), so unlike fs-host.mjs
// it is NOT under the stringify-into-a-page contract — it is imported as an
// ordinary module by boot.mjs.
//
// D2's durability model (DESIGN.md), literally:
//   - the in-memory `saves` map remains the SYNCHRONOUS truth — OPFS on the main
//     thread is async under love.filesystem's sync write(), so every read and
//     write the engine sees is served from the map, exactly as before;
//   - every mutation schedules an eager async flush of that one path, all on one
//     promise chain so OPFS applies them in the order the engine issued them;
//   - pagehide / visibilitychange(hidden) re-schedule any flush that failed —
//     the page's last chance. The declared residual is a force-kill inside the
//     last-write window: eventual durability, declared, the model every shipped
//     browser game uses;
//   - hydrate() replays what OPFS holds back into `saves`, and the caller must
//     await it BEFORE pump_boot: love.boot reads conf.lua on its first frame,
//     and a file written last session must already shadow the project then.
//
// Layout (D2): a separate, per-game namespace — love-saves/<identity>/<path> —
// beside anything else the origin keeps in OPFS. The identity is a caller
// concern: t.identity lives in conf.lua and the engine only reports it after
// boot, which is too late for hydration, so boot.mjs derives it from the
// project source (or the consumer passes it explicitly).
//
//   let fs = makeFsHost();
//   fs = makeOpfsSaves(fs, { identity });
//   await fs.hydrate();                  // before pump_boot
//   ... instantiate with { love_fs: fs.imports }, then fs.bind(memory) ...
export function makeOpfsSaves(fs, { identity = 'default', onWarn = () => {} } = {}) {
  let memory;
  const td = new TextDecoder(), te = new TextEncoder();
  const readPath = (ptr, len) => td.decode(new Uint8Array(memory.buffer, ptr, len));

  // love-saves/<identity>/ — created on first use, shared by every flush.
  let dirPromise = null;
  const rootDir = () => {
    if (!dirPromise) dirPromise = navigator.storage.getDirectory()
      .then((r) => r.getDirectoryHandle('love-saves', { create: true }))
      .then((d) => d.getDirectoryHandle(identity, { create: true }));
    return dirPromise;
  };

  const walkTo = async (segs, create) => {
    let dir = await rootDir();
    for (const s of segs) dir = await dir.getDirectoryHandle(s, { create });
    return dir;
  };

  // Flush = converge OPFS to what the map says NOW for one path. Reading the
  // map at execution time (not capture time) makes a stale queued flush
  // harmless: a write overtaken by a remove finds the key gone and removes; two
  // writes to one path both land the final bytes. The host replaces a file's
  // Uint8Array wholesale on rewrite (it never mutates one in place), so the
  // value read here is never half-written.
  const syncPath = async (path) => {
    const segs = path.split('/').filter((s) => s.length > 0);
    const v = fs.saves[path];
    if (v instanceof Uint8Array) {
      const name = segs.pop();
      const fh = await (await walkTo(segs, true)).getFileHandle(name, { create: true });
      const w = await fh.createWritable();
      await w.write(v);
      await w.close();
    } else if (v) {
      // The DIR sentinel — any non-bytes value in the save map is a directory.
      await walkTo(segs, true);
    } else {
      // Removed. The parent may itself never have been flushed; nothing to do.
      const name = segs.pop();
      try {
        await (await walkTo(segs, false)).removeEntry(name);
      } catch (e) {
        if (e && e.name === 'NotFoundError') return;
        throw e;
      }
    }
  };

  // One chain serializes every flush; a failed path is remembered and retried
  // on pagehide/visibilitychange (D2's second flush point — with per-write
  // eager flushing the chain is normally already drained by then, so those
  // events exist to retry failures, not to do the day's work).
  let chain = Promise.resolve();
  const failed = new Set();
  const schedule = (path) => {
    chain = chain.then(() => syncPath(path)).then(
      () => { failed.delete(path); },
      (e) => { failed.add(path); onWarn(`saves: flush of ${path} failed — ${e && e.message ? e.message : e}`); });
  };
  const retry = () => { const ps = [...failed]; failed.clear(); for (const p of ps) schedule(p); };
  addEventListener('pagehide', retry);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') retry(); });

  return {
    ...fs,
    imports: {
      ...fs.imports,
      // The three mutators, each: decode the path, let the reference host do
      // exactly what it always did to the map, then flush that path. The path
      // must be decoded BEFORE delegating — fs_remove deletes the bytes the
      // pointer's validity has nothing to do with, but a future host could
      // reasonably reuse the scratch the path sits in.
      fs_write(pathPtr, pathLen, bufPtr, len) {
        const p = readPath(pathPtr, pathLen);
        const r = fs.imports.fs_write(pathPtr, pathLen, bufPtr, len);
        schedule(p);
        return r;
      },
      fs_remove(pathPtr, pathLen) {
        const p = readPath(pathPtr, pathLen);
        const r = fs.imports.fs_remove(pathPtr, pathLen);
        if (r === 0) schedule(p);
        return r;
      },
      // One schedule covers the intermediate directories fs_mkdir also creates:
      // syncPath walks to the leaf with create, so OPFS gains the same parents
      // the map just did.
      fs_mkdir(pathPtr, pathLen) {
        const p = readPath(pathPtr, pathLen).replace(/\/+$/, '');
        const r = fs.imports.fs_mkdir(pathPtr, pathLen);
        schedule(p);
        return r;
      },
    },
    bind(m) { memory = m; fs.bind(m); },

    // Load OPFS back into the save map. Replayed through the reference host's
    // OWN imports over a scratch "memory" (bind takes anything with a .buffer),
    // so hydration takes exactly the code path the engine's writes take — which
    // is also the only way in: the DIR sentinel a directory needs is private to
    // the host closure. Runs before the real memory exists; the caller's later
    // bind() replaces the scratch. Flushing is not re-entered because the inner
    // imports are called directly, below the wrapped ones.
    async hydrate() {
      // Advisory, fire-and-forget (D2): persistence against browser eviction;
      // a denial changes nothing about the flush model.
      try { navigator.storage.persist(); } catch { /* not offered */ }
      const replay = (path, bytes) => {
        const pb = te.encode(path);
        const buf = new Uint8Array(pb.length + (bytes ? bytes.length : 0));
        buf.set(pb, 0);
        if (bytes) buf.set(bytes, pb.length);
        fs.bind({ buffer: buf.buffer });
        if (bytes) fs.imports.fs_write(0, pb.length, pb.length, bytes.length);
        else fs.imports.fs_mkdir(0, pb.length);
      };
      let files = 0;
      const walk = async (dir, prefix) => {
        for await (const [name, handle] of dir.entries()) {
          const p = prefix ? prefix + '/' + name : name;
          if (handle.kind === 'directory') { replay(p, null); await walk(handle, p); }
          else { replay(p, new Uint8Array(await (await handle.getFile()).arrayBuffer())); files++; }
        }
      };
      await walk(await rootDir(), '');
      return { files };
    },

    // Exposed so a consumer (or a witness) can await the pending flushes.
    flushed: () => chain,
  };
}
