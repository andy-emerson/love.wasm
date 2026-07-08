// Browser leg of the pump witness: the reactor in real Chromium, frames on
// requestAnimationFrame (the pump's real cadence), via the shared witness
// harness (wasi/host/witness-harness.mjs) and the shared WASI shim.
// Usage: node run-browser.mjs <love-pump.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { drivePump } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-pump.wasm').toString('base64');

// driver.mjs and wasi-shim.mjs are self-contained by contract, so their
// function bodies are rebuilt inside the page from source text.
const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: bootSrc,
  driverSrc: drivePump.toString(), shimSrc: makeWasiShim.toString(),
  withNow: true,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
