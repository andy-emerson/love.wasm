// Browser witness driver: instantiate a wasm32-wasi command module in a real
// browser with the shared hand-rolled WASI preview1 shim (no Emscripten, no
// node:wasi), capture stdout, and report the exit code. The launch + in-page
// body live in the shared harness (wasi/host/witness-harness.mjs); the shim
// (wasi/host/wasi-shim.mjs) is the seed of love-wasi's browser host.
//
// WITNESS_BROWSER selects the engine (default chromium). firefox (SpiderMonkey)
// and webkit (JavaScriptCore) are non-V8 engines — the same module running there
// is an independent cross-check of the standardized wasm encoding.
import { readFileSync } from 'node:fs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { runInBrowser, commandPageFn } from '../host/witness-harness.mjs';

const engine = process.env.WITNESS_BROWSER || 'chromium';
const wasmB64 = readFileSync(process.argv[2] ?? 'eh-witness.wasm').toString('base64');
const sentinel = process.argv[3] ?? 'EH-WITNESS: PASS';
const result = await runInBrowser(engine, commandPageFn, { b64: wasmB64, shimSrc: makeWasiShim.toString() });

console.log(`--- ${engine} stdout ---`);
console.log(result.out.trimEnd());
console.log('--- exit: ' + result.exit + (result.error ? '  error: ' + result.error : '') + ' ---');
process.exit(result.exit === 0 && result.out.includes(sentinel) ? 0 : 1);
