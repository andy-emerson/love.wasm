// Browser leg of the love.sound decoder witness: the LÖVE core + real love.sound
// decoders driven in real Chromium (frames on requestAnimationFrame), via the
// shared harness and WASI shim. The witness decodes from a Data — no browser APIs
// touched, no host import modules bound — so a blank page suffices (no WebGL2).
// The real Ogg asset is base64-injected into the witness source here, identical to
// the node leg. Usage: node run-browser-sound.mjs <love-sound.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const oggB64 = readFileSync(join(root, 'testing/resources/clickmono.ogg')).toString('base64');
const bootSrc = readFileSync(join(here, 'witness-sound.lua'), 'utf8').replace('__OGG_B64__', oggB64);
const wasmB64 = readFileSync(process.argv[2] ?? 'love-sound.wasm').toString('base64');

const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: bootSrc,
  driverSrc: driveWitness.toString(), shimSrc: makeWasiShim.toString(),
  withNow: false,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
