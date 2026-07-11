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

#include "RecordingDevice.h"
#include "Imports.h"

#include <cstring>

namespace love
{
namespace audio
{
namespace webaudio
{

RecordingDevice::RecordingDevice(const char *name)
	: name(name)
{
}

RecordingDevice::~RecordingDevice()
{
	if (recording)
		wa_mic_stop();
}

bool RecordingDevice::start(int samples, int sampleRate, int bitDepth, int channels)
{
	if (samples <= 0 || sampleRate <= 0)
		return false;

	if (recording)
		stop();

	// The host opens capture and reports the rate it will actually deliver at
	// (it owns the resampling). A negative result means no capture available.
	int actualRate = wa_mic_start(sampleRate, channels);
	if (actualRate < 0)
		return false;

	this->samples = samples;
	this->sampleRate = actualRate;   // ACTUAL rate, not the request
	this->bitDepth = 16;             // host delivers int16
	this->channels = channels;
	recording = true;
	(void)bitDepth;                  // requested depth is advisory; we deliver 16
	return true;
}

void RecordingDevice::stop()
{
	if (!recording)
		return;
	wa_mic_stop();
	recording = false;
}

love::sound::SoundData *RecordingDevice::getData()
{
	if (!recording)
		return nullptr;

	int available = wa_mic_sample_count();
	if (available <= 0)
		return nullptr;

	love::sound::SoundData *sd =
		new love::sound::SoundData(available, sampleRate, bitDepth, channels);

	// Drain host PCM straight into the SoundData buffer (int16, interleaved).
	int got = wa_mic_read(sd->getData(), available);

	// If the host delivered fewer frames than it reported, silence the untouched
	// tail rather than return uninitialized memory.
	if (got < available)
	{
		int frameBytes = channels * (bitDepth / 8);
		memset((unsigned char *)sd->getData() + (size_t)got * frameBytes, 0,
		       (size_t)(available - got) * frameBytes);
	}
	return sd;
}

const char *RecordingDevice::getName() const
{
	return name.c_str();
}

int RecordingDevice::getMaxSamples() const
{
	return samples;
}

int RecordingDevice::getSampleCount() const
{
	if (!recording)
		return 0;
	return wa_mic_sample_count();
}

int RecordingDevice::getSampleRate() const
{
	return sampleRate;
}

int RecordingDevice::getBitDepth() const
{
	return bitDepth;
}

int RecordingDevice::getChannelCount() const
{
	return channels;
}

bool RecordingDevice::isRecording() const
{
	return recording;
}

} //webaudio
} //audio
} //love
