# love-wasi audio backend — design decisions

The build-order step-5 audio seam. This records the decisions the `webaudio`
backend is built on, and the microphone plan — both now **built and witnessed**
(playback + microphone, 440 Hz tone-recovery on node + Chromium, including a real
`getUserMedia` capture leg). It remains the decisions note; where a passage below
reads as a plan, the code has since landed it (the import names are kept in sync
with `src/modules/audio/webaudio/Imports.h`).

## The one principle: love-wasi is a pure audio adapter

love-wasi does **no custom audio DSP**. It decodes (real, in-tree, already
ours), does the one trivial per-sample format cast the boundary forces
(int16 ↔ Float32), and hands PCM to the platform. Everything hard — mixing,
spatialization, sample-rate conversion — is the platform's job, exactly as it
is on desktop, where **OpenAL** does all of it and LÖVE owns none of it.

This is not an aesthetic preference; it is faithfulness. LÖVE's audio backend
has always been a thin adapter over a platform audio library. WebAudio is the
browser's OpenAL, so the browser backend stays the same *kind* of thing.

## Decision 1 — Mixing: delegate to WebAudio (per-source nodes)

Each `love.audio` Source becomes one WebAudio node; the browser's graph sums
them. LÖVE never mixes audio itself on any platform (desktop's `pool`/
`poolThread` hands per-Source PCM to OpenAL, which mixes and spatializes), so
delegating to WebAudio is the faithful, upstream-shaped choice. Mixing in wasm
would re-implement OpenAL's mixer — new divergence, more code, still not
bit-exact — and is adopted **only if** a cross-browser parity test later shows
WebAudio's summation diverging in a way that matters.

## Decision 2 — Resampling: delegate to WebAudio everywhere

**Never resample ourselves. Delegate to WebAudio. Where a browser won't
resample capture, report the actual rate rather than resample.** One rule,
covering playback and mic alike, with no resampler of our own.

Good arbitrary-ratio resampling is genuinely hard (anti-aliasing, polyphase
filters — the reason libsamplerate/SoX exist), and LÖVE delegated it to OpenAL
precisely because of that. Hand-rolling one is the "do it poorly" trap;
growing one is the "becomes its own project" trap. So:

- **Playback** — a source's PCM goes into a WebAudio `AudioBuffer` at the
  source's *own* rate; the graph resamples it to the context rate on playback.
  Core WebAudio, high-confidence on every engine.
- **Capture (mic)** — open the capture `AudioContext` at the game's requested
  rate and let WebAudio resample the mic input into it.
- **Runtime capability check, not a static assumption** — at mic start, request
  the context rate and read back `ctx.sampleRate`. Honored → delegation did the
  work. Not honored (or `createMediaStreamSource` throws) → report the *actual*
  captured rate via `RecordingDevice:getSampleRate()`. A declared divergence
  (desktop OpenAL always honors the request), but zero DSP.
- **Vendor, never hand-roll, and only if forced** — if a real game later needs
  exact-rate mic on a browser that won't delegate, vendor a proven resampler
  (speexdsp / libsamplerate), used consistently. Last resort, evidence-gated.

**Evidence:** `wasi/audio/probe-resample.mjs` proved both paths in Chromium
(playback 24000→48000 tone intact; capture context honored at 16000 with the
tone intact). Firefox/WebKit are **unverified** — tracked in **issue #33**. The
runtime check keeps the port correct on all engines regardless; only the mic's
rate *faithfulness* on Firefox/WebKit is open.

## Decision 3 — Device-agnostic fidelity draws the wasm/host line

The preview's bar is **device-agnostic fidelity** (same correct behavior across
browsers), not desktop parity. "Browser-native" is not automatically
device-agnostic: most of WebAudio is spec-deterministic (summation, linear
gain, equal-power `StereoPannerNode`, device output → identical everywhere), but
two things vary by engine — **sample-rate resampling** (handled by Decision 2)
and **HRTF spatialization** (`PannerNode`, 3D math not spec-pinned).

So **HRTF is deferred**: use the deterministic `StereoPannerNode` + gain now; a
device-agnostic 3D spatializer is a separate, later, deliberate design.

| WebAudio owns (identical everywhere) | love-wasi owns |
|---|---|
| summation (mix), gain, equal-power stereo pan, device output | decode; the trivial int16↔Float32 cast |
| sample-rate conversion (playback + capture) | the runtime capability check + report-rate fallback |

love-wasi owns no DSP it must be good at.

## The playback contract (sub-step 1b)

The `webaudio` backend grows the WASI host shim with a small, fixed audio import
surface (host-agnostic — any host implements it; the witness supplies a mock
that taps PCM for the seam readback):

```
source_create(rate, channels) -> handle           // one WebAudio node per Source
source_queue(handle, ptr, frames, rate, bitDepth, channels)  // int PCM; host builds an AudioBuffer at `rate`
source_play(handle) / source_stop(handle) / source_gain(handle, g)
```
(module `love_audio`; a static Source holds its PCM and flushes it on play(),
a queueable Source pushes through queue().)

Its witness recovers the **tone**, not just "executes": the node leg taps PCM
at the import boundary (Goertzel at the test frequency), the Chromium leg reads
it back through `OfflineAudioContext`.

## The microphone plan (built — this branch's mic sub-step)

Mic is a sub-step in this same branch/PR (no separate issue, by decision). It
maps LÖVE's existing `RecordingDevice` contract onto browser
capture. The contract (`src/modules/audio/RecordingDevice.h`) is synchronous and
pull-based: `start(samples, rate, bitDepth, channels) -> bool`, then the game
polls `getSampleCount()` / drains `getData()`; defaults 8000 Hz / 16-bit / mono.

Mapping:

- **Permission reuses LÖVE's existing Android-shaped seam.** `love.audio`
  already has `hasRecordingPermission()` / `requestRecordingPermission()` and
  `getRecordingDevices()` returns empty until granted — Android's model is
  async/prompt-gated, exactly like the browser's `getUserMedia`. So the mic is
  not a novel design; it's "do what Android does, with browser primitives."
  `hasRecordingPermission()` is backed by `navigator.permissions.query`
  (Safari lacks it → assume `prompt`, rely on the `getUserMedia` result).
- **Capture graph:** `getUserMedia({audio}) -> MediaStreamSource -> AudioWorklet
  -> silent destination` (an unconnected worklet isn't reliably pulled). The
  worklet posts transferred Float32 `ArrayBuffer`s (128-frame quanta) to the
  main thread — **no SharedArrayBuffer, no COOP/COEP**. Worklet module ships
  **inlined via a Blob URL** ("one artifact").
- **Rate: delegate, per Decision 2 — no wasm resampler.** Open the capture
  `AudioContext` at the requested rate; capability-check `ctx.sampleRate`;
  report the actual rate if not honored. The only in-wasm math is the trivial
  Float32→int16 cast.
- **Sync façade:** `start()` returns true iff the host holds a live stream
  (matches Android when permission is absent); state resolves across
  frame-pump ticks (the async-across-frames model). `mic_device_count`,
  `mic_device_name`, `mic_start`, `mic_stop`, `mic_sample_count`, `mic_read` —
  the finite import surface (module `love_audio`). Permission is host-side and
  reflected at enumeration (empty until granted), not a wasm import — that is
  the only Lua-visible recording surface (`love.audio.getRecordingDevices`).
- **Witness:** a mock host feeds a canned sine through `mic_read` (pure
  RecordingDevice logic, node + Chromium), and a dedicated real-capture leg
  (`wasi/audio/run-browser-mic.mjs`) drives the real `getUserMedia` →
  AudioWorklet path against Chromium's fake device end-to-end — recovering the
  tone from the game-facing `SoundData`, with permission-gated enumeration.

Superseded: the earlier mic sketch had resampling live in wasm. Decision 2
replaced that with delegate-and-capability-check; this note is the current plan.
