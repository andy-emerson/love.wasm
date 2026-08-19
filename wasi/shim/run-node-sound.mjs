// Node leg of the love.shim witness on the LOVE + DATA + SOUND artifact — the
// build that reaches SoundData:getChannels, renamed to getChannelCount in 12.
// Usage: node run-node-sound.mjs <love-sound.wasm>
import { readFileSync } from 'node:fs';
import { driveWitness } from '../platform/driver.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';
import { shimBootSrc } from './boot-src.mjs';

const bytes = readFileSync(process.argv[2] ?? 'love-sound.wasm');
const ok = await runReactorNode(bytes, driveWitness, shimBootSrc(), {});
process.exit(ok ? 0 : 1);
