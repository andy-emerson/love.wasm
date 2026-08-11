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
#include "Audio.h"
#include "Imports.h"

#include "common/Module.h"

#include <ctime>

namespace love
{
namespace audio
{
namespace webaudio
{

// The audio module, when there is one. play()/stop() report themselves to it so
// love.audio.stop() / getActiveSourceCount() see sources started the ordinary
// way (`source:play()`), which never passes through the module.
// The monotonic clock, read directly rather than through love.timer: the
// audio-only build does not link the timer module, and this is the same source
// Timer.cpp reads under LOVE_WASM.
static double nowSeconds()
{
	struct timespec ts;
	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0)
		return 0.0;
	return (double) ts.tv_sec + (double) ts.tv_nsec / 1.0e9;
}

static Audio *audioModule()
{
	return (Audio *) Module::getInstance<love::audio::Audio>(Module::M_AUDIO);
}

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
	if (playing)
	{
		playStartTime = nowSeconds();
		if (Audio *audio = audioModule())
			audio->trackPlaying(this);
	}
	return playing;
}

void Source::stop()
{
	if (handle >= 0)
		wa_source_stop(handle);
	playing = false;

	// Last, because untracking drops the module's reference and this may be the
	// only one left — nothing below may touch `this`.
	if (Audio *audio = audioModule())
		audio->untrack(this);
}

void Source::pause()
{
	// A distinct pause voice-state is a later refinement; stop for now.
	//
	// Deliberately does NOT untrack, unlike stop(): love.audio.pause() hands the
	// set back to Lua so love.audio.play(list) can resume it, and releasing here
	// would free a Source out from under that list before w_pause retains it.
	// The module's next reapFinished() does drop it — `playing` is false and
	// nothing here separates paused from finished — which is why this is a
	// deferral of the release, not a promise that a paused Source stays tracked.
	if (handle >= 0)
		wa_source_stop(handle);
	playing = false;
}

bool Source::isPlaying() const
{
	if (!playing)
		return false;
	// A looping Source never ends on its own, and STREAM/QUEUE have no known
	// length (getDuration is honestly -1 for them), so `playing` is the whole
	// answer for both.
	if (looping)
		return true;
	double duration = const_cast<Source *>(this)->getDuration(UNIT_SECONDS);
	if (duration < 0)
		return true;
	// A STATIC Source's length IS knowable, so run it against the clock: the
	// host gives us no "ended" callback, and treating a finished clip as still
	// playing is what made love.audio.pause() report Sources nobody is hearing.
	// Pitch scales playback rate, so it scales the wall-clock length too.
	double rate = pitch > 0.0f ? (double) pitch : 1.0;
	return (nowSeconds() - playStartTime) < (duration / rate);
}

bool Source::isFinished() const
{
	return !isPlaying();
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

double Source::getDuration(Unit unit)
{
	// A static Source holds its whole PCM buffer, so its length is arithmetic —
	// there is nothing to ask the host. Reporting -1 (LOVE's "unknown") made
	// every duration query a lie for the one case that is knowable.
	//
	// A STREAM or QUEUE Source genuinely has no fixed length here: the host is
	// fed as it goes, so -1 stays the honest answer for those.
	if (sourceType != TYPE_STATIC)
		return -1.0;

	const int bytesPerSample = (bitDepth / 8) * channels;
	if (bytesPerSample <= 0 || sampleRate <= 0)
		return -1.0;

	const double samples = (double) (staticData.size() / (size_t) bytesPerSample);
	return unit == UNIT_SAMPLES ? samples : samples / (double) sampleRate;
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
