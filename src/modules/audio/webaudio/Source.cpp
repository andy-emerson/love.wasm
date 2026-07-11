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

#include "Source.h"
#include "Imports.h"

namespace love
{
namespace audio
{
namespace webaudio
{

Source::Source(Type type, int sampleRate, int bitDepth, int channels)
	: love::audio::Source(type)
	, sampleRate(sampleRate)
	, bitDepth(bitDepth)
	, channels(channels)
{
}

Source::~Source()
{
	if (handle >= 0)
		wa_source_stop(handle);
}

void Source::setStaticData(const void *data, size_t bytes)
{
	const unsigned char *p = (const unsigned char *)data;
	staticData.assign(p, p + bytes);
	staticFlushed = false;
}

int Source::ensureHandle()
{
	if (handle < 0)
		handle = wa_source_create(sampleRate, channels);
	return handle;
}

love::audio::Source *Source::clone()
{
	this->retain();
	return this;
}

bool Source::play()
{
	int h = ensureHandle();
	if (h < 0)
		return false;

	// Flush a static source's held PCM to the host voice once, now that the
	// handle exists (never dropped even if the voice wasn't live at creation).
	if (!staticData.empty() && !staticFlushed)
	{
		int frameBytes = channels * (bitDepth / 8);
		int frames = frameBytes > 0 ? (int)(staticData.size() / frameBytes) : 0;
		wa_source_queue(h, staticData.data(), frames, sampleRate, bitDepth, channels);
		staticFlushed = true;
	}

	playing = wa_source_play(h) != 0;
	return playing;
}

void Source::stop()
{
	if (handle >= 0)
		wa_source_stop(handle);
	playing = false;
}

void Source::pause()
{
	// A distinct pause voice-state is a later refinement; stop for now.
	if (handle >= 0)
		wa_source_stop(handle);
	playing = false;
}

bool Source::isPlaying() const
{
	return playing;
}

bool Source::isFinished() const
{
	return !playing;
}

bool Source::update()
{
	return playing;
}

void Source::setPitch(float pitch)
{
	this->pitch = pitch;
}

float Source::getPitch() const
{
	return pitch;
}

void Source::setVolume(float volume)
{
	this->volume = volume;
	if (handle >= 0)
		wa_source_gain(handle, volume);
}

float Source::getVolume() const
{
	return volume;
}

void Source::seek(double, Source::Unit)
{
}

double Source::tell(Source::Unit)
{
	return 0.0f;
}

double Source::getDuration(Unit)
{
	return -1.0f;
}

void Source::setPosition(float *)
{
}

void Source::getPosition(float *) const
{
}

void Source::setVelocity(float *)
{
}

void Source::getVelocity(float *) const
{
}

void Source::setDirection(float *)
{
}

void Source::getDirection(float *) const
{
}

void Source::setCone(float innerAngle, float outerAngle, float outerVolume, float outerHighGain)
{
	coneInnerAngle = innerAngle;
	coneOuterAngle = outerAngle;
	coneOuterVolume = outerVolume;
	coneOuterHighGain = outerHighGain;
}

void Source::getCone(float &innerAngle, float &outerAngle, float &outerVolume, float &outerHighGain) const
{
	innerAngle = coneInnerAngle;
	outerAngle = coneOuterAngle;
	outerVolume = coneOuterVolume;
	outerHighGain = coneOuterHighGain;
}

void Source::setRelative(bool enable)
{
	relative = enable;
}

bool Source::isRelative() const
{
	return relative;
}

void Source::setLooping(bool looping)
{
	this->looping = looping;
}

bool Source::isLooping() const
{
	return looping;
}

void Source::setMinVolume(float volume)
{
	this->minVolume = volume;
}

float Source::getMinVolume() const
{
	return this->minVolume;
}

void Source::setMaxVolume(float volume)
{
	this->maxVolume = volume;
}

float Source::getMaxVolume() const
{
	return this->maxVolume;
}

void Source::setReferenceDistance(float distance)
{
	this->referenceDistance = distance;
}

float Source::getReferenceDistance() const
{
	return this->referenceDistance;
}

void Source::setRolloffFactor(float factor)
{
	this->rolloffFactor = factor;
}

float Source::getRolloffFactor() const
{
	return this->rolloffFactor;
}

void Source::setMaxDistance(float distance)
{
	this->maxDistance = distance;
}

float Source::getMaxDistance() const
{
	return this->maxDistance;
}

void Source::setAirAbsorptionFactor(float factor)
{
	absorptionFactor = factor;
}

float Source::getAirAbsorptionFactor() const
{
	return absorptionFactor;
}

int Source::getChannelCount() const
{
	return channels;
}

int Source::getFreeBufferCount() const
{
	// The host owns the queue; report a small positive budget so a game may
	// keep pushing. A precise count is a later refinement.
	return 8;
}

bool Source::queue(void *data, size_t length, int dataSampleRate, int dataBitDepth, int dataChannels)
{
	int h = ensureHandle();
	if (h < 0)
		return false;

	int frameBytes = dataChannels * (dataBitDepth / 8);
	int frames = frameBytes > 0 ? (int)(length / frameBytes) : 0;
	wa_source_queue(h, data, frames, dataSampleRate, dataBitDepth, dataChannels);
	return true;
}

bool Source::setFilter(const std::map<Filter::Parameter, float> &)
{
	return false;
}

bool Source::setFilter()
{
	return false;
}

bool Source::getFilter(std::map<Filter::Parameter, float> &)
{
	return false;
}

bool Source::setEffect(const char *)
{
	return false;
}

bool Source::setEffect(const char *, const std::map<Filter::Parameter, float> &)
{
	return false;
}

bool Source::unsetEffect(const char *)
{
	return false;
}

bool Source::getEffect(const char *, std::map<Filter::Parameter, float> &)
{
	return false;
}

bool Source::getActiveEffects(std::vector<std::string> &) const
{
	return false;
}

} // webaudio
} // audio
} // love
