// Chromium leg of the raw-GL witness (step 4.1a): run the command module in
// real Chromium against a real WebGL2 context (gl-host-browser.mjs), so the
// pixel is cleared and read back through the browser's actual GL — not a mock.
// The in-page glCommandPageFn is self-contained (serialized by Playwright): it
// rebuilds the WASI shim and the GL host from source text, instantiates the
// command with both import modules, runs _start, and returns stdout + exit.
// Usage: node run-browser.mjs <witness-gl.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeBrowserGLHost } from '../host/gl-host-browser.mjs';
import { runInChromium } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const wasmB64 = readFileSync(process.argv[2] ?? join(here, 'witness-gl.wasm')).toString('base64');

// Self-contained: no outer-scope references; rebuilds shim + host from source.
async function glCommandPageFn({ b64, shimSrc, glHostSrc }) {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const shim = (new Function('return ' + shimSrc)())();
  const gl = (new Function('return ' + glHostSrc)())();
  if (!gl.haveContext()) return { out: '', exit: -1, error: 'no WebGL2 context' };
  let exit = -1;
  try {
    const module = await WebAssembly.compile(bytes);
    shim.autostub(module);
    const instance = await WebAssembly.instantiate(module, {
      wasi_snapshot_preview1: shim.imports,
      love_gl: gl.imports,
    });
    shim.bind(instance.exports.memory);
    gl.bind(instance.exports.memory);
    instance.exports._start();
    exit = 0;                          // _start returned without proc_exit
  } catch (e) {
    if (e && typeof e.wasiExit === 'number') exit = e.wasiExit;
    else return { out: shim.stdout, exit: -1, error: String(e) };
  }
  return { out: shim.stdout, exit };
}

const result = await runInChromium(glCommandPageFn, {
  b64: wasmB64,
  shimSrc: makeWasiShim.toString(),
  glHostSrc: makeBrowserGLHost.toString(),
});

if (result.out) console.log('--- wasm stdout ---\n' + result.out.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.exit === 0 ? 0 : 1);
