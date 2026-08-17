// D9 instrument: run the draw-call sweep against real WebGL2 in Chromium and
// report the curve.
//
// This is a PROBE, not a witness. Every other runner under wasi/ renders a
// verdict that CI can enforce; this one cannot, because its output is a
// measurement and a measurement is a property of the machine it ran on, not of
// the code. It exits non-zero only when the run itself failed — never because a
// number was large. Wiring it into CI as a gate would be a category error, and
// on a GitHub runner it would gate on SwiftShader (see below).
//
// PROVENANCE IS PART OF THE RESULT. The sweep exists to separate submission cost
// from fill cost, and a software rasteriser inverts that ratio: fill becomes
// CPU-bound and dominates, burying exactly the signal we came for. So the driver
// reads the unmasked renderer string and, when it recognises a software one,
// prints the table with the verdict withheld rather than letting a plausible
// number circulate unlabelled.
//
// Usage: node run-browser-bench.mjs [wasm]
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeWebGLWinHost } from '../host/webgl-win-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { makeInputHost } from '../host/input-host.mjs';
import { makeSystemHost } from '../host/system-host.mjs';
import { makeAudioHost } from '../host/audio-host.mjs';
import { makeGamepadHost } from '../host/gamepad-host.mjs';
import { runInChromium } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const wasmPath = process.argv[2] ?? join(root, 'wasi/shell/love-game.wasm');

const b64 = readFileSync(wasmPath).toString('base64');
const boot = readFileSync(join(root, 'wasi/platform/witness-frame.lua'), 'utf8');

function collect(dir) {
  const out = {};
  const walk = (d) => {
    for (const name of readdirSync(d)) {
      const p = join(d, name);
      if (statSync(p).isDirectory()) walk(p);
      else out[relative(dir, p).split(sep).join('/')] = readFileSync(p).toString('base64');
    }
  };
  walk(dir);
  return out;
}
const project = collect(join(here, 'project'));

async function benchPageFn({ b64, boot, project, shimSrc, winHostSrc, fsHostSrc, inputHostSrc, systemHostSrc, audioHostSrc, gamepadHostSrc }) {
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const shim = (new Function('return ' + shimSrc)())();
  const host = (new Function('return ' + winHostSrc)())();
  const fs = (new Function('return ' + fsHostSrc)())();
  const system = (new Function('return ' + systemHostSrc)())();
  const audio = (new Function('return ' + audioHostSrc)())();
  const gamepad = (new Function('return ' + gamepadHostSrc)())();
  // Same silencing as the corpus driver: the input host's baked fixture script
  // ends in a QUIT record, which love.run obeys, and the sweep has no user.
  const rawInput = (new Function('return ' + inputHostSrc)())();
  const input = { ...rawInput, imports: { ...rawInput.imports, input_poll: () => 0 } };
  const lines = [];
  const log = (s) => lines.push(s);
  const te = new TextEncoder();
  const td = new TextDecoder();

  if (!host.haveContext || !host.haveContext()) return { ok: false, lines, error: 'no WebGL2 context' };

  // Provenance, from a throwaway 1x1 context rather than the engine's own. The
  // host keeps its context private in a closure and, with no canvas factory
  // passed, draws to an OffscreenCanvas that is in no document — so there is
  // nothing to query for it. The unmasked renderer names the driver behind the
  // browser, not the individual context, so a probe context answers identically
  // and disturbs no engine state. haveContext() above already does this.
  let renderer = 'unknown';
  try {
    const gl = new OffscreenCanvas(1, 1).getContext('webgl2');
    const dbg = gl && gl.getExtension('WEBGL_debug_renderer_info');
    if (gl) renderer = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
  } catch { /* provenance is best-effort; the run is still valid without it */ }

  try {
    for (const k of Object.keys(fs.files)) delete fs.files[k];
    for (const [name, b] of Object.entries(project))
      fs.files[name] = Uint8Array.from(atob(b), (c) => c.charCodeAt(0));

    const module = await WebAssembly.compile(bytes);
    shim.autostub(module);
    const instance = await WebAssembly.instantiate(module, {
      wasi_snapshot_preview1: shim.imports,
      love_gl: host.glImports,
      love_win: host.winImports,
      love_fs: fs.imports,
      love_input: input.imports,
      love_system: system.imports,
      love_audio: audio.imports,
      love_gamepad: gamepad.imports,
    });
    const x = instance.exports;
    shim.bind(x.memory);
    host.bind(x.memory, x.malloc);
    fs.bind(x.memory);
    input.bind(x.memory);
    system.bind(x.memory);
    audio.bind(x.memory);
    gamepad.bind(x.memory);
    x._initialize();

    const put = (s) => { const b = te.encode(s); const p = x.pump_in(b.length); new Uint8Array(x.memory.buffer).set(b, p); return b.length; };
    const out = () => { const p = x.pump_out(); return td.decode(new Uint8Array(x.memory.buffer).slice(p, p + x.pump_out_len())); };
    const tick = () => new Promise((r) => requestAnimationFrame(r));

    let st = x.pump_boot(put(boot));
    if (st === -2) return { ok: false, lines, renderer, stdout: shim.stdout, error: 'boot error: ' + out() };

    // The sweep's own ABORT_MS bounds the work; this bounds a sweep that never
    // reaches its last cell at all.
    const MAX_FRAMES = 20000;
    let frames = 0;
    while (st >= 0 && frames < MAX_FRAMES) { await tick(); st = x.pump_frame(put('t')); frames++; }
    log('frames: ' + frames + ', final pump status: ' + st);
    if (st === -2) return { ok: false, lines, renderer, stdout: shim.stdout, error: 'runtime error after ' + frames + ' frames: ' + out() };
    if (frames >= MAX_FRAMES) return { ok: false, lines, renderer, stdout: shim.stdout, error: 'the sweep never finished within ' + MAX_FRAMES + ' frames' };

    const key = Object.keys(fs.saves).find((k) => /bench\.json$/.test(k));
    if (!key) return { ok: false, lines, renderer, stdout: shim.stdout, error: 'no bench.json in the save namespace; keys: ' + Object.keys(fs.saves).join(', ') };
    return { ok: true, lines, renderer, stdout: shim.stdout, json: td.decode(fs.saves[key]) };
  } catch (e) {
    const error = (e && typeof e.wasiExit === 'number') ? ('proc_exit(' + e.wasiExit + ')') : String(e);
    return { ok: false, lines, renderer, stdout: shim.stdout, error };
  }
}

const result = await runInChromium(benchPageFn, {
  b64, boot, project,
  shimSrc: makeWasiShim.toString(),
  winHostSrc: makeWebGLWinHost.toString(),
  fsHostSrc: makeFsHost.toString(),
  inputHostSrc: makeInputHost.toString(),
  systemHostSrc: makeSystemHost.toString(),
  audioHostSrc: makeAudioHost.toString(),
  gamepadHostSrc: makeGamepadHost.toString(),
});

for (const line of result.lines || []) console.log(line);
if (result.error) {
  if (result.stdout) console.log('--- wasm stdout (tail) ---\n' + result.stdout.slice(-8000).trimEnd());
  console.log('--- error: ' + result.error + ' ---');
  console.log('BENCH: FAILED TO RUN');
  process.exit(1);
}

const data = JSON.parse(result.json);
const rows = data.results;
const SOFTWARE = /swiftshader|llvmpipe|softpipe|software|lavapipe|microsoft basic/i;
const isSoftware = SOFTWARE.test(result.renderer || '');

console.log('\nrenderer: ' + result.renderer);
console.log(`warmup ${data.warmup} frame(s), median of ${data.measure}\n`);
console.log('mode       sprites     cpu ms    wall ms     us/draw');
console.log('--------------------------------------------------------');
for (const r of rows) {
  console.log(
    r.mode.padEnd(11) + String(r.n).padStart(7) +
    r.cpu_ms.toFixed(3).padStart(11) + r.wall_ms.toFixed(3).padStart(11) +
    (r.us_per_draw != null ? r.us_per_draw.toFixed(3).padStart(12) : ''.padStart(12)));
}
for (const mode of ['batched', 'unbatched']) {
  const at = data['abandoned_' + mode];
  if (at != null) console.log(`\n${mode}: ladder abandoned above n=${at} (cell cost >= ${data.abort_ms} ms)`);
}

// The derived figure: the largest sprite count each mode still draws inside a
// 60 Hz CPU budget. Batched is the fill/vertex ceiling; unbatched is the
// submission ceiling, and the second is the one a WebGPU backend would move.
const BUDGET_MS = 16.7;
const ceiling = (mode) => {
  const under = rows.filter((r) => r.mode === mode && r.cpu_ms <= BUDGET_MS);
  return under.length ? under[under.length - 1].n : null;
};
console.log(`\nlargest n under a ${BUDGET_MS} ms CPU budget:`);
for (const mode of ['batched', 'unbatched']) {
  const c = ceiling(mode);
  console.log(`  ${mode.padEnd(10)} ${c === null ? 'none — even the smallest cell exceeds it' : c}`);
}

if (isSoftware) {
  console.log('\n!! SOFTWARE RASTERISER — NO VERDICT.');
  console.log('!! This renderer has no GPU behind it, so fill cost is CPU-bound and');
  console.log('!! dominates the submission cost this sweep exists to isolate. The');
  console.log('!! table above shows the instrument works; the numbers say nothing');
  console.log('!! about WebGL2 on real hardware. Re-run on a machine with a GPU.');
}
console.log('\nBENCH: RAN (probe — no pass/fail)');
