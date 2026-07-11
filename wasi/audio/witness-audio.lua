-- Step-5 audio witness (mock host): the real LÖVE core booting under the pump
-- WITH love.audio linked. Covers a Source's whole lifecycle (create -> queue
-- PCM -> play -> stop) AND the microphone seam (RecordingDevice enumerate ->
-- start -> getData, tone recovered from the SoundData, then record->playback via
-- a static Source), through the one wasm-EH runtime. Backend-agnostic: it
-- asserts the contract executes; the actual sound is proven at the host seam
-- (PCM readback, and the real-capture leg in run-browser-mic.mjs). The inert
-- null backend exposes no devices, so the mic checks self-skip there.
local failures = 0
local function check(name, cond, got)
  if cond then
    coroutine.yield("ok   " .. name)
  else
    failures = failures + 1
    coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got))
  end
end

local love = require("love")
check("require 'love'", type(love) == "table", love)

-- love.audio links and registers (the wrap_Audio backend-selection seam picks
-- a non-OpenAL backend; without the guard this module would not even compile).
local aok = pcall(require, "love.audio")
check("require 'love.audio' (module links + selects a backend)",
  aok and type(love.audio) == "table", love.audio)

-- love.data supplies the PCM buffer, so no love.sound / file decoders are on
-- the path for this witness.
local dok = pcall(require, "love.data")
check("require 'love.data'", dok and type(love.data) == "table")

-- A queueable Source via the numeric overload — the decoder-free creation path.
local rate, bits, ch = 44100, 16, 1
local sok, src = pcall(love.audio.newQueueableSource, rate, bits, ch)
check("newQueueableSource creates a Source", sok and src ~= nil, src)

if sok and src then
  -- The inert null backend doesn't model source types (every Source reads as
  -- "static"); a real backend reports "queue" here. Backend-agnostic: assert a
  -- valid type string, report the value.
  local stype = src:getType()
  check("Source:getType returns a valid type",
    stype == "static" or stype == "stream" or stype == "queue", stype)
  coroutine.yield("Source:getType() = " .. tostring(stype))

  -- 0.1 s of int16 mono 440 Hz, built in Lua, handed over as a love.data Data
  -- pointer (lightuserdata) — the raw-PCM queue path.
  local n = math.floor(rate * 0.1)
  local parts = {}
  for i = 0, n - 1 do
    local s = math.floor(math.sin(2 * math.pi * 440 * i / rate) * 30000)
    if s < 0 then s = s + 65536 end
    parts[#parts + 1] = string.char(s % 256, math.floor(s / 256) % 256)
  end
  local bd = love.data.newByteData(table.concat(parts))
  local ptr = bd:getPointer()

  -- queue(lightuserdata, offset, length, sampleRate, bitDepth, channels)
  local qok, queued = pcall(src.queue, src, ptr, 0, bd:getSize(), rate, bits, ch)
  check("Source:queue executes and returns a boolean",
    qok and type(queued) == "boolean", qok and queued or queued)

  local pok, played = pcall(src.play, src)
  check("Source:play executes and returns a boolean",
    pok and type(played) == "boolean", pok and played or played)

  local ipok, playing = pcall(src.isPlaying, src)
  check("Source:isPlaying executes and returns a boolean",
    ipok and type(playing) == "boolean", ipok and playing or playing)

  pcall(src.stop, src)
  -- Report (not assert) the backend's play() result: null returns false, a
  -- real backend returns true. The seam readback is where sound is proven.
  coroutine.yield("backend Source:play() returned: " .. tostring(played))
end

-- Microphone: the RecordingDevice seam. Backend-agnostic — the inert null
-- backend exposes no devices (mic checks skipped); the webaudio backend drives
-- the host mic seam, and we recover the tone from the game-facing SoundData.
local devices = love.audio.getRecordingDevices()
check("getRecordingDevices returns a table", type(devices) == "table", devices)
if #devices == 0 then
  coroutine.yield("no recording devices (inert backend) — mic checks skipped")
else
  local dev = devices[1]
  check("recording device has a name",
    type(dev:getName()) == "string" and #dev:getName() > 0, dev:getName())

  -- Ask for 8000 Hz; the host can't honor it and delivers 48000 — the backend
  -- reports the ACTUAL rate (the capability check, no wasm resampler).
  local started = dev:start(8192, 8000, 16, 1)
  check("RecordingDevice:start returns true", started == true, started)
  check("getSampleRate reports the ACTUAL host rate (48000, not the 8000 asked)",
    dev:getSampleRate() == 48000, dev:getSampleRate())
  check("getBitDepth is 16", dev:getBitDepth() == 16, dev:getBitDepth())
  check("getChannelCount is 1", dev:getChannelCount() == 1, dev:getChannelCount())

  local n = dev:getSampleCount()
  check("getSampleCount > 0 after start", n > 0, n)

  local sd = dev:getData()
  check("getData returns a SoundData with samples",
    sd ~= nil and sd:getSampleCount() > 0, sd)

  dev:stop()
  check("isRecording is false after stop", dev:isRecording() == false, dev:isRecording())

  -- Recover the 440 Hz tone from the captured SoundData (exactly what a game
  -- receives) with a Goertzel filter in Lua, at the ACTUAL rate.
  if sd ~= nil then
    local rate = dev:getSampleRate()
    local count = sd:getSampleCount()
    local function goertzel(freq)
      local w = 2 * math.pi * freq / rate
      local c = 2 * math.cos(w)
      local s1, s2 = 0.0, 0.0
      for i = 0, count - 1 do
        local s0 = sd:getSample(i) + c * s1 - s2
        s2 = s1; s1 = s0
      end
      return math.sqrt(s1 * s1 + s2 * s2 - c * s1 * s2) / count
    end
    local ratio = goertzel(440) / (goertzel(440 * 2.71 + 37) + 1e-9)
    check("captured SoundData carries the 440 Hz tone (ratio > 8)", ratio > 8, ratio)
    coroutine.yield(("mic seam: %d samples @ %d Hz, 440 Hz ratio %.0f"):format(count, rate, ratio))

    -- Record -> playback: feed the captured SoundData to a STATIC Source and
    -- play it, exercising the static-source path (held PCM flushed on play()).
    local pbok, pb = pcall(love.audio.newSource, sd)
    check("newSource(SoundData) is a static Source",
      pbok and pb ~= nil and pb:getType() == "static", pbok and pb and pb:getType())
    if pbok and pb ~= nil then
      check("static Source plays the recorded SoundData", pb:play() == true, "play() false")
      pb:stop()
    end
  end
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP5-AUDIO-WITNESS: PASS" or "STEP5-AUDIO-WITNESS: FAIL"
