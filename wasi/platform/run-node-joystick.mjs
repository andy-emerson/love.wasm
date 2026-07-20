// Node leg of the step-6.5 joystick/gamepad witness: instantiate the reactor (the
// LÖVE core + real love.joystick/gamepad over the 6.4 love.event stack) under
// node's WASI — the cross-check against the hand-rolled browser shim — with the
// love_gamepad host (the scripted Gamepad-API frames) bound, plus an EMPTY
// love_input host (the 6.4 event backend is linked and imports love_input, but the
// joystick witness must see no injected DOM events) and the love_fs host
// (love.mouse/image link filesystem, though this witness reads no file).
// Usage: node run-node-joystick.mjs <love-joystick.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeGamepadHost, makeEmptyInputHost } from '../host/gamepad-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-joystick.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-joystick.wasm');

const gamepad = makeGamepadHost();
const input = makeEmptyInputHost();
const fs = makeFsHost();
const ok = await runReactorNode(bytes, driveWitness, bootSrc, {
  extraImports: { love_gamepad: gamepad.imports, love_input: input.imports, love_fs: fs.imports },
  onInstance: (instance) => {
    gamepad.bind(instance.exports.memory);
    input.bind(instance.exports.memory);
    fs.bind(instance.exports.memory);
  },
});
process.exit(ok ? 0 : 1);
