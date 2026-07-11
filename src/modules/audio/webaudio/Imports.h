/**
 * Copyright (c) 2006-2026 LOVE Development Team
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 **/

#ifndef LOVE_AUDIO_WEBAUDIO_IMPORTS_H
#define LOVE_AUDIO_WEBAUDIO_IMPORTS_H

// The finite, host-agnostic audio import surface (readme.md: everything the
// host supplies as imports, the same role an OS plays for desktop LÖVE). The
// host — a browser, or the witness's mock — implements these; wasm only calls
// them. Any host does the mixing (per-source WebAudio nodes) and the sample-rate
// conversion (AudioBuffer at the source's own rate); love-wasi owns no DSP.
// See wasi/audio/DESIGN.md.

#define WA_IMPORT(sym) __attribute__((import_module("love_audio"), import_name(sym)))

extern "C" {

// Create one host playback voice for a Source; returns an opaque handle (>= 0),
// or -1 if the host has no audio output. Called lazily on first use.
WA_IMPORT("source_create") int wa_source_create(int sampleRate, int channels);

// Hand the host `frames` of interleaved PCM at `bitDepth` (8 or 16) and the
// given rate. The host builds a WebAudio AudioBuffer at `sampleRate` (so the
// graph, not wasm, resamples to the context rate) after the trivial int->float
// cast. Static Sources push once; queueable Sources push repeatedly.
WA_IMPORT("source_queue") void wa_source_queue(int handle, const void *pcm,
        int frames, int sampleRate, int bitDepth, int channels);

// Playback control. play returns 1 if the voice started (a live host context),
// 0 otherwise (e.g. autoplay still suspended) — mapped to Source::play()'s bool.
WA_IMPORT("source_play") int wa_source_play(int handle);
WA_IMPORT("source_stop") void wa_source_stop(int handle);
WA_IMPORT("source_gain") void wa_source_gain(int handle, float gain);

// --- Microphone capture (RecordingDevice) ---
// The finite mic surface. A single active capture (the witness/first host use
// one device); a multi-device host would add handles. Permission is the host's
// concern (LÖVE's Android-shaped seam); enumeration is empty until granted on a
// real host, so a game gates on getRecordingDevices() being non-empty.
WA_IMPORT("mic_device_count") int wa_mic_device_count(void);
WA_IMPORT("mic_device_name") int wa_mic_device_name(int index, char *dst, int maxLen);

// Begin capture at (or near) the requested rate. Returns the ACTUAL rate the
// host will deliver — it owns the resampling, and if it cannot honor the
// request it reports what it gives (the capability check; no wasm DSP), or -1
// if capture is unavailable. PCM is delivered as interleaved int16.
WA_IMPORT("mic_start") int wa_mic_start(int requestedRate, int channels);
WA_IMPORT("mic_stop") void wa_mic_stop(void);

// Pull-based drain: how many frames are available now, and copy up to
// maxFrames int16 frames into `dst`, returning the number copied.
WA_IMPORT("mic_sample_count") int wa_mic_sample_count(void);
WA_IMPORT("mic_read") int wa_mic_read(void *dst, int maxFrames);

}

#undef WA_IMPORT

#endif // LOVE_AUDIO_WEBAUDIO_IMPORTS_H
