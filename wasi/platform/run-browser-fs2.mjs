// Browser leg of the step-6.2 filesystem witness: the LÖVE core + real
// love.filesystem driven in real Chromium (frames on requestAnimationFrame),
// via the shared harness (wasi/host/witness-harness.mjs), the shared WASI shim,
// and the shared love_fs host. The host uses no browser APIs (pure linear-memory
// copies), so no secure context / server is needed — a blank page is enough.
// Usage: node run-browser-fs2.mjs <love-fs2.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-fs2.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-fs2.wasm').toString('base64');

const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: bootSrc,
  driverSrc: driveWitness.toString(), shimSrc: makeWasiShim.toString(),
  fsHostSrc: makeFsHost.toString(),
  withNow: false,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
