// Node leg of the love.sound decoder witness: instantiate the reactor (LÖVE core
// + real love.sound decoders) under node's WASI and run the shared transcript.
// The witness decodes from a Data, so there are NO host imports to bind — the
// WASI shim is the whole host. The real Ogg asset is base64-injected into the
// witness source here (same bytes the browser leg injects), so both legs decode
// identical input. Usage: node run-node-sound.mjs <love-sound.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const oggB64 = readFileSync(join(root, 'testing/resources/clickmono.ogg')).toString('base64');
const bootSrc = readFileSync(join(here, 'witness-sound.lua'), 'utf8').replace('__OGG_B64__', oggB64);
const bytes = readFileSync(process.argv[2] ?? 'love-sound.wasm');

const ok = await runReactorNode(bytes, driveWitness, bootSrc, {});
process.exit(ok ? 0 : 1);
