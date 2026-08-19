// Browser leg of the love.shim witness on the LOVE + DATA + MATH + FILESYSTEM
// artifact — the same transcript in real Chromium, over the hand-rolled WASI
// shim and the same fs host, so the filesystem and love.math tiers are shown
// identical on both engines rather than only under node's WASI.
// Usage: node run-browser-fs.mjs <love-fs2.wasm>
import { readFileSync } from 'node:fs';
import { driveWitness } from '../platform/driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';
import { shimBootSrc } from './boot-src.mjs';

const wasmB64 = readFileSync(process.argv[2] ?? 'love-fs2.wasm').toString('base64');

const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: shimBootSrc(),
  driverSrc: driveWitness.toString(), shimSrc: makeWasiShim.toString(),
  fsHostSrc: makeFsHost.toString(),
  withNow: false,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
