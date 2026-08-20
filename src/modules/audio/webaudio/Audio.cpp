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

#include "Audio.h"
#include "Imports.h"

#include "sound/SoundData.h"
#include "sound/Decoder.h"

namespace love
{
namespace audio
{
namespace webaudio
{

Audio::Audio()
	: love::audio::Audio("love.audio.webaudio")
{
}

Audio::~Audio()
{
	// Drop the references trackPlaying() took, or every Source that was still
	// playing at teardown outlives the module that was keeping it alive. Emptied
	// first, so a Source destroyed here cannot see a half-torn-down set.
	std::vector<love::audio::Source*> tracked;
	tracked.swap(playingSources);
	for (auto *s : tracked)
		s->release();

	for (auto *d : capture)
		d->release();
}

love::audio::Source *Audio::newSource(love::sound::Decoder *decoder)
{
	// A streaming Source's format is the decoder's; incremental streaming into
	// the host voice is a later refinement (the raw-PCM / SoundData paths land
	// first). The voice is created; nothing is queued until streaming exists.
	return new Source(Source::TYPE_STREAM, decoder->getSampleRate(),
	                  decoder->getBitDepth(), decoder->getChannelCount());
}

love::audio::Source *Audio::newSource(love::sound::SoundData *soundData)
{
	// A static Source holds its whole PCM and flushes it on play() — not an
	// eager queue at creation (which would be dropped if the host voice isn't
	// live yet).
	Source *s = new Source(Source::TYPE_STATIC, soundData->getSampleRate(),
	                       soundData->getBitDepth(), soundData->getChannelCount());
	s->setStaticData(soundData->getData(), soundData->getSize());
	return s;
}

love::audio::Source *Audio::newSource(int sampleRate, int bitDepth, int channels, int /*buffers*/)
{
	return new Source(Source::TYPE_QUEUE, sampleRate, bitDepth, channels);
}

int Audio::getActiveSourceCount() const
{
	// Reap before counting, for the same reason pause() does: a Source that ran
	// to its own end is not active, and nothing tells us so unprompted.
	const_cast<Audio *>(this)->reapFinished();
	return (int) playingSources.size();
}

void Audio::trackPlaying(love::audio::Source *source)
{
	for (auto *s : playingSources)
	{
		if (s == source)
			return;
	}
	source->retain();
	playingSources.push_back(source);
}

void Audio::untrack(love::audio::Source *source)
{
	for (auto it = playingSources.begin(); it != playingSources.end(); ++it)
	{
		if (*it == source)
		{
			(*it)->release();
			playingSources.erase(it);
			return;
		}
	}
}

int Audio::getMaxSources() const
{
	return 64;
}

// Source::play()/stop() are what maintain playingSources, not these entry
// points: wrap_Source's `source:play()` / `source:stop()` call the Source
// directly and never come through the module, which is the way games actually
// start a sound. Registering here as well would leave that path untracked —
// love.audio.stop() would stop nothing and getActiveSourceCount() would answer
// 0 — so the Source owns the bookkeeping, exactly as openal's Source does
// through the Pool.
bool Audio::play(love::audio::Source *source)
{
	return source != nullptr && source->play();
}

bool Audio::play(const std::vector<love::audio::Source*> &sources)
{
	bool any = false;
	for (auto *s : sources)
	{
		if (s != nullptr && s->play())
			any = true;
	}
	return any;
}

void Audio::stop(love::audio::Source *source)
{
	if (source != nullptr)
		source->stop();
}

void Audio::stop(const std::vector<love::audio::Source*> &sources)
{
	for (auto *s : sources)
	{
		if (s != nullptr)
			s->stop();
	}
}

void Audio::stop()
{
	// Copy first, and hold a reference across the walk: stop() untracks, which
	// drops the tracking reference and can destroy the Source mid-loop.
	std::vector<love::audio::Source*> all = playingSources;
	for (auto *s : all)
		s->retain();
	for (auto *s : all)
		s->stop();
	for (auto *s : all)
		s->release();
}

void Audio::pause(love::audio::Source *source)
{
	if (source != nullptr)
		source->pause();
}

void Audio::pause(const std::vector<love::audio::Source*> &sources)
{
	for (auto *s : sources)
		if (s != nullptr)
			s->pause();
}

// Drop Sources that have finished on their own. The host reports no "ended"
// event, so completion is only ever observed on demand; every answer that
// depends on "what is playing" reaps before answering.
void Audio::reapFinished()
{
	std::vector<love::audio::Source*> live;
	live.reserve(playingSources.size());
	for (auto *s : playingSources)
	{
		if (s->isPlaying())
			live.push_back(s);
		else
			s->release();
	}
	playingSources.swap(live);
}

std::vector<love::audio::Source*> Audio::pause()
{
	// LOVE's contract: pause everything currently playing and hand back exactly
	// those Sources, so love.audio.play(list) can resume them.
	//
	// Nothing is untracked HERE, and that is what makes the returned vector safe:
	// the tracking reference is routinely the last one — a Source played and then
	// dropped by Lua is kept alive by nothing else — so releasing during this
	// call would have w_pause push an already-destroyed Source to Lua. The next
	// reapFinished() does drop them, because Source::pause() stops the voice and
	// clears `playing`, and this backend has no way to tell paused from finished;
	// by then w_pause has retained everything it handed to Lua.
	//
	// Reap first: a STATIC Source that ran to its own end is not playing, and
	// with no host "ended" event the set only learns that by being asked. Without
	// this, pause() hands back every Source ever played — the corpus's
	// audio/pause asserts exactly that ("check nothing paused").
	reapFinished();
	std::vector<love::audio::Source*> paused = playingSources;
	for (auto *s : paused)
		s->pause();
	return paused;
}

void Audio::setVolume(float volume)
{
	this->volume = volume;
}

float Audio::getVolume() const
{
	return volume;
}

// Store and report. Desktop round-trips these through OpenAL's own listener
// state (openal/Audio.cpp:469 — alGetListenerfv / alListenerfv), so a game that
// sets and reads back sees the same values here that it sees there. What a
// browser does not do is APPLY them, which is the declared part.
//
// The empty bodies these replace were not a no-op: the wrapper reads an
// uninitialized array and pushes it to Lua, so the game received stack noise
// rather than the value it had set (#88).
void Audio::getPosition(float *v) const
{
	for (int i = 0; i < 3; i++)
		v[i] = position[i];
}

void Audio::setPosition(float *v)
{
	for (int i = 0; i < 3; i++)
		position[i] = v[i];
}

void Audio::getOrientation(float *v) const
{
	for (int i = 0; i < 6; i++)
		v[i] = orientation[i];
}

void Audio::setOrientation(float *v)
{
	for (int i = 0; i < 6; i++)
		orientation[i] = v[i];
}

void Audio::getVelocity(float *v) const
{
	for (int i = 0; i < 3; i++)
		v[i] = velocity[i];
}

void Audio::setVelocity(float *v)
{
	for (int i = 0; i < 3; i++)
		velocity[i] = v[i];
}

void Audio::setDopplerScale(float scale)
{
	dopplerScale = scale;
}

float Audio::getDopplerScale() const
{
	return dopplerScale;
}

const std::vector<love::audio::RecordingDevice*> &Audio::getRecordingDevices()
{
	// Populate once from the host's device list. Empty on a real host until mic
	// permission is granted (LÖVE's Android-shaped seam), so a game gates on the
	// list being non-empty.
	if (capture.empty())
	{
		int count = wa_mic_device_count();
		for (int i = 0; i < count; i++)
		{
			char buf[256];
			int len = wa_mic_device_name(i, buf, (int)sizeof(buf) - 1);
			if (len < 0)
				len = 0;
			if (len > (int)sizeof(buf) - 1)
				len = (int)sizeof(buf) - 1;
			buf[len] = '\0';
			capture.push_back(new RecordingDevice(buf));
		}
	}
	return capture;
}

Audio::DistanceModel Audio::getDistanceModel() const
{
	return distanceModel;
}

void Audio::setDistanceModel(DistanceModel distanceModel)
{
	this->distanceModel = distanceModel;
}

bool Audio::setEffect(const char *, std::map<Effect::Parameter, float> &)
{
	return false;
}

bool Audio::unsetEffect(const char *)
{
	return false;
}

bool Audio::getEffect(const char *, std::map<Effect::Parameter, float> &)
{
	return false;
}

bool Audio::getActiveEffects(std::vector<std::string> &) const
{
	return false;
}

int Audio::getMaxSceneEffects() const
{
	return 0;
}

int Audio::getMaxSourceEffects() const
{
	return 0;
}

bool Audio::isEFXsupported() const
{
	return false;
}

bool Audio::setOutputSpatialization(bool, const char *)
{
	return false;
}

bool Audio::getOutputSpatialization(const char *&filter) const
{
	filter = nullptr;
	return false;
}

void Audio::getOutputSpatializationFilters(std::vector<std::string> &) const
{
}

void Audio::pauseContext()
{
}

void Audio::resumeContext()
{
}

std::string Audio::getPlaybackDevice()
{
	return "";
}

void Audio::getPlaybackDevices(std::vector<std::string> &)
{
}

} // webaudio
} // audio
} // love
