// Node leg of the step-6.6a timer+system witness: instantiate the reactor (the
// LÖVE core + real love.timer + real love.system) under node's WASI — an
// independent, complete WASI host, the cross-check against the hand-rolled
// browser shim — with the love_system host bound, and run the shared transcript.
// Usage: node run-node-timer-system.mjs <love-timer-system.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeSystemHost } from '../host/system-host.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-timer-system.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-timer-system.wasm');

const system = makeSystemHost();
const ok = await runReactorNode(bytes, driveWitness, bootSrc, {
  extraImports: { love_system: system.imports },
  onInstance: (instance) => {
    system.bind(instance.exports.memory);
  },
});
process.exit(ok ? 0 : 1);
