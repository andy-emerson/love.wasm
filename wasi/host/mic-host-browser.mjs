// The REAL browser microphone host — backs the wa_mic_* import surface with an
// actual getUserMedia -> AudioWorklet capture graph, so the RecordingDevice seam
// is driven end-to-end through the reactor (not the deterministic mock in
// audio-host.mjs). Used only by the real-capture witness (wasi/audio/
// run-browser-mic.mjs), which serves a secure-context page and launches Chromium
// with a fake audio device.
//
// Permission is reflected at enumeration, matching LÖVE's contract (and this
// build's only Lua-visible recording surface, love.audio.getRecordingDevices):
// mic_device_count() returns 0 until getUserMedia has resolved a stream — i.e.
// empty until granted — and the first enumeration call kicks the request off.
//
// Rate is delegated: mic_start opens the AudioContext at the requested rate and
// returns ctx.sampleRate (the capability check — honored on Chromium). WebAudio
// resamples the mic input into that context; we do the trivial Float32->int16
// cast here. No wasm resampler.
//
// Self-contained/stringifiable like wasi-shim.mjs (no imports, no outer refs).
export function makeBrowserMicHost() {
  let memory;
  let requested = false;
  let stream = null;
  let ctx = null, node = null;
  let ring = [];                 // accumulated int16 samples

  const imports = {
    mic_device_count() {
      // First look kicks the permission request; empty until it resolves.
      if (!requested) {
        requested = true;
        navigator.mediaDevices.getUserMedia({ audio: true })
          .then((s) => { stream = s; })
          .catch(() => { stream = null; });   // denied -> stays empty
      }
      return stream ? 1 : 0;
    },
    mic_device_name(index, dst, maxLen) {
      if (index !== 0 || !stream || !memory) return 0;
      const bytes = new TextEncoder().encode('browser-mic');
      const n = Math.min(bytes.length, maxLen);
      new Uint8Array(memory.buffer, dst, n).set(bytes.subarray(0, n));
      return n;
    },
    mic_start(requestedRate, _channels) {
      if (!stream) return -1;
      try { ctx = new AudioContext({ sampleRate: requestedRate }); }
      catch { ctx = new AudioContext(); }
      const actual = ctx.sampleRate;           // capability check: what we got
      ctx.resume();
      const workletSrc =
        "class Cap extends AudioWorkletProcessor{process(inputs){" +
        "const ch=inputs[0][0];if(ch&&ch.length)this.port.postMessage(ch.slice(0));return true;}}" +
        "registerProcessor('cap',Cap);";
      const url = URL.createObjectURL(new Blob([workletSrc], { type: 'application/javascript' }));
      ctx.audioWorklet.addModule(url).then(() => {
        const src = ctx.createMediaStreamSource(stream);
        node = new AudioWorkletNode(ctx, 'cap');
        node.port.onmessage = (e) => {
          const f = e.data;                    // Float32 quantum
          for (let i = 0; i < f.length; i++) {
            const v = Math.max(-1, Math.min(1, f[i]));
            ring.push((v * 32767) | 0);         // trivial int16 cast, host-side
          }
        };
        const mute = ctx.createGain(); mute.gain.value = 0;   // capture-only, silent
        src.connect(node); node.connect(mute); mute.connect(ctx.destination);
      }).catch(() => { /* setup failed -> ring stays empty */ });
      return actual;
    },
    mic_stop() {
      if (stream) stream.getTracks().forEach((t) => t.stop());
      if (ctx) ctx.close();
      ctx = null; node = null; ring = [];
    },
    mic_sample_count() { return ring.length; },
    mic_read(dst, maxFrames) {
      if (!memory) return 0;
      const n = Math.min(maxFrames, ring.length);
      const dv = new DataView(memory.buffer);
      for (let i = 0; i < n; i++) dv.setInt16(dst + i * 2, ring[i], true);
      ring.splice(0, n);
      return n;
    },
  };

  return { imports, bind(m) { memory = m; } };
}
