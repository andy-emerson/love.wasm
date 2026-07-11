// Real-capture leg of the step-5 mic witness: marries the actual browser capture
// path (getUserMedia -> AudioWorklet, Chromium fake device) to love.audio's
// RecordingDevice, driven through the reactor. Unlike run-browser.mjs (which
// uses the deterministic mock host), this serves a secure-context page and
// launches Chromium with a fake audio device, so the async permission +
// capture edges are exercised for real. Usage: node run-browser-mic.mjs <wasm>
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createServer } from 'node:http';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { driveAudio } from './driver.mjs';
import { makeWasiShim } from '../host/wasi-shim.mjs';
import { makeAudioHost } from '../host/audio-host.mjs';
import { makeBrowserMicHost } from '../host/mic-host-browser.mjs';
import { reactorPageFn } from '../host/witness-harness.mjs';

const TONE_HZ = 440, WAV_RATE = 48000;

// A known 440 Hz 16-bit mono WAV — Chromium plays it as the fake microphone.
function makeSineWav(freq, rate, seconds) {
  const n = rate * seconds, bps = 2, dataLen = n * bps;
  const buf = Buffer.alloc(44 + dataLen);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + dataLen, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20);
  buf.writeUInt16LE(1, 22); buf.writeUInt32LE(rate, 24);
  buf.writeUInt32LE(rate * bps, 28); buf.writeUInt16LE(bps, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(dataLen, 40);
  for (let i = 0; i < n; i++)
    buf.writeInt16LE(Math.max(-1, Math.min(1, Math.sin(2 * Math.PI * freq * i / rate))) * 32767, 44 + i * bps);
  return buf;
}

function resolvePlaywright() {
  for (const base of [process.cwd(), '/root/.love-wasi/npm', process.env.HOME || '/root']) {
    try { return createRequire(base + '/noop.js')('playwright-core'); } catch { /* next */ }
  }
  throw new Error('playwright-core not resolvable');
}

const here = dirname(fileURLToPath(import.meta.url));
const bootSrc = readFileSync(join(here, 'witness-mic-real.lua'), 'utf8');
const wasmB64 = readFileSync(process.argv[2] ?? 'love-audio.wasm').toString('base64');

const wavPath = (process.env.TMPDIR || '/tmp') + '/witness-mic-440.wav';
writeFileSync(wavPath, makeSineWav(TONE_HZ, WAV_RATE, 2));

// localhost gives getUserMedia a secure context (about:blank does not).
const server = createServer((_q, res) => {
  res.writeHead(200, { 'content-type': 'text/html' });
  res.end('<!doctype html><meta charset=utf8><title>real mic witness</title>');
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

const { chromium } = resolvePlaywright();
const executablePath = process.env.CHROMIUM && existsSync(process.env.CHROMIUM) ? process.env.CHROMIUM : undefined;
const browser = await chromium.launch({
  ...(executablePath ? { executablePath } : {}),
  chromiumSandbox: false,
  args: [
    '--use-fake-device-for-media-stream',
    '--use-fake-ui-for-media-stream',
    `--use-file-for-fake-audio-capture=${wavPath}`,
    '--autoplay-policy=no-user-gesture-required',
  ],
});

let result;
try {
  const page = await browser.newPage();
  await page.goto(`http://localhost:${port}/`);
  result = await page.evaluate(reactorPageFn, {
    b64: wasmB64, boot: bootSrc,
    driverSrc: driveAudio.toString(), shimSrc: makeWasiShim.toString(),
    audioHostSrc: makeAudioHost.toString(), micHostSrc: makeBrowserMicHost.toString(),
    toneHz: TONE_HZ, withNow: false,
  });
} finally {
  await browser.close();
  server.close();
}

console.log('--- real-mic browser transcript ---');
for (const line of result.lines) console.log(line);
if (result.stdout) console.log('--- wasm stdout ---\n' + result.stdout.trimEnd());
if (result.error) console.log('--- error: ' + result.error + ' ---');
process.exit(result.ok ? 0 : 1);
