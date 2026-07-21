// Node leg of the filesystem directory-enumeration witness: instantiate the
// reactor (LÖVE core + real love.filesystem, the same fs2 artifact) under node's
// WASI with the love_fs host bound, and run the enumeration transcript. The host
// now fulfils fs_list (added beside fs_size/fs_read/fs_stat/fs_write/...).
// Usage: node run-node-fs-list.mjs <love-fs2.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-fs-list.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-fs2.wasm');

const fs = makeFsHost();
const ok = await runReactorNode(bytes, driveWitness, bootSrc, {
  extraImports: { love_fs: fs.imports },
  onInstance: (instance) => fs.bind(instance.exports.memory),
});
process.exit(ok ? 0 : 1);
