// Chromium leg of the step-4 (4.1c) love.graphics witness: the real LÖVE core
// with love.graphics booting under the pump in real Chromium, its opengl backend
// reseamed to a real WebGL2 context (webgl-host.mjs), driven through the
// graphics-ext bridge to setMode + clear + read the pixel back. The in-page
// function is self-contained (serialized by Playwright): it rebuilds the WASI
// shim, the WebGL2 host, and the driver from source, instantiates the reactor
// with both import modules, binds memory + the exported malloc (glGetString
// needs it), runs the ctors, and drives the witness lua.
// Usage: node run-browser-love.mjs <love-graphics.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveGraphics } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeWebGLHost } from '../host/webgl-host.mjs';
import { runInChromium } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
// argv[2]: wasm module; argv[3]: witness lua (defaults to the 4.1c clear witness).
const boot = readFileSync(process.argv[3] ?? join(here, 'witness-graphics.lua'), 'utf8');
const b64 = readFileSync(process.argv[2] ?? join(here, 'love-graphics.wasm')).toString('base64');

async function loveGraphicsPageFn({ b64, boot, shimSrc, hostSrc, driverSrc }) {
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
      love_gl: host.imports,
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

const result = await runInChromium(loveGraphicsPageFn, {
  b64, boot,
  shimSrc: makeWasiShim.toString(),
  hostSrc: makeWebGLHost.toString(),
  driverSrc: driveGraphics.toString(),
});

console.log('--- browser transcript ---');
for (const line of result.lines || []) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
