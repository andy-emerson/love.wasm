// Node leg of the raw-GL witness (step 4.1a): run the command module under
// node's built-in WASI with the mock love_gl host providing the GL import
// surface, and require a clean exit (the module returns 0 iff the pixel it read
// back matches the color it cleared). Usage: node run-node.mjs <witness-gl.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { WASI } from 'node:wasi';
import { makeGLHost } from '../host/gl-host.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bytes = readFileSync(process.argv[2] ?? join(here, 'witness-gl.wasm'));

const wasi = new WASI({ version: 'preview1' });
const gl = makeGLHost();
const { instance } = await WebAssembly.instantiate(bytes, {
  ...wasi.getImportObject(),
  love_gl: gl.imports,
});
gl.bind(instance.exports.memory);   // bind memory before _start touches an import
const code = wasi.start(instance);
process.exit(code);
