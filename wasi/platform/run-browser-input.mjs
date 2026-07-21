// Browser leg of the step-6.4 input witness: the LÖVE core + real love.event/
// keyboard/mouse driven in real Chromium (frames on requestAnimationFrame), via
// the shared harness (wasi/host/witness-harness.mjs), the shared WASI shim, the
// love_input host (pre-seeded DOM-event queue), and the shared love_fs host
// (love.mouse/image link filesystem, though this witness reads no file). No
// browser APIs are touched by the hosts — pure linear-memory copies — so a blank
// page is enough (no WebGL2, unlike the 6.3 window leg).
// Usage: node run-browser-input.mjs <love-input.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeInputHost } from '../host/input-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-input.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-input.wasm').toString('base64');

const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: bootSrc,
  driverSrc: driveWitness.toString(), shimSrc: makeWasiShim.toString(),
  inputHostSrc: makeInputHost.toString(),
  fsHostSrc: makeFsHost.toString(),
  withNow: false,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
