// Browser leg of the love.shim witness: the same transcript in real Chromium.
// The shim is pure Lua and physics is pure compute, so no browser API is
// touched — but running it here is what proves the shim behaves identically on
// both engines rather than only under node's WASI.
// Usage: node run-browser-shim.mjs <love-physics.wasm>
import { readFileSync } from 'node:fs';
import { driveWitness } from '../platform/driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';
import { shimBootSrc } from './boot-src.mjs';

const wasmB64 = readFileSync(process.argv[2] ?? 'love-physics.wasm').toString('base64');

const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: shimBootSrc(),
  driverSrc: driveWitness.toString(), shimSrc: makeWasiShim.toString(),
  withNow: false,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
