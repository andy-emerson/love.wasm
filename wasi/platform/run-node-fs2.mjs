// Node leg of the step-6.2 filesystem witness: instantiate the reactor (the
// LÖVE core + real love.filesystem) under node's WASI — an independent, complete
// WASI host, the cross-check against the hand-rolled browser shim — with the
// love_fs host bound, and run the shared transcript.
// Usage: node run-node-fs2.mjs <love-fs2.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-fs2.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-fs2.wasm');

const fs = makeFsHost();
const ok = await runReactorNode(bytes, driveWitness, bootSrc, {
  extraImports: { love_fs: fs.imports },
  onInstance: (instance) => fs.bind(instance.exports.memory),
});
process.exit(ok ? 0 : 1);
