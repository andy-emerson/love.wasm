// Node leg of the pump witness: instantiate the reactor under node's WASI
// and run the shared transcript. Usage: node run-node.mjs <love-pump.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WASI } from 'node:wasi';
import { drivePump } from './driver.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness.lua'), 'utf8');

const wasi = new WASI({ version: 'preview1' });
const bytes = readFileSync(process.argv[2] ?? 'love-pump.wasm');
const { instance } = await WebAssembly.instantiate(bytes, wasi.getImportObject());
wasi.initialize(instance);  // reactor: runs ctors, no _start

const ok = await drivePump(
  instance.exports, bootSrc,
  (cb) => setTimeout(cb, 0),
  () => performance.now(),
  (line) => console.log(line),
);
process.exit(ok ? 0 : 1);
