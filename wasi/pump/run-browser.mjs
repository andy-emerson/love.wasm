// Browser leg of the pump witness: instantiate the reactor in real Chromium
// with the shared hand-rolled WASI preview1 shim (wasi/host/wasi-shim.mjs, the
// same one the step-0 witness uses), then run the shared transcript with frames
// driven by requestAnimationFrame — the pump's real production cadence.
// Usage: node run-browser.mjs <love-pump.wasm>
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { drivePump } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';

const require = createRequire(resolve(process.cwd(), 'noop.js'));
const { chromium } = require('playwright-core');
const executablePath = process.env.CHROMIUM && existsSync(process.env.CHROMIUM)
  ? process.env.CHROMIUM
  : undefined;

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-pump.wasm').toString('base64');

const browser = await chromium.launch(executablePath ? { executablePath } : {});
const page = await browser.newPage();

const result = await page.evaluate(async ({ b64, boot, driverSrc, shimSrc }) => {
  const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const makeWasiShim = new Function('return ' + shimSrc)();
  const shim = makeWasiShim();
  const lines = [];
  try {
    // The reactor imports more of preview1 than the shim implements (liolib
    // pulls in fd_fdstat_set_flags etc.); shim.autostub ENOSYS-stubs the rest —
    // loudly absent, not silently wrong.
    const module = await WebAssembly.compile(bytes);
    shim.autostub(module);
    const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: shim.imports });
    shim.bind(instance.exports.memory);
    instance.exports._initialize();  // reactor ctors
    const drivePump = new Function('return ' + driverSrc)();
    const ok = await drivePump(
      instance.exports, boot,
      (cb) => requestAnimationFrame(cb),
      () => performance.now(),
      (line) => lines.push(line),
    );
    return { ok, lines, stdout: shim.stdout };
  } catch (e) {
    return { ok: false, lines, stdout: shim.stdout, error: String(e) };
  }
}, {
  b64: wasmB64,
  boot: bootSrc,
  // driver.mjs and wasi-shim.mjs are self-contained by contract, so their
  // function bodies can be rebuilt inside the page from source text.
  driverSrc: drivePump.toString(),
  shimSrc: makeWasiShim.toString(),
});

await browser.close();
console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
