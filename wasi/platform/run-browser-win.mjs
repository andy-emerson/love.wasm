// Chromium leg of the step-6.3 love.window witness: the LÖVE core + real
// love.window + love.graphics booting under the pump in real Chromium, with the
// combined love_gl + love_win host (wasi/host/webgl-win-host.mjs) serving both
// import modules over ONE real WebGL2 context. love.window.setMode drives the
// host to create the canvas + context, graphics binds to it, and present() reads
// the presented backbuffer back for the captureScreenshot close of step 4.
//
// This is Chromium-only: it needs a real WebGL2 context (node has no WebGL2),
// the same constraint the graphics real-backend legs carry. The in-page function
// is self-contained (serialized by Playwright): it rebuilds the WASI shim, the
// combined host, and the driver from source, instantiates the reactor with both
// import modules, binds memory + the exported malloc (glGetString needs it), runs
// the ctors, and drives the witness lua.
// Usage: node run-browser-win.mjs <love-win.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeWebGLWinHost } from '../host/webgl-win-host.mjs';
import { runInChromium } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const boot = readFileSync(process.argv[3] ?? join(here, 'witness-win.lua'), 'utf8');
const b64 = readFileSync(process.argv[2] ?? join(here, 'love-win.wasm')).toString('base64');

async function loveWinPageFn({ b64, boot, shimSrc, hostSrc, driverSrc }) {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const shim = (new Function('return ' + shimSrc)())();
  const host = (new Function('return ' + hostSrc)())();
  if (!host.haveContext()) return { ok: false, lines: [], error: 'no WebGL2 context' };
  const lines = [];
  try {
    const module = await WebAssembly.compile(bytes);
    shim.autostub(module);
    const instance = await WebAssembly.instantiate(module, {
      wasi_snapshot_preview1: shim.imports,
      love_gl: host.glImports,
      love_win: host.winImports,
    });
    shim.bind(instance.exports.memory);
    host.bind(instance.exports.memory, instance.exports.malloc);
    instance.exports._initialize();
    const drive = (new Function('return ' + driverSrc)());
    const ok = await drive(instance.exports, boot, (cb) => requestAnimationFrame(cb), (l) => lines.push(l));
    return { ok, lines, stdout: shim.stdout };
  } catch (e) {
    const error = (e && typeof e.wasiExit === 'number') ? ('proc_exit(' + e.wasiExit + ')') : String(e);
    return { ok: false, lines, stdout: shim.stdout, error };
  }
}

const result = await runInChromium(loveWinPageFn, {
  b64, boot,
  shimSrc: makeWasiShim.toString(),
  hostSrc: makeWebGLWinHost.toString(),
  driverSrc: driveWitness.toString(),
});

console.log('--- browser transcript ---');
for (const line of result.lines || []) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
