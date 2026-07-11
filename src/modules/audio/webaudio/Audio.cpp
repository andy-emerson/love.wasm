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
	return 0;
}

int Audio::getMaxSources() const
{
	return 64;
}

bool Audio::play(love::audio::Source *source)
{
	return source != nullptr && source->play();
}

bool Audio::play(const std::vector<love::audio::Source*> &sources)
{
	bool any = false;
	for (auto *s : sources)
		any = (s != nullptr && s->play()) || any;
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
		if (s != nullptr)
			s->stop();
}

void Audio::stop()
{
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

std::vector<love::audio::Source*> Audio::pause()
{
	return {};
}

void Audio::setVolume(float volume)
{
	this->volume = volume;
}

float Audio::getVolume() const
{
	return volume;
}

void Audio::getPosition(float *) const
{
}

void Audio::setPosition(float *)
{
}

void Audio::getOrientation(float *) const
{
}

void Audio::setOrientation(float *)
{
}

void Audio::getVelocity(float *) const
{
}

void Audio::setVelocity(float *)
{
}

void Audio::setDopplerScale(float)
{
}

float Audio::getDopplerScale() const
{
	return 1.0f;
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
