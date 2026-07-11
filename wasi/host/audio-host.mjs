// The host side of the love-wasi audio seam: implements the `love_audio` import
// surface the webaudio backend calls (src/modules/audio/webaudio/Imports.h).
// This is the witness/mock host — it captures the PCM handed to each Source so
// the tone can be recovered at the seam. A real browser host implements the same
// finite surface by driving WebAudio nodes instead (readme.md: everything the
// host supplies as imports, the OS's role for desktop LÖVE).
//
// Self-contained by contract, exactly like wasi-shim.mjs: no imports, no
// outer-scope references, so makeAudioHost.toString() can be stringified into a
// Playwright page and rebuilt with `new Function('return ' + src)()`. Runs
// unchanged in node too.
//
// Usage mirrors the WASI shim:
//   const audio = makeAudioHost();
//   ... instantiate with { love_audio: audio.imports } ...
//   audio.bind(instance.exports.memory);   // before any import fires
//   audio.sources()                        // captured PCM per Source, post-run
export function makeAudioHost() {
  let memory;
  const CONTEXT_RATE = 48000;         // the mock host's device rate
  const srcs = new Map();             // handle -> { rate, channels, chunks:[Float32Array], played }
  let next = 0;

  // Single-frequency energy (Goertzel), used to recover a test tone.
  const goertzel = (samples, rate, freq) => {
    const w = 2 * Math.PI * freq / rate, c = 2 * Math.cos(w);
    let s1 = 0, s2 = 0, s0 = 0;
    for (let i = 0; i < samples.length; i++) { s0 = samples[i] + c * s1 - s2; s2 = s1; s1 = s0; }
    return Math.sqrt(s1 * s1 + s2 * s2 - c * s1 * s2) / (samples.length || 1);
  };

  const imports = {
    source_create(sampleRate, channels) {
      const h = next++;
      srcs.set(h, { rate: sampleRate || CONTEXT_RATE, channels: channels || 1, chunks: [], played: false });
      return h;
    },
    // Read channel 0 of interleaved int PCM at `ptr` and store it as Float32 —
    // the trivial int->float cast a real host also does before WebAudio.
    source_queue(handle, ptr, frames, sampleRate, bitDepth, channels) {
      const s = srcs.get(handle);
      if (!s || !memory) return;
      const dv = new DataView(memory.buffer);
      const frameBytes = (channels || 1) * (bitDepth / 8);
      const out = new Float32Array(frames);
      for (let i = 0; i < frames; i++) {
        const off = ptr + i * frameBytes;               // channel 0
        out[i] = bitDepth === 16
          ? dv.getInt16(off, true) / 32768
          : (dv.getUint8(off) - 128) / 128;             // 8-bit PCM is unsigned
      }
      s.chunks.push(out);
    },
    source_play(handle) { const s = srcs.get(handle); if (s) s.played = true; return 1; },
    source_stop(handle) { const s = srcs.get(handle); if (s) s.played = false; },
    source_gain(_handle, _gain) { /* recorded by a real host; unused by the tap */ },
    context_rate() { return CONTEXT_RATE; },
  };

  const concat = (chunks) => {
    const total = chunks.reduce((a, f) => a + f.length, 0);
    const pcm = new Float32Array(total);
    let o = 0; for (const f of chunks) { pcm.set(f, o); o += f.length; }
    return pcm;
  };

  return {
    imports,
    goertzel,
    bind(m) { memory = m; },
    // Captured PCM per Source (channel 0), for post-run analysis.
    sources() {
      return [...srcs.entries()].map(([handle, s]) =>
        ({ handle, rate: s.rate, channels: s.channels, played: s.played, pcm: concat(s.chunks) }));
    },
    // Node convenience: best on-target vs off-target ratio over the raw captured
    // PCM (the seam tap), at each Source's own rate.
    rawToneRatio(freq) {
      let best = 0;
      for (const s of this.sources()) {
        if (!s.pcm.length) continue;
        const on = goertzel(s.pcm, s.rate, freq);
        const off = goertzel(s.pcm, s.rate, freq * 2.71 + 37);
        best = Math.max(best, on / (off + 1e-9));
      }
      return best;
    },
  };
}
