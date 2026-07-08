// Browser witness driver: instantiate a wasm32-wasi command module in real
// Chromium with the shared hand-rolled WASI preview1 shim (no Emscripten, no
// node:wasi), capture stdout, and report the exit code. The launch + in-page
// body live in the shared harness (wasi/host/witness-harness.mjs); the shim
// (wasi/host/wasi-shim.mjs) is the seed of love-wasi's browser host.
import { readFileSync } from 'node:fs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { runInChromium, commandPageFn } from '../host/witness-harness.mjs';

const wasmB64 = readFileSync(process.argv[2] ?? 'eh-witness.wasm').toString('base64');
const result = await runInChromium(commandPageFn, { b64: wasmB64, shimSrc: makeWasiShim.toString() });

console.log('--- browser stdout ---');
console.log(result.out.trimEnd());
console.log('--- exit: ' + result.exit + (result.error ? '  error: ' + result.error : '') + ' ---');
process.exit(result.exit === 0 && result.out.includes('EH-WITNESS: PASS') ? 0 : 1);
