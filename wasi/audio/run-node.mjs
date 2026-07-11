// Node leg of the step-5 audio witness: instantiate the reactor under node's
// WASI with the love_audio host (wasi/host/audio-host.mjs) providing the audio
// import surface, run the shared transcript, then recover the test tone from the
// PCM tapped at the seam. Usage: node run-node.mjs <love-audio.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveAudio } from './driver.mjs';
import { runReactorNode } from '../host/witness-harness.mjs';
import { makeAudioHost } from '../host/audio-host.mjs';

const TONE_HZ = 440;
const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-audio.lua'), 'utf8');
const bytes = readFileSync(process.argv[2] ?? 'love-audio.wasm');

const audio = makeAudioHost();
const ok = await runReactorNode(bytes, driveAudio, bootSrc, {
  extraImports: { love_audio: audio.imports },
  onInstance: (inst) => audio.bind(inst.exports.memory),
});

// A backend that routes PCM to the seam (webaudio) created Sources; recover the
// tone from the tapped PCM. A backend that doesn't (null) created none — then
// the Lua verdict stands alone.
let toneOk = true;
const list = audio.sources();
if (list.length) {
  const ratio = audio.rawToneRatio(TONE_HZ);
  toneOk = ratio > 8;
  const s = list[0];
  console.log(`seam tap: ${list.length} source(s), ${s.pcm.length} samples @ ${s.rate} Hz, played=${s.played}, ${TONE_HZ} Hz ratio ${ratio.toFixed(0)} -> ${toneOk ? 'PASS' : 'FAIL'}`);
}

process.exit(ok && toneOk ? 0 : 1);
