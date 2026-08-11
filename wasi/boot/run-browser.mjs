// Browser leg of the step-3 boot witness: the LÖVE core booting in real
// Chromium, frames on requestAnimationFrame, via the shared witness harness
// (wasi/host/witness-harness.mjs) and the shared WASI shim.
// Usage: node run-browser.mjs <love-boot.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveBoot } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-boot.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-boot.wasm').toString('base64');

const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: bootSrc,
  driverSrc: driveBoot.toString(), shimSrc: makeWasiShim.toString(),
  withNow: false,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout (love error_printer etc.) ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
