// Browser leg of the step-5 audio witness: the LÖVE core with love.audio
// booting in real Chromium, frames on requestAnimationFrame, via the shared
// witness harness (wasi/host/witness-harness.mjs) and the shared WASI shim.
// Usage: node run-browser.mjs <love-audio.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveAudio } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-audio.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-audio.wasm').toString('base64');

const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: bootSrc,
  driverSrc: driveAudio.toString(), shimSrc: makeWasiShim.toString(),
  withNow: false,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
