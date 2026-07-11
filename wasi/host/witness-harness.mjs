// The node-side witness harness shared by all three browser witness runners
// (step-0 command, step-2 pump, step-3 boot). #8 consolidated the in-page WASI
// shim into wasi/host/wasi-shim.mjs; this consolidates the runner scaffolding
// that surrounds it — the Playwright launch, the in-page instantiate/drive
// bodies, and the node:wasi reactor leg — so those stopped being copy-pasted
// three ways.
//
// Two kinds of export:
//   - runInChromium / runReactorNode run in NODE (they launch the browser or
//     node:wasi and may import node builtins freely).
//   - reactorPageFn / commandPageFn are SERIALIZED into the page by Playwright,
//     so they are self-contained by contract (no imports, no outer-scope refs) —
//     the same rule wasi-shim.mjs and the driver.mjs files obey. They rebuild
//     the shim and driver from source text passed in via their single argument.
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';
import { WASI } from 'node:wasi';

// Launch an installed Chromium and run one self-contained page function against
// its argument, returning whatever the page function returns.
export async function runInChromium(pageFn, arg) {
  // playwright-core is a dev-only dependency resolved from the invoking cwd
  // (same pattern as lua-wasi's browser witness), so it never lives in-repo.
  const require = createRequire(resolve(process.cwd(), 'noop.js'));
  const { chromium } = require('playwright-core');
  const executablePath = process.env.CHROMIUM && existsSync(process.env.CHROMIUM)
    ? process.env.CHROMIUM
    : undefined;  // otherwise let playwright resolve its installed chromium
  const browser = await chromium.launch(executablePath ? { executablePath } : {});
  try {
    const page = await browser.newPage();
    return await page.evaluate(pageFn, arg);
  } finally {
    await browser.close();
  }
}

// In-page: instantiate a wasm32-wasi COMMAND module, run _start, report the
// exit code. arg = { b64, shimSrc }. Self-contained (serialized into the page).
// A command that links more of libc than the trivial witnesses (e.g. vendored
// FreeType pulls in stdio → fd_fdstat_set_flags) imports preview1 calls the
// shim doesn't implement, so autostub ENOSYS-stubs the rest before instantiate —
// loudly absent, never silently wrong, same as the reactor path.
export async function commandPageFn({ b64, shimSrc }) {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const makeWasiShim = new Function('return ' + shimSrc)();
  const shim = makeWasiShim();
  let exit = -1;
  try {
    const module = await WebAssembly.compile(bytes);
    shim.autostub(module);
    const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: shim.imports });
    shim.bind(instance.exports.memory);
    instance.exports._start();
    exit = 0;                        // _start returned without proc_exit
  } catch (e) {
    if (e && typeof e.wasiExit === 'number') exit = e.wasiExit;
    else return { out: shim.stdout, exit: -1, error: String(e) };
  }
  return { out: shim.stdout, exit };
}

// In-page: instantiate a REACTOR, run its ctors, and drive it with the shared
// transcript on requestAnimationFrame (the pump's real cadence). The reactor
// imports more of preview1 than the shim implements (liolib pulls in
// fd_fdstat_set_flags etc.); shim.autostub ENOSYS-stubs the rest — loudly
// absent, not silently wrong. arg = { b64, boot, driverSrc, shimSrc, withNow };
// withNow appends a performance.now getter for drivers that take one (the pump).
// Self-contained (serialized into the page).
// audioHostSrc (optional) is makeAudioHost stringified: when present, the
// love_audio import surface is provided and, after the run, each Source's
// captured PCM is played through a real OfflineAudioContext — proving WebAudio
// resamples the source rate to the context rate AND the tone survives (not just
// that the seam carried it). toneHz is the frequency to recover.
export async function reactorPageFn({ b64, boot, driverSrc, shimSrc, audioHostSrc, toneHz, withNow }) {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const makeWasiShim = new Function('return ' + shimSrc)();
  const shim = makeWasiShim();
  const lines = [];
  let audio = null;
  const extra = {};
  if (audioHostSrc) {
    const makeAudioHost = new Function('return ' + audioHostSrc)();
    audio = makeAudioHost();
    extra.love_audio = audio.imports;
  }
  try {
    const module = await WebAssembly.compile(bytes);
    shim.autostub(module);
    const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: shim.imports, ...extra });
    shim.bind(instance.exports.memory);
    if (audio) audio.bind(instance.exports.memory);
    instance.exports._initialize();  // reactor ctors
    const drive = new Function('return ' + driverSrc)();
    const args = [instance.exports, boot, (cb) => requestAnimationFrame(cb)];
    if (withNow) args.push(() => performance.now());
    args.push((line) => lines.push(line));
    const ok = await drive(...args);

    // Post-run: render captured Sources through real WebAudio and recover the
    // tone from the RENDERED output (the browser did the resample + mix).
    let audioSources = 0, audioTone = null;
    if (audio) {
      const list = audio.sources();
      audioSources = list.length;
      let best = 0;
      for (const s of list) {
        if (!s.pcm.length) continue;
        const ctxRate = 48000;
        const frames = Math.max(1, Math.ceil(s.pcm.length * ctxRate / s.rate));
        const off = new OfflineAudioContext(1, frames, ctxRate);
        const buf = off.createBuffer(1, s.pcm.length, s.rate);
        buf.getChannelData(0).set(s.pcm);
        const node = off.createBufferSource(); node.buffer = buf; node.connect(off.destination); node.start();
        const rendered = await off.startRendering();
        const outCh = rendered.getChannelData(0);
        const r = audio.goertzel(outCh, ctxRate, toneHz) / (audio.goertzel(outCh, ctxRate, toneHz * 2.71 + 37) + 1e-9);
        best = Math.max(best, r);
      }
      audioTone = best;
    }
    return { ok, lines, stdout: shim.stdout, audioSources, audioTone };
  } catch (e) {
    // Decode the shim's proc_exit sentinel so it doesn't print [object Object].
    const error = (e && typeof e.wasiExit === 'number') ? ('proc_exit(' + e.wasiExit + ')') : String(e);
    return { ok: false, lines, stdout: shim.stdout, error };
  }
}

// Node leg: instantiate a reactor under node's WASI (an independent, complete
// WASI host — a deliberate cross-check against the hand-rolled browser shim,
// not a duplicate) and run the shared transcript. withNow appends a
// performance.now getter for drivers that take one (the pump). extraImports adds
// non-WASI import modules (e.g. { love_audio: audioHost.imports }); onInstance
// runs right after instantiate so a host can bind the instance's memory before
// any import fires.
export async function runReactorNode(bytes, driver, bootSrc, { withNow = false, extraImports = {}, onInstance } = {}) {
  const wasi = new WASI({ version: 'preview1' });
  const importObject = { ...wasi.getImportObject(), ...extraImports };
  const { instance } = await WebAssembly.instantiate(bytes, importObject);
  if (onInstance) onInstance(instance);
  wasi.initialize(instance);  // reactor: runs ctors, no _start
  const args = [instance.exports, bootSrc, (cb) => setTimeout(cb, 0)];
  if (withNow) args.push(() => performance.now());
  args.push((line) => console.log(line));
  return driver(...args);
}
