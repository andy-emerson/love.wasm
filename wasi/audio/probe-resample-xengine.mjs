// Issue #33: drive the step-5 resampling-delegation probe under Chromium (V8),
// Firefox (SpiderMonkey) and WebKit (JavaScriptCore) — not Chromium alone — to
// settle whether WebAudio's rate conversion is honored on every engine, or which
// ones fall back to report-actual-rate. This is a PROBE, not a pass/fail witness:
// it records per-engine findings and always exits 0. The step-5 backend is
// already correct on all three (a runtime capability check picks delegate-or-
// report-actual at mic start); what this measures is only *how faithful* the mic
// rate is per engine.
//
//   node wasi/audio/probe-resample-xengine.mjs            # all installed engines
//   PROBE_ENGINES=chromium,firefox node …xengine.mjs      # a subset
//
// Two delegation points, per engine:
//   A. Playback — a 24000 Hz AudioBuffer in a 48000 Hz OfflineAudioContext. No
//      mic, no fake device: works everywhere, the high-confidence baseline.
//   B. Capture  — request a 16000 Hz AudioContext against a fake mic; does the
//      engine honor the rate, does createMediaStreamSource survive the mismatch,
//      and does a tone survive? The tone SOURCE differs per engine (Chromium
//      plays our WAV at 440 Hz; Firefox's fake device synthesises its own tone;
//      WebKit headless typically has no fake mic at all), so capture detects the
//      DOMINANT frequency by a coarse sweep rather than assuming 440.
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { existsSync, writeFileSync } from 'node:fs';

const TONE_HZ = 440, WAV_RATE = 48000;

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

// Per-engine launch config. Chromium: fake device fed our WAV file. Firefox:
// fake device via prefs (synthesises its own tone). WebKit: no documented fake
// mic — attempt bare and let the probe record what getUserMedia does.
function launchOpts(engine, wavPath, executablePath) {
  const base = executablePath ? { executablePath } : {};
  if (engine === 'chromium') return { ...base, chromiumSandbox: false,
    args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream',
      `--use-file-for-fake-audio-capture=${wavPath}`, '--autoplay-policy=no-user-gesture-required'] };
  if (engine === 'firefox') return { ...base, firefoxUserPrefs: {
    'media.navigator.streams.fake': true, 'media.navigator.permission.disabled': true,
    'media.autoplay.default': 0, 'media.autoplay.blocking_policy': 0 } };
  return { ...base }; // webkit
}

async function pageProbe() {
  const goertzel = (s, rate, freq) => {
    const w = 2 * Math.PI * freq / rate, c = 2 * Math.cos(w);
    let s1 = 0, s2 = 0, s0 = 0;
    for (let i = 0; i < s.length; i++) { s0 = s[i] + c * s1 - s2; s2 = s1; s1 = s0; }
    return Math.sqrt(s1 * s1 + s2 * s2 - c * s1 * s2) / s.length;
  };
  // Dominant tone: peak magnitude over a coarse sweep, and its ratio to the median
  // (tonal if the peak stands well above the noise floor). Engine-agnostic.
  const dominant = (pcm, rate) => {
    if (!pcm.length) return { hz: 0, ratio: 0 };
    const cand = [220, 330, 440, 660, 880, 1000, 1320, 1760];
    const mags = cand.map(f => goertzel(pcm, rate, f));
    let bi = 0; for (let i = 1; i < mags.length; i++) if (mags[i] > mags[bi]) bi = i;
    const sorted = [...mags].sort((a, b) => a - b);
    const median = sorted[Math.floor(sorted.length / 2)] + 1e-9;
    return { hz: cand[bi], ratio: mags[bi] / median };
  };

  const out = { playback: null, capture: null };

  // A. Playback (no mic; every engine)
  try {
    const srcRate = 24000, ctxRate = 48000, secs = 0.5;
    const off = new OfflineAudioContext(1, Math.floor(ctxRate * secs), ctxRate);
    const buf = off.createBuffer(1, Math.floor(srcRate * secs), srcRate);
    const ch = buf.getChannelData(0);
    for (let i = 0; i < ch.length; i++) ch[i] = Math.sin(2 * Math.PI * 440 * i / srcRate);
    const node = off.createBufferSource(); node.buffer = buf; node.connect(off.destination); node.start();
    const rendered = await off.startRendering();
    out.playback = { bufferRate: srcRate, ctxRate: rendered.sampleRate, tone: dominant(rendered.getChannelData(0), rendered.sampleRate) };
  } catch (e) { out.playback = { error: String(e) }; }

  // B. Capture (fake mic; the fragile, per-engine point). Wrapped in an IN-PAGE
  // hard cap: a getUserMedia / audioWorklet.addModule that never settles (seen on
  // headless Firefox) would otherwise strand the whole evaluate and throw away
  // playback A too. On cap, record the engine as capture-timed-out — playback
  // still returns — instead of losing everything to the outer Node guard.
  try {
    const CAP_MS = 8000;
    const captureWork = (async () => {
      const requested = 16000;
      let ctx, ctxErr = null;
      try { ctx = new AudioContext({ sampleRate: requested }); }
      catch (e) { ctxErr = String(e); ctx = new AudioContext(); }
      if (ctx.state === 'suspended') { try { await ctx.resume(); } catch { /* ignore */ } }

      let stream = null, gumErr = null;
      try { stream = await navigator.mediaDevices.getUserMedia({ audio: true }); }
      catch (e) { gumErr = String(e); }

      const result = { requested, ctxRate: ctx.sampleRate, ctxHonored: ctx.sampleRate === requested, ctxErr, gumErr, srcErr: null };
      if (stream) {
        let src = null;
        try { src = ctx.createMediaStreamSource(stream); }
        catch (e) { result.srcErr = String(e); }
        if (src) {
          const workletSrc = `class Cap extends AudioWorkletProcessor{process(i){const c=i[0][0];if(c&&c.length)this.port.postMessage(c.slice(0));return true}}registerProcessor('cap',Cap)`;
          const url = URL.createObjectURL(new Blob([workletSrc], { type: 'application/javascript' }));
          await ctx.audioWorklet.addModule(url);
          const node = new AudioWorkletNode(ctx, 'cap');
          const frames = []; node.port.onmessage = (e) => frames.push(e.data);
          const mute = ctx.createGain(); mute.gain.value = 0;
          src.connect(node); node.connect(mute); mute.connect(ctx.destination);
          await new Promise(r => setTimeout(r, 600));
          node.port.onmessage = null; stream.getTracks().forEach(t => t.stop());
          const total = frames.reduce((a, f) => a + f.length, 0);
          const pcm = new Float32Array(total); let k = 0; for (const f of frames) { pcm.set(f, k); k += f.length; }
          result.samples = total; result.tone = dominant(pcm, ctx.sampleRate);
        }
      }
      try { await ctx.close(); } catch { /* ignore */ }
      return result;
    })();
    out.capture = await Promise.race([
      captureWork,
      new Promise((res) => setTimeout(() => res({ timedOut: CAP_MS }), CAP_MS)),
    ]);
  } catch (e) { out.capture = { error: String(e) }; }

  return out;
}

async function runEngine(engine, wavPath) {
  const pw = resolvePlaywright();
  const bt = pw[engine];
  if (!bt) return { engine, skipped: 'unknown engine' };
  // $CHROMIUM pins the provisioned Chromium when playwright-core's own expected
  // path is version-skewed (interactive sessions); it counts as installed.
  const chromiumOverride = engine === 'chromium' && process.env.CHROMIUM && existsSync(process.env.CHROMIUM);
  if (!chromiumOverride && !existsSync(bt.executablePath())) return { engine, skipped: 'not installed' };
  const executablePath = chromiumOverride ? process.env.CHROMIUM : undefined;

  const server = createServer((_q, res) => { res.writeHead(200, { 'content-type': 'text/html' }); res.end('<!doctype html><meta charset=utf8><title>xengine resample probe</title>'); });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  const port = server.address().port;

  let browser = null;
  try {
    browser = await bt.launch(launchOpts(engine, wavPath, executablePath));
    // No newContext({permissions:['microphone']}): Playwright validates it lazily
    // at newPage and WebKit rejects the string outright ("Unknown permission:
    // microphone"), which killed the whole WebKit leg. Each engine's launchOpts
    // already handles the grant (chromium --use-fake-ui; firefox permission.disabled
    // pref); WebKit has no fake mic, so its getUserMedia simply rejects and is
    // recorded as gumErr — a real finding, not a harness crash.
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto(`http://localhost:${port}/`);
    // page.evaluate has NO default timeout: a headless engine whose getUserMedia
    // or audioWorklet.addModule never settles (WebKit has no fake mic and may not
    // accept a blob-URL worklet) would hang the evaluate — and the CI job — until
    // GitHub's step ceiling. A probe must never do that, so cap it: on timeout,
    // record the engine as probe-timed-out and move on (the finally tears the
    // hung page down via browser.close()).
    let timer;
    const res = await Promise.race([
      page.evaluate(pageProbe),
      new Promise((_, rej) => { timer = setTimeout(() => rej(new Error('probe evaluate timed out (25s)')), 25000); }),
    ]).finally(() => clearTimeout(timer));
    return { engine, ...res };
  } catch (e) {
    return { engine, launchError: String(e) };
  } finally {
    if (browser) await browser.close();
    server.close();
  }
}

async function main() {
  const wavPath = (process.env.TMPDIR || '/tmp') + '/probe-resample-440.wav';
  writeFileSync(wavPath, makeSineWav(TONE_HZ, WAV_RATE, 2));
  const engines = (process.env.PROBE_ENGINES || 'chromium,firefox,webkit').split(',').map(s => s.trim()).filter(Boolean);

  console.log('== resampling-delegation probe — cross-engine (issue #33) ==');
  for (const engine of engines) {
    const r = await runEngine(engine, wavPath);
    if (r.skipped) { console.log(`\n[${engine}] SKIPPED (${r.skipped})`); continue; }
    if (r.launchError) { console.log(`\n[${engine}] LAUNCH ERROR: ${r.launchError}`); continue; }
    const p = r.playback || {}, c = r.capture || {};
    const pOk = p.tone && p.tone.ratio > 8;
    console.log(`\n[${engine}]`);
    console.log(`  A playback : ${JSON.stringify(p)}`);
    console.log(`    -> resample delegated: ${pOk ? 'YES' : 'NO'} (tone ~${p.tone?.hz}Hz, ratio ${p.tone?.ratio?.toFixed?.(0)})`);
    console.log(`  B capture  : ${JSON.stringify(c)}`);
    if (c.error) { console.log(`    -> capture ERROR: ${c.error}`); continue; }
    if (c.timedOut) { console.log(`    -> capture TIMED OUT after ${c.timedOut}ms (getUserMedia/addModule never settled on this headless engine)`); continue; }
    const honored = c.ctxHonored && !c.srcErr && !c.gumErr;
    const tonal = c.tone && c.tone.ratio > 8;
    console.log(`    -> ctx honored @16000: ${honored ? 'YES' : 'NO'} (got ${c.ctxRate}${c.gumErr ? '; getUserMedia: ' + c.gumErr : ''}${c.srcErr ? '; createMediaStreamSource: ' + c.srcErr : ''})`);
    console.log(`    -> capture tone survived: ${tonal ? 'YES' : 'NO'} (${c.samples || 0} samples, ~${c.tone?.hz}Hz, ratio ${c.tone?.ratio?.toFixed?.(0)})`);
  }
  console.log('\n(probe: records per-engine findings; the backend is correct on all three regardless — see wasi/audio/DESIGN.md and #33)');
  process.exit(0);
}
main().catch(e => { console.error('probe error:', e); process.exit(1); });
