// Node leg of the step-6.4 input witness: instantiate the reactor (the LÖVE core
// + real love.event/keyboard/mouse) under node's WASI — an independent, complete
// WASI host, the cross-check against the hand-rolled browser shim — with the
// love_input host (the pre-seeded DOM-event queue) bound, and run the shared
// transcript. love.filesystem links (love.mouse/image depend on it) so the
// love_fs host is bound too, though this witness never reads a file.
// Usage: node run-node-input.mjs <love-input.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeInputHost } from '../host/input-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-input.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-input.wasm');

const input = makeInputHost();
const fs = makeFsHost();
const ok = await runReactorNode(bytes, driveWitness, bootSrc, {
  extraImports: { love_input: input.imports, love_fs: fs.imports },
  onInstance: (instance) => {
    input.bind(instance.exports.memory);
    fs.bind(instance.exports.memory);
  },
});
process.exit(ok ? 0 : 1);
