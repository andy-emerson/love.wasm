// Browser leg of the step-6.6a timer+system witness: the LÖVE core + real
// love.timer + real love.system driven in real Chromium (frames on
// requestAnimationFrame), via the shared harness (wasi/host/witness-harness.mjs),
// the shared WASI shim, and the love_system host. No browser APIs are touched by
// the host (pure linear-memory copies + baked deterministic values), so a blank
// page is enough (no WebGL2, unlike the 6.3 window leg) — timer's getTime rides
// the browser's real clock_time_get through node:wasi's cross-check and V8's here.
// Usage: node run-browser-timer-system.mjs <love-timer-system.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeSystemHost } from '../host/system-host.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-timer-system.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-timer-system.wasm').toString('base64');

const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: bootSrc,
  driverSrc: driveWitness.toString(), shimSrc: makeWasiShim.toString(),
  systemHostSrc: makeSystemHost.toString(),
  withNow: false,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
