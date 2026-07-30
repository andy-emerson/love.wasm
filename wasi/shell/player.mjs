// The interactive shell — Beta step 1. A page that runs a LÖVE game you can play.
//
// Every seam this drives already exists and is witnessed; the shell is assembly,
// not new engine work. What it changes is who fills the seams. The witnesses
// stringify the host modules into a Playwright page, bake a fixed event script,
// and serve a canned project; here the hosts are imported as ordinary modules,
// input comes from real DOM events, and the drawing surface is a canvas in the
// document rather than an OffscreenCanvas.
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
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeWebGLWinHost } from '../host/webgl-win-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { makeSystemHost } from '../host/system-host.mjs';
import { makeAudioHost } from '../host/audio-host.mjs';
import { makeGamepadHost } from '../host/gamepad-host.mjs';
import { makeBrowserInputHost } from '../host/input-host-browser.mjs';

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
// canvas is created on demand by the window host and inserted here.
let canvas = null;
const newCanvas = (w, h) => {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  c.id = 'game';
  if (canvas) canvas.remove();
  stage.appendChild(c);
  canvas = c;
  input.attach(c);
  c.focus();
  log(`window.setMode ${w}x${h}`);
  return c;
};

const shim = makeWasiShim();
const win = makeWebGLWinHost(newCanvas);
const fs = makeFsHost();
const system = makeSystemHost();
const audio = makeAudioHost();
const gamepad = makeGamepadHost();
const input = makeBrowserInputHost();

const te = new TextEncoder(), td = new TextDecoder();

// Replace the canned project with a real one, read through the manifest contract.
// Files land in fs.files, the read-only project map; the writable save namespace
// (fs.saves) is left alone, so a game's saves never overwrite its source.
async function loadProject(base) {
  const baseUrl = new URL(base.endsWith('/') ? base : base + '/', location.href);
  const manRes = await fetch(new URL('manifest.json', baseUrl));
  if (!manRes.ok) throw new Error(`manifest.json: ${manRes.status} at ${baseUrl}`);
  const man = await manRes.json();
  const list = Array.isArray(man) ? man : man.files;
  if (!Array.isArray(list)) throw new Error('manifest.json has no "files" array');

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

  for (const k of Object.keys(fs.files)) delete fs.files[k];
  for (const [name, buf] of entries) fs.files[name] = buf;
  if (!fs.files['main.lua'])
    throw new Error('the project has no main.lua — LÖVE has nothing to run');
  return { count: entries.length, bytes: total };
}

// Frame cadence is the browser's, and a hidden or unfocused tab gets none: a
// game must not keep simulating in a tab nobody is looking at. love.timer's dt
// comes from the pump, so a paused tab resumes without a giant time step.
let running = false, paused = false, raf = 0;

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
  if (PROJECT_URL) {
    setStatus('loading project…');
    try {
      const { count, bytes } = await loadProject(PROJECT_URL);
      log(`project: ${count} file(s), ${bytes} bytes from ${PROJECT_URL}`);
    } catch (e) {
      setStatus('project failed to load', 'bad');
      log('project error: ' + e.message);
      return;
    }
  } else {
    log('project: none given, running the canned project (pass ?project=<url>)');
  }

  shim.autostub(module);
  const instance = await WebAssembly.instantiate(module, {
    wasi_snapshot_preview1: shim.imports,
    love_gl: win.glImports,
    love_win: win.winImports,
    love_fs: fs.imports,
    love_input: input.imports,
    love_gamepad: gamepad.imports,
    love_system: system.imports,
    love_audio: audio.imports,
  });
  const x = instance.exports;
  // Bind before any import can fire.
  shim.bind(x.memory);
  win.bind(x.memory, x.malloc);
  fs.bind(x.memory);
  system.bind(x.memory);
  audio.bind(x.memory);
  gamepad.bind(x.memory);
  input.bind(x.memory);
  x._initialize();

  // pump_in hands back a pointer to write into; take it before viewing memory,
  // since a growth during the call would detach an earlier view.
  const put = (s) => {
    const b = te.encode(s);
    const p = x.pump_in(b.length);
    new Uint8Array(x.memory.buffer).set(b, p);
    return b.length;
  };
  const out = () => {
    const p = x.pump_out();
    return td.decode(new Uint8Array(x.memory.buffer).slice(p, p + x.pump_out_len()));
  };

  let tapped = 0;
  const drainTap = () => {
    const s = shim.stdout || '';
    if (s.length > tapped) { log(s.slice(tapped).trimEnd()); tapped = s.length; }
  };

  let st = x.pump_boot(put(bootSrc));
  drainTap();
  if (st === -2) { setStatus('boot error', 'bad'); log(out()); return; }
  setStatus('running', 'good');
  running = true;

  const frame = () => {
    if (!running) return;
    if (paused) { raf = requestAnimationFrame(frame); return; }
    st = x.pump_frame(put('t'));
    drainTap();
    if (st === -2) { running = false; setStatus('runtime error', 'bad'); log(out()); return; }
    if (st < 0) { running = false; setStatus('quit', ''); log('the game exited'); return; }
    raf = requestAnimationFrame(frame);
  };
  raf = requestAnimationFrame(frame);

  // Pausing is the shell's job, not the input host's: the host reports focus and
  // visibility as events the game can see, and the shell decides whether to keep
  // pumping. A key held when focus is lost is still held when it returns, which
  // is what desktop does.
  const pause = (why) => { if (running && !paused) { paused = true; setStatus('paused (' + why + ')', ''); } };
  const resume = () => { if (running && paused) { paused = false; setStatus('running', 'good'); } };
  addEventListener('blur', () => pause('unfocused'));
  addEventListener('focus', resume);
  document.addEventListener('visibilitychange', () =>
    document.visibilityState === 'visible' ? resume() : pause('tab hidden'));

  // A browser tab has no close button the game owns, so quitting is explicit.
  el('quit').addEventListener('click', () => { input.quit(); });
}

main().catch((e) => { setStatus('failed', 'bad'); log('unhandled: ' + (e && e.message ? e.message : String(e))); });
