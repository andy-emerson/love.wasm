// Browser leg of the filesystem directory-enumeration witness: the LÖVE core +
// real love.filesystem (the fs2 artifact) driven in real Chromium via the shared
// harness, WASI shim, and the shared love_fs host (now fulfilling fs_list). The
// host uses no browser APIs (pure linear-memory copies), so a blank page suffices.
// Usage: node run-browser-fs-list.mjs <love-fs2.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-fs-list.lua'), 'utf8');
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
