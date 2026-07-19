// Node leg of the step-6.1 filesystem-seam witness: instantiate the reactor
// under node's WASI (an independent, complete WASI host — the cross-check
// against the hand-rolled browser shim) with the love_fs host bound, and run
// the shared transcript.
// Usage: node run-node.mjs <love-fs.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-fs.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-fs.wasm');

const fs = makeFsHost();
const ok = await runReactorNode(bytes, driveWitness, bootSrc, {
  extraImports: { love_fs: fs.imports },
  onInstance: (instance) => fs.bind(instance.exports.memory),
});
process.exit(ok ? 0 : 1);
