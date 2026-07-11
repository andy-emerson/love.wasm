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

#ifndef LOVE_AUDIO_WEBAUDIO_RECORDING_DEVICE_H
#define LOVE_AUDIO_WEBAUDIO_RECORDING_DEVICE_H

#include "audio/RecordingDevice.h"
#include "sound/SoundData.h"

#include <string>

namespace love
{
namespace audio
{
namespace webaudio
{

// Microphone capture over the host mic seam (wa_mic_* imports). Preserves
// LÖVE's synchronous, pull-based RecordingDevice contract: start() begins host
// capture, the game polls getSampleCount() and drains getData(). The host owns
// permission, the getUserMedia -> AudioWorklet graph, and the rate conversion;
// getSampleRate() reports the ACTUAL rate the host delivers (which may differ
// from the request — the capability check, no wasm resampler). PCM is delivered
// as int16 (the trivial cast from the browser's Float32 lives host-side).
class RecordingDevice : public love::audio::RecordingDevice
{
public:
	RecordingDevice(const char *name);
	virtual ~RecordingDevice();
	virtual bool start(int samples, int sampleRate, int bitDepth, int channels);
	virtual void stop();
	virtual love::sound::SoundData *getData();
	virtual const char *getName() const;
	virtual int getMaxSamples() const;
	virtual int getSampleCount() const;
	virtual int getSampleRate() const;
	virtual int getBitDepth() const;
	virtual int getChannelCount() const;
	virtual bool isRecording() const;

private:
	std::string name;
	int samples = DEFAULT_SAMPLES;    // requested ring-buffer capacity
	int sampleRate = 0;               // ACTUAL delivered rate (0 until started)
	int bitDepth = 16;                // int16 is what the host delivers
	int channels = DEFAULT_CHANNELS;
	bool recording = false;

}; //RecordingDevice

} //webaudio
} //audio
} //love

#endif //LOVE_AUDIO_WEBAUDIO_RECORDING_DEVICE_H
