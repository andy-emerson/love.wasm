// Browser leg of the step-6.5 joystick/gamepad witness: the LÖVE core + real
// love.joystick/gamepad (over the 6.4 love.event stack) driven in real Chromium
// (frames on requestAnimationFrame), via the shared harness
// (wasi/host/witness-harness.mjs), the shared WASI shim, the love_gamepad host
// (the scripted Gamepad-API frames), an EMPTY love_input host (the 6.4 event
// backend is linked and imports love_input, but the joystick witness must see no
// injected DOM events), and the shared love_fs host. No browser APIs are touched
// by the hosts — pure linear-memory copies — so a blank page is enough (no
// WebGL2, like the 6.4 leg).
// Usage: node run-browser-joystick.mjs <love-joystick.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveWitness } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeGamepadHost, makeEmptyInputHost } from '../host/gamepad-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-joystick.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-joystick.wasm').toString('base64');

const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: bootSrc,
  driverSrc: driveWitness.toString(), shimSrc: makeWasiShim.toString(),
  gamepadHostSrc: makeGamepadHost.toString(),
  inputHostSrc: makeEmptyInputHost.toString(),
  fsHostSrc: makeFsHost.toString(),
  withNow: false,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
