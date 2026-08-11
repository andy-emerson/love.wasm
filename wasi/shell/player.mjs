// The interactive shell — Beta step 1. A page that runs a LÖVE game you can play.
//
// Every seam this drives already exists and is witnessed; the shell is assembly,
// not new engine work. The consumer-invariant wiring — instantiate, bind, boot,
// the frame loop — lives in boot.mjs (#57), and this page is its first caller:
// what remains here is exactly what varies per consumer — producing the file
// map (a manifest over HTTP), the canvas's place in this document, where the
// log goes, and the live-edit poll.
//
// It is a game PLAYER and nothing more: load a project, run it, show it. No
// editor, no REPL, no agent UI — those belong to a downstream consumer, which
// this shell exists to prove is possible, not to become.
//
// Packaging is deliberately untouched (#7): the raw .wasm is fetched as-is.
//
//   wasi/shell/serve.sh            # then open the printed URL
//
// The artifact is expected at wasi/shell/love-game.wasm by default, or wherever
// ?wasm= points. Build one with:
//
//   PREFIX=$PREFIX OUT=wasi/shell/love-game.wasm wasi/platform/build-game.sh
import { boot } from './boot.mjs';

const params = new URLSearchParams(location.search);
const WASM_URL = params.get('wasm') || './love-game.wasm';
// A project is a base URL containing manifest.json — {"files": ["main.lua", …]} —
// plus those files. Deliberately not tied to this dev server: any static host
// that exposes a manifest beside the files works, and serve.sh synthesizes one
// for a local folder so pointing it at a game directory is enough. Without
// ?project the canned project in fs-host.mjs runs, which is a real LÖVE game.
const PROJECT_URL = params.get('project');
// A project is game source, not a disk image. The cap is here so a wrong URL
// fails with a clear message instead of exhausting memory.
const MAX_PROJECT_BYTES = 256 * 1024 * 1024;
// LÖVE's own boot wrapper: require love, then love.boot, which reads conf.lua and
// main.lua through love.filesystem. Game-agnostic, and shared with the frame and
// game witnesses rather than copied — one source for how this engine boots.
const BOOT_URL = '../platform/witness-frame.lua';

const el = (id) => document.getElementById(id);
const statusEl = el('status');
const logEl = el('log');
const stage = el('stage');

const setStatus = (s, cls) => { statusEl.textContent = s; statusEl.className = cls || ''; };
const log = (s) => {
  logEl.textContent += s + '\n';
  logEl.scrollTop = logEl.scrollHeight;
};

// The visible drawing surface. love.window.setMode decides the size, so the
// canvas is created on demand and inserted here; boot() attaches the input
// listeners to whatever this returns.
let canvas = null;
const newCanvas = (w, h) => {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  c.id = 'game';
  if (canvas) canvas.remove();
  stage.appendChild(c);
  canvas = c;
  log(`window.setMode ${w}x${h}`);
  return c;
};

// Produce the path -> Uint8Array map (EMBEDDING.md §2: the map is the contract;
// this manifest-over-HTTP loader is one way to fill it). The read-only project
// only — the writable save namespace is boot()'s host's business, so a game's
// saves never overwrite its source.
async function loadProject(base) {
  const baseUrl = new URL(base.endsWith('/') ? base : base + '/', location.href);
  const manRes = await fetch(new URL('manifest.json', baseUrl));
  if (!manRes.ok) throw new Error(`manifest.json: ${manRes.status} at ${baseUrl}`);
  const man = await manRes.json();
  const raw = Array.isArray(man) ? man : man.files;
  if (!Array.isArray(raw)) throw new Error('manifest.json has no "files" array');
  // An entry is a path, or a path with change-detection metadata. A hand-written
  // manifest of plain strings stays valid; serve.sh supplies mtime and size so
  // live-edit can tell what changed without re-reading the project.
  const list = raw.map((e) => (typeof e === 'string' ? { path: e } : e))
                  .map((e) => e && e.path);
  const meta = new Map(raw.map((e) => (typeof e === 'string'
    ? [e, null]
    : [e.path, `${e.mtime}:${e.size}`])));

  // Fetch concurrently — a project is many small files, and serially would make
  // load time the file count times the round trip.
  let total = 0;
  const entries = await Promise.all(list.map(async (name) => {
    if (typeof name !== 'string' || name.startsWith('/') || name.split('/').includes('..'))
      throw new Error(`manifest entry is not a project-relative path: ${name}`);
    const res = await fetch(new URL(name, baseUrl));
    if (!res.ok) throw new Error(`${name}: ${res.status}`);
    // ArrayBuffer, not text: assets are binary and a project must round-trip
    // byte-exact, the same property the filesystem witnesses assert.
    const buf = new Uint8Array(await res.arrayBuffer());
    total += buf.length;
    if (total > MAX_PROJECT_BYTES) throw new Error('project exceeds the size cap');
    return [name, buf];
  }));

  const files = Object.fromEntries(entries);
  if (!files['main.lua'])
    throw new Error('the project has no main.lua — LÖVE has nothing to run');
  return { files, count: entries.length, bytes: total, base: baseUrl, meta };
}

// Live-edit, at module granularity, over the mechanism step 6.7 already ships:
// replace the source the VFS serves, then invalidate() drops the game's Lua
// modules from package.loaded so the next require re-reads and re-evaluates them.
// love and every love.* submodule survive, so the engine is not rebooted.
//
// main.lua is NOT live yet. LÖVE does not require() it, so nothing caches it
// and nothing re-reads it. D4 (#47) has closed as function-body hotswap — the
// chosen mechanism replaces the bodies of love.update/love.draw in place, with
// live state surviving — but that mechanism is not built, so until it lands
// restart is the honest report rather than a silent no-op.
// conf.lua is read once before the window exists, so it cannot be live either.
// For both, the honest answer is a restart, and the shell says so rather than
// silently doing nothing.
const RESTART_ONLY = new Set(['main.lua', 'conf.lua']);

function watchProject(project, handle, intervalMs = 700) {
  let meta = project.meta;
  let stop = false;
  const poll = async () => {
    if (stop) return;
    try {
      const res = await fetch(new URL('manifest.json', project.base), { cache: 'no-store' });
      if (res.ok) {
        const man = await res.json();
        const raw = Array.isArray(man) ? man : man.files;
        const next = new Map((raw || []).map((e) => (typeof e === 'string'
          ? [e, null] : [e.path, `${e.mtime}:${e.size}`])));

        const changed = [];
        for (const [p, sig] of next) {
          const was = meta.get(p);
          // A null signature means the manifest carries no metadata, so change
          // cannot be detected — treat it as unchanged rather than reloading
          // the project on every poll.
          if (sig !== null && (was === undefined || was !== sig)) changed.push(p);
        }
        const gone = [...meta.keys()].filter((p) => !next.has(p));
        meta = next;

        if (changed.length || gone.length) {
          const live = changed.filter((p) => !RESTART_ONLY.has(p));
          const needsRestart = [...changed, ...gone].filter((p) => RESTART_ONLY.has(p));

          for (const p of gone) delete handle.files[p];
          for (const p of live) {
            const r = await fetch(new URL(p, project.base), { cache: 'no-store' });
            if (r.ok) handle.files[p] = new Uint8Array(await r.arrayBuffer());
            else log(`live-edit: ${p} vanished (${r.status})`);
          }
          if (live.length || gone.length) {
            const dropped = handle.invalidate();
            log(`live-edit: ${[...live, ...gone].join(', ')} → ${dropped} module(s) invalidated`);
          }
          if (needsRestart.length)
            log(`live-edit: ${needsRestart.join(', ')} changed — reload the page to apply (#47)`);
        }
      }
    } catch (e) {
      // A poll failure is not fatal: the server may be restarting under us.
      log('live-edit: poll failed — ' + e.message);
    }
    setTimeout(poll, intervalMs);
  };
  setTimeout(poll, intervalMs);
  return { stop() { stop = true; } };
}

async function main() {
  setStatus('loading…');
  let bootSrc, module;
  try {
    const [bootRes, wasmRes] = await Promise.all([fetch(BOOT_URL), fetch(WASM_URL)]);
    if (!bootRes.ok) throw new Error(`${BOOT_URL}: ${bootRes.status}`);
    if (!wasmRes.ok) throw new Error(`${WASM_URL}: ${wasmRes.status} — build it with wasi/platform/build-game.sh`);
    bootSrc = await bootRes.text();
    // compileStreaming compiles while the bytes arrive; the union artifact is
    // large enough for that to be the difference between instant and a pause.
    module = await WebAssembly.compileStreaming(wasmRes);
  } catch (e) {
    setStatus('failed to load', 'bad');
    log('load error: ' + e.message);
    return;
  }

  // The project has to be in place before pump_boot: love.boot reads conf.lua and
  // main.lua through love.filesystem on its very first frame.
  let project = null;
  if (PROJECT_URL) {
    setStatus('loading project…');
    try {
      project = await loadProject(PROJECT_URL);
      log(`project: ${project.count} file(s), ${project.bytes} bytes from ${PROJECT_URL}`);
    } catch (e) {
      setStatus('project failed to load', 'bad');
      log('project error: ' + e.message);
      return;
    }
  } else {
    log('project: none given, running the canned project (pass ?project=<url>)');
  }

  let handle;
  try {
    handle = await boot({
      wasm: module,
      bootSrc,
      files: project ? project.files : null,
      canvas: newCanvas,
      onLog: log,
      onStatus: (state, detail) => {
        if (state === 'running') setStatus('running', 'good');
        else if (state === 'paused') setStatus('paused (' + detail + ')', '');
        else if (state === 'error') { setStatus('runtime error', 'bad'); log(detail); }
        else if (state === 'quit') { setStatus('quit', ''); log('the game exited'); }
      },
    });
  } catch (e) {
    setStatus('boot error', 'bad');
    log(e.message);
    return;
  }

  // Watch only a mounted project: the canned one has no source on disk to change.
  if (project) watchProject(project, handle);

  el('quit').addEventListener('click', () => { handle.quit(); });
}

main().catch((e) => { setStatus('failed', 'bad'); log('unhandled: ' + (e && e.message ? e.message : String(e))); });
