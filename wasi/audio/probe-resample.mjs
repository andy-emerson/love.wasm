// Step-5 resampling-delegation probe: can WebAudio do the rate conversion for
// us — for BOTH playback and mic capture — so love-wasi needs no resampler of
// its own? Decides between "delegate resampling everywhere" (no custom DSP) and
// "vendor one proven resampler". Chromium only here (the pre-provisioned
// browser); Firefox/WebKit remain claims until they can be driven too.
//
//   node wasi/audio/probe-resample.mjs
//
// A. Playback: an AudioBuffer at 24000 Hz played in a 48000 Hz context — does
//    the graph resample it and preserve the tone? (The playback delegation
//    point: AudioBufferSourceNode resamples buffer.sampleRate -> ctx rate.)
// B. Capture: open the capture AudioContext at 16000 Hz while the fake mic
//    feeds 48000 Hz — does Chromium honor the rate, does createMediaStreamSource
//    survive the mismatch, and do the captured frames arrive at 16000 Hz with
//    the tone intact? (The mic delegation point — the fragile one.)
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { existsSync, writeFileSync } from 'node:fs';

const TONE_HZ = 440;
const WAV_RATE = 48000;

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

async function pageProbe({ toneHz }) {
  const goertzel = (samples, rate, freq) => {
    const w = 2 * Math.PI * freq / rate, c = 2 * Math.cos(w);
    let s1 = 0, s2 = 0, s0 = 0;
    for (let i = 0; i < samples.length; i++) { s0 = samples[i] + c * s1 - s2; s2 = s1; s1 = s0; }
    return Math.sqrt(s1 * s1 + s2 * s2 - c * s1 * s2) / samples.length;
  };
  const toneRatio = (samples, rate) =>
    goertzel(samples, rate, toneHz) / (goertzel(samples, rate, toneHz * 2.71 + 37) + 1e-9);

  const out = { playback: null, capture: null };

  // --- A. Playback resample delegation: 24000 Hz buffer -> 48000 Hz context ---
  try {
    const srcRate = 24000, ctxRate = 48000, secs = 0.5;
    const off = new OfflineAudioContext(1, Math.floor(ctxRate * secs), ctxRate);
    const buf = off.createBuffer(1, Math.floor(srcRate * secs), srcRate);
    const ch = buf.getChannelData(0);
    for (let i = 0; i < ch.length; i++) ch[i] = Math.sin(2 * Math.PI * toneHz * i / srcRate);
    const node = off.createBufferSource(); node.buffer = buf; node.connect(off.destination); node.start();
    const rendered = await off.startRendering();
    const o = rendered.getChannelData(0);
    out.playback = { bufferRate: srcRate, ctxRate: rendered.sampleRate, ratio: toneRatio(o, rendered.sampleRate) };
  } catch (e) { out.playback = { error: String(e) }; }

  // --- B. Capture resample delegation: request a 16000 Hz capture context ---
  try {
    const requested = 16000;
    let ctx, ctxErr = null;
    try { ctx = new AudioContext({ sampleRate: requested }); }
    catch (e) { ctxErr = String(e); ctx = new AudioContext(); }
    if (ctx.state === 'suspended') await ctx.resume();

    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    let srcErr = null, src = null;
    try { src = ctx.createMediaStreamSource(stream); }
    catch (e) { srcErr = String(e); }

    let result = { requested, ctxRate: ctx.sampleRate, ctxHonored: ctx.sampleRate === requested, ctxErr, srcErr };
    if (src) {
      const workletSrc = `
        class Cap extends AudioWorkletProcessor {
          process(inputs){ const ch=inputs[0][0]; if(ch&&ch.length) this.port.postMessage(ch.slice(0)); return true; }
        }
        registerProcessor('cap', Cap);`;
      const url = URL.createObjectURL(new Blob([workletSrc], { type: 'application/javascript' }));
      await ctx.audioWorklet.addModule(url);
      const node = new AudioWorkletNode(ctx, 'cap');
      const frames = [];
      node.port.onmessage = (e) => frames.push(e.data);
      const mute = ctx.createGain(); mute.gain.value = 0;
      src.connect(node); node.connect(mute); mute.connect(ctx.destination);
      await new Promise(r => setTimeout(r, 600));
      node.port.onmessage = null; stream.getTracks().forEach(t => t.stop());
      const total = frames.reduce((a, f) => a + f.length, 0);
      const pcm = new Float32Array(total); let k = 0; for (const f of frames) { pcm.set(f, k); k += f.length; }
      result.quantum = frames[0] ? frames[0].length : 0;
      result.frames = frames.length; result.samples = total;
      // captured samples are at ctx.sampleRate; recover the tone at that rate
      result.ratio = total ? toneRatio(pcm, ctx.sampleRate) : 0;
    }
    await ctx.close();
    out.capture = result;
  } catch (e) { out.capture = { error: String(e) }; }

  return out;
}

async function main() {
  const wavPath = (process.env.TMPDIR || '/tmp') + '/probe-resample-440.wav';
  writeFileSync(wavPath, makeSineWav(TONE_HZ, WAV_RATE, 2));

  const server = createServer((_q, res) => { res.writeHead(200, { 'content-type': 'text/html' }); res.end('<!doctype html><meta charset=utf8><title>resample probe</title>'); });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;

  const { chromium } = resolvePlaywright();
  const executablePath = process.env.CHROMIUM && existsSync(process.env.CHROMIUM) ? process.env.CHROMIUM : undefined;
  const browser = await chromium.launch({
    ...(executablePath ? { executablePath } : {}),
    chromiumSandbox: false,
    args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
      `--use-file-for-fake-audio-capture=${wavPath}`, '--autoplay-policy=no-user-gesture-required'],
  });
  let res;
  try {
    const page = await browser.newPage();
    await page.goto(`http://localhost:${port}/`);
    res = await page.evaluate(pageProbe, { toneHz: TONE_HZ });
  } finally { await browser.close(); server.close(); }

  console.log('== resampling-delegation probe (Chromium only) ==');
  console.log('A playback (24000 Hz buffer -> 48000 Hz context):', JSON.stringify(res.playback));
  console.log('B capture  (request 16000 Hz capture context):    ', JSON.stringify(res.capture));

  const aOk = res.playback && !res.playback.error && res.playback.ratio > 8;
  const bHonored = res.capture && !res.capture.error && res.capture.ctxHonored && !res.capture.srcErr;
  const bTone = res.capture && res.capture.ratio > 8;
  console.log(`A playback resample delegated: ${aOk ? 'YES' : 'NO'} (tone ratio ${res.playback?.ratio?.toFixed?.(0)})`);
  console.log(`B capture  context honored at 16000: ${bHonored ? 'YES' : 'NO'} (got ${res.capture?.ctxRate}); tone survived: ${bTone ? 'YES' : 'NO'} (ratio ${res.capture?.ratio?.toFixed?.(0)})`);
  process.exit(0);
}
main().catch(e => { console.error('probe error:', e); process.exit(1); });
