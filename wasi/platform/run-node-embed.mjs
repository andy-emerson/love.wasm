// Node leg of the step-6.7 embedding-contract witness: instantiate the reactor
// (the LÖVE core + real love.filesystem read+write + the pump reload primitive)
// under node's WASI — an independent, complete WASI host, the cross-check
// against the hand-rolled browser shim — with the love_fs host (read-only
// project + separate writable save namespace) bound, and run the shared
// transcript. After the run, assert the write path never mutated the project
// map (the save namespace holds the writes, the project bytes are untouched).
// Usage: node run-node-embed.mjs <love-embed.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-embed.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-embed.wasm');

const fs = makeFsHost();
const projectMod = new TextDecoder().decode(fs.files['mod.lua']);
const ok = await runReactorNode(bytes, driveWitness, bootSrc, {
  extraImports: { love_fs: fs.imports },
  onInstance: (instance) => fs.bind(instance.exports.memory),
});

// Host-side corroboration: the witness proved namespace separation by transcript
// (write -> shadow -> remove -> pristine); confirm it from the host maps too —
// the project mod.lua/greeting.txt are byte-unchanged, and the edited mod.lua
// (v=2) lives only in the writable save namespace.
const stillV1 = new TextDecoder().decode(fs.files['mod.lua']) === projectMod &&
  projectMod.indexOf('v=1') !== -1;
const savedV2 = fs.saves['mod.lua'] && new TextDecoder().decode(fs.saves['mod.lua']).indexOf('v=2') !== -1;
const projectClean = new TextDecoder().decode(fs.files['greeting.txt']) === 'project data';
console.log(`host check: project mod.lua unchanged (v=1) = ${stillV1}`);
console.log(`host check: edited mod.lua (v=2) is in the save namespace = ${!!savedV2}`);
console.log(`host check: project greeting.txt pristine = ${projectClean}`);

process.exit(ok && stillV1 && savedV2 && projectClean ? 0 : 1);
