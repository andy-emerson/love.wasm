// Browser leg of the step-5 audio witness: the LÖVE core with love.audio booting
// in real Chromium (frames on requestAnimationFrame), the love_audio host
// capturing each Source's PCM, and — after the run — that PCM played through a
// real OfflineAudioContext so the test tone is recovered from WebAudio's own
// rendered output (proving WebAudio resamples + the tone survives, not just that
// the seam carried it). Usage: node run-browser.mjs <love-audio.wasm>
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveAudio } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeAudioHost } from '../host/audio-host.mjs';
import { runInChromium, reactorPageFn } from '../host/witness-harness.mjs';

const TONE_HZ = 440;
const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-audio.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-audio.wasm').toString('base64');

const result = await runInChromium(reactorPageFn, {
  b64: wasmB64, boot: bootSrc,
  driverSrc: driveAudio.toString(), shimSrc: makeWasiShim.toString(),
  audioHostSrc: makeAudioHost.toString(), toneHz: TONE_HZ,
  withNow: false,
});

console.log('--- browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');

let toneOk = true;
if (result.audioSources > 0) {
  toneOk = result.audioTone > 8;
  console.log(`WebAudio readback: ${result.audioSources} source(s), ${TONE_HZ} Hz ratio ${result.audioTone?.toFixed?.(0)} -> ${toneOk ? 'PASS' : 'FAIL'}`);
}

process.exit(result.ok && toneOk ? 0 : 1);
