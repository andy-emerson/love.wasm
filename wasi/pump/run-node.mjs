// Node leg of the pump witness: instantiate the reactor under node's WASI and
// run the shared transcript (via wasi/host/witness-harness.mjs).
// Usage: node run-node.mjs <love-pump.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { drivePump } from './driver.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-pump.wasm');

const ok = await runReactorNode(bytes, drivePump, bootSrc, { withNow: true });
process.exit(ok ? 0 : 1);
