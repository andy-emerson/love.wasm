// Node leg of the love.physics (Box2D) link witness: instantiate the reactor
// (LÖVE core + real love.physics) under node's WASI — an independent, complete
// WASI host, the cross-check against the hand-rolled browser shim — and run the
// shared transcript. love.physics is pure compute, so there are NO host imports
// to bind (no love_system / love_fs / love_gl): the WASI shim is the whole host.
// Usage: node run-node-physics.mjs <love-physics.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-physics.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-physics.wasm');

const ok = await runReactorNode(bytes, driveWitness, bootSrc, {});
process.exit(ok ? 0 : 1);
