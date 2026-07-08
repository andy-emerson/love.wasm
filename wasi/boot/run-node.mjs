// Node leg of the step-3 boot witness: instantiate the reactor under node's
// WASI and run the shared transcript (via wasi/host/witness-harness.mjs).
// Usage: node run-node.mjs <love-boot.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveBoot } from './driver.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-boot.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-boot.wasm');

const ok = await runReactorNode(bytes, driveBoot, bootSrc);
process.exit(ok ? 0 : 1);
