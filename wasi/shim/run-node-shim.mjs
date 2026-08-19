// Node leg of the love.shim witness (D21, #64), on the LOVE + DATA + PHYSICS
// artifact — the smallest build that carries the spring joints, which are the
// only part of the 11.5 -> 12 gap that is a units change rather than a rename.
// Usage: node run-node-shim.mjs <love-physics.wasm>
import { readFileSync } from 'node:fs';
import { driveWitness } from '../platform/driver.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';
import { shimBootSrc } from './boot-src.mjs';

const bytes = readFileSync(process.argv[2] ?? 'love-physics.wasm');
const ok = await runReactorNode(bytes, driveWitness, shimBootSrc(), {});
process.exit(ok ? 0 : 1);
