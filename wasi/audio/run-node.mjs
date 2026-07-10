// Node leg of the step-5 audio witness: instantiate the reactor under node's
// WASI and run the shared transcript (via wasi/host/witness-harness.mjs).
// Usage: node run-node.mjs <love-audio.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveAudio } from './driver.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-audio.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-audio.wasm');

const ok = await runReactorNode(bytes, driveAudio, bootSrc);
process.exit(ok ? 0 : 1);
