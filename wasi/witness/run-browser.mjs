// Browser witness driver: instantiate a wasm32-wasi command module in real
// Chromium with the shared hand-rolled WASI preview1 shim (no Emscripten, no
// node:wasi), capture stdout, and report the exit code. The shim
// (wasi/host/wasi-shim.mjs) is the seed of love-wasi's browser host; it is
// stringified into the page the same way driver.mjs is.
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createRequire } from 'node:module';
import { makeWasiShim } from '../host/wasi-shim.mjs';

// playwright-core is a dev-only dependency resolved from the invoking cwd
// (same pattern as lua-wasi's browser witness), so it never lives in-repo.
const require = createRequire(resolve(process.cwd(), 'noop.js'));
const { chromium } = require('playwright-core');
const executablePath = process.env.CHROMIUM && existsSync(process.env.CHROMIUM)
  ? process.env.CHROMIUM
  : undefined;  // otherwise let playwright resolve its installed chromium

const wasmB64 = readFileSync(process.argv[2] ?? 'eh-witness.wasm').toString('base64');

const browser = await chromium.launch(executablePath ? { executablePath } : {});
const page = await browser.newPage();

const result = await page.evaluate(async ({ b64, shimSrc }) => {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const makeWasiShim = new Function('return ' + shimSrc)();
  const shim = makeWasiShim();
  let exit = -1;
  try {
    const { instance } = await WebAssembly.instantiate(bytes, { wasi_snapshot_preview1: shim.imports });
    shim.bind(instance.exports.memory);
    instance.exports._start();
    exit = 0;                        // _start returned without proc_exit
  } catch (e) {
    if (e && typeof e.wasiExit === 'number') exit = e.wasiExit;
    else return { out: shim.stdout, exit: -1, error: String(e) };
  }
  return { out: shim.stdout, exit };
}, { b64: wasmB64, shimSrc: makeWasiShim.toString() });

await browser.close();
console.log('--- browser stdout ---');
console.log(result.out.trimEnd());
console.log('--- exit: ' + result.exit + (result.error ? '  error: ' + result.error : '') + ' ---');
process.exit(result.exit === 0 && result.out.includes('EH-WITNESS: PASS') ? 0 : 1);
