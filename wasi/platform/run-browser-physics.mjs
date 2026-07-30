// Browser leg of the love.physics (Box2D) link witness: the LÖVE core + real
// love.physics driven in real Chromium (frames on requestAnimationFrame), via the
// shared harness (wasi/host/witness-harness.mjs) and the shared WASI shim. No
// browser APIs are touched (physics is pure linear-memory compute), so a blank
// page is enough — no WebGL2, unlike the window/graphics legs — and no host import
// modules are bound (reactorPageFn builds none when no host srcs are passed).
// Usage: node run-browser-physics.mjs <love-physics.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-physics.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-physics.wasm').toString('base64');

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
