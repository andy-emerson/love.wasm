// Run a wasm32-wasi command module under node's built-in WASI and require
// a clean exit. Usage: node run-node.mjs <module.wasm>
import { readFileSync } from 'node:fs';
import { WASI } from 'node:wasi';

const wasi = new WASI({ version: 'preview1' });
const bytes = readFileSync(process.argv[2]);
const { instance } = await WebAssembly.instantiate(bytes, wasi.getImportObject());
const code = wasi.start(instance);
process.exit(code);
