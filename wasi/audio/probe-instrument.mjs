// Step-5 sub-step 0 — "witness the witness": prove the AUDIO INSTRUMENT works
// in *our* exact Chromium before any WebAudio backend is built on top of it.
// love-wasi is tested without ears — we capture PCM and analyse it numerically.
// This probe validates the two browser-side mechanisms that make that possible:
//
//   A. OfflineAudioContext readback — render a known 440 Hz tone to a buffer
//      (no device, no real-time playback) and recover its frequency. This is
//      how step-5 PLAYBACK is witnessed: drive the graph, read the samples that
//      *would* have played, assert on them.
//   B. Fake-device capture — Chrome's --use-file-for-fake-audio-capture feeds a
//      known WAV through the real getUserMedia -> AudioWorklet path (permission
//      auto-granted, no prompt, no hardware). This is how the MIC seam is
//      witnessed end-to-end: known signal in, assert the captured/resampled
//      Float32 frames carry it. Also exercises the Blob-URL inline worklet and
//      the port.postMessage transfer — both load-bearing for the real design.
//
// The node-side seam tap (collect bytes at the import boundary) is trivially
// JS and needs no probe; the risky, browser-specific parts are A and B.
//
//   node wasi/audio/probe-instrument.mjs
//
// Exit 0 = instrument works (both mechanisms recovered the tone). Exit 1 = a
// mechanism failed in our harness — we learn it now, cheaply, not after
// building the backend.
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { existsSync } from 'node:fs';

const TONE_HZ = 440;
const WAV_RATE = 48000;

// --- a known-signal 16-bit mono WAV (2 s of 440 Hz), as a data buffer Chrome
//     can play as the fake microphone via --use-file-for-fake-audio-capture ---
function makeSineWav(freq, rate, seconds) {
  const n = rate * seconds;
  const bytesPerSample = 2;
  const dataLen = n * bytesPerSample;
  const buf = Buffer.alloc(44 + dataLen);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + dataLen, 4); buf.write('WAVE', 8);
  buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20);   // PCM
  buf.writeUInt16LE(1, 22);            // mono
  buf.writeUInt32LE(rate, 24);
  buf.writeUInt32LE(rate * bytesPerSample, 28);
  buf.writeUInt16LE(bytesPerSample, 32); buf.writeUInt16LE(16, 34);
  buf.write('data', 36); buf.writeUInt32LE(dataLen, 40);
  for (let i = 0; i < n; i++) {
    const s = Math.sin(2 * Math.PI * freq * i / rate);
    buf.writeInt16LE(Math.max(-1, Math.min(1, s)) * 32767, 44 + i * bytesPerSample);
  }
  return buf;
}

function resolvePlaywright() {
  for (const base of [process.cwd(), '/root/.love-wasi/npm', process.env.HOME || '/root']) {
    try {
      const require = createRequire(base + '/noop.js');
      return require('playwright-core');
    } catch { /* try next */ }
  }
  throw new Error('playwright-core not resolvable');
}

// This function is SERIALIZED into the page (self-contained: no outer refs).
// Runs both instrument tests and returns measured numbers. Uses a Goertzel
// filter to score energy at the target frequency vs an off-target control.
async function pageProbe({ toneHz, wavRate }) {
  // Goertzel magnitude at `freq` over `samples` taken at `rate`.
  const goertzel = (samples, rate, freq) => {
    const w = 2 * Math.PI * freq / rate;
    const c = 2 * Math.cos(w);
    let s0 = 0, s1 = 0, s2 = 0;
    for (let i = 0; i < samples.length; i++) { s0 = samples[i] + c * s1 - s2; s2 = s1; s1 = s0; }
    return Math.sqrt(s1 * s1 + s2 * s2 - c * s1 * s2) / samples.length;
  };
  // ratio of on-target energy to an off-target control (~2.7x the tone) — a
  // clean tone scores this well above 1; noise/silence scores ~1 or NaN.
  const toneRatio = (samples, rate) =>
    goertzel(samples, rate, toneHz) / (goertzel(samples, rate, toneHz * 2.71 + 37) + 1e-9);

  const result = { A: null, B: null };

  // --- A. OfflineAudioContext readback ---
  try {
    const off = new OfflineAudioContext(1, wavRate, wavRate);
    const osc = off.createOscillator();
    osc.frequency.value = toneHz;
    osc.connect(off.destination);
    osc.start();
    const rendered = await off.startRendering();
    const ch = rendered.getChannelData(0);
    result.A = { rate: rendered.sampleRate, samples: ch.length, ratio: toneRatio(ch, rendered.sampleRate) };
  } catch (e) { result.A = { error: String(e) }; }

  // --- B. Fake-device capture through getUserMedia -> AudioWorklet ---
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const ctx = new AudioContext();
    if (ctx.state === 'suspended') await ctx.resume();
    // inline worklet via Blob URL (the "one artifact" constraint in miniature)
    const workletSrc = `
      class Cap extends AudioWorkletProcessor {
        process(inputs) {
          const ch = inputs[0][0];
          if (ch && ch.length) this.port.postMessage(ch.slice(0));
          return true;
        }
      }
      registerProcessor('cap', Cap);`;
    const url = URL.createObjectURL(new Blob([workletSrc], { type: 'application/javascript' }));
    await ctx.audioWorklet.addModule(url);
    const src = ctx.createMediaStreamSource(stream);
    const node = new AudioWorkletNode(ctx, 'cap');
    const frames = [];
    node.port.onmessage = (e) => frames.push(e.data);
    // capture-only graph: route worklet -> silent gain -> destination so the
    // node is actually pulled, without audible output.
    const mute = ctx.createGain(); mute.gain.value = 0;
    src.connect(node); node.connect(mute); mute.connect(ctx.destination);
    await new Promise(r => setTimeout(r, 600));
    node.port.onmessage = null;
    stream.getTracks().forEach(t => t.stop());
    const total = frames.reduce((a, f) => a + f.length, 0);
    const pcm = new Float32Array(total);
    let o = 0; for (const f of frames) { pcm.set(f, o); o += f.length; }
    result.B = {
      rate: ctx.sampleRate, quantum: frames[0] ? frames[0].length : 0,
      frames: frames.length, samples: total,
      ratio: total ? toneRatio(pcm, ctx.sampleRate) : 0,
    };
    await ctx.close();
  } catch (e) { result.B = { error: String(e) }; }

  return result;
}

async function main() {
  const wav = makeSineWav(TONE_HZ, WAV_RATE, 2);
  const wavPath = (process.env.TMPDIR || '/tmp') + '/probe-mic-440.wav';
  const { writeFileSync } = await import('node:fs');
  writeFileSync(wavPath, wav);

  // localhost gives getUserMedia a secure context (about:blank does not).
  const server = createServer((_req, res) => {
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end('<!doctype html><meta charset=utf8><title>audio instrument probe</title>');
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
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
  let res;
  try {
    const page = await browser.newPage();
    await page.goto(`http://localhost:${port}/`);
    res = await page.evaluate(pageProbe, { toneHz: TONE_HZ, wavRate: WAV_RATE });
  } finally {
    await browser.close();
    server.close();
  }

  console.log('== audio instrument probe ==');
  console.log('A (OfflineAudioContext readback):', JSON.stringify(res.A));
  console.log('B (fake-device getUserMedia -> AudioWorklet):', JSON.stringify(res.B));

  const aOk = res.A && !res.A.error && res.A.ratio > 8 && res.A.samples > 1000;
  const bOk = res.B && !res.B.error && res.B.ratio > 8 && res.B.frames > 0;
  console.log(`A ${aOk ? 'PASS' : 'FAIL'} — recovered ${TONE_HZ} Hz from rendered buffer`);
  console.log(`B ${bOk ? 'PASS' : 'FAIL'} — recovered ${TONE_HZ} Hz from captured mic frames (native rate ${res.B?.rate}, quantum ${res.B?.quantum})`);

  if (aOk && bOk) {
    console.log('INSTRUMENT: PASS — playback readback and mic capture are both measurable headless');
    process.exit(0);
  }
  console.log('INSTRUMENT: FAIL');
  process.exit(1);
}

main().catch(e => { console.error('probe error:', e); process.exit(1); });
