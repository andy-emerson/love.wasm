// Node leg of the step-3 boot witness.
// Usage: node run-node.mjs <love-boot.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WASI } from 'node:wasi';
import { driveBoot } from './driver.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-boot.lua'), 'utf8');

const wasi = new WASI({ version: 'preview1' });
const bytes = readFileSync(process.argv[2] ?? 'love-boot.wasm');
const { instance } = await WebAssembly.instantiate(bytes, wasi.getImportObject());
wasi.initialize(instance);

const ok = await driveBoot(
  instance.exports, bootSrc,
  (cb) => setTimeout(cb, 0),
  (line) => console.log(line),
);
process.exit(ok ? 0 : 1);
