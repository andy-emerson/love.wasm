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
