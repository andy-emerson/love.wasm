// Node leg of the love.shim witness on the LOVE + DATA + MATH + FILESYSTEM +
// AUDIO artifact — the build that reaches love.audio.getSourceCount, renamed to
// getActiveSourceCount in 12. It also re-covers the love.math and filesystem
// tiers, so this leg overlaps the fs one deliberately rather than exactly.
// Usage: node run-node-audio.mjs <love-audio.wasm>
import { readFileSync } from 'node:fs';
import { driveWitness } from '../platform/driver.mjs';
import { makeAudioHost } from '../host/audio-host.mjs';
import { makeFsHost } from '../host/fs-host.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';
import { shimBootSrc } from './boot-src.mjs';

const bytes = readFileSync(process.argv[2] ?? 'love-audio.wasm');
const audio = makeAudioHost();
const fs = makeFsHost();
const ok = await runReactorNode(bytes, driveWitness, shimBootSrc(), {
  extraImports: { love_audio: audio.imports, love_fs: fs.imports },
  onInstance: (inst) => { audio.bind(inst.exports.memory); fs.bind(inst.exports.memory); },
});
process.exit(ok ? 0 : 1);
