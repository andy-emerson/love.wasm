-- Step-5 real-capture mic witness: drives love.audio.RecordingDevice against a
-- REAL browser getUserMedia -> AudioWorklet host (Chromium fake device), through
-- the reactor. Proves the whole mic path end-to-end — including the two async
-- edges the mock host can't exercise: permission-gated enumeration (empty until
-- getUserMedia resolves) and capture starting over several frames (the
-- across-frames model). Each coroutine.yield advances one rAF frame, during
-- which the browser's audio thread accumulates captured PCM.
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
local aok = pcall(require, "love.audio")
check("require 'love.audio'", aok and type(love.audio) == "table")

-- Permission-gated enumeration: getRecordingDevices() is empty until the host's
-- getUserMedia resolves a stream. Poll until a device appears.
local devices = {}
for _ = 1, 180 do
  devices = love.audio.getRecordingDevices()
  if #devices > 0 then break end
  coroutine.yield("waiting for mic permission/device...")
end
check("a recording device appears after permission is granted", #devices > 0, #devices)

if #devices > 0 then
  local dev = devices[1]
  check("device has a name",
    type(dev:getName()) == "string" and #dev:getName() > 0, dev:getName())

  local rate = 16000
  local started = dev:start(8192, rate, 16, 1)
  check("RecordingDevice:start returns true", started == true, started)
  check("getSampleRate is a valid host rate", dev:getSampleRate() > 0, dev:getSampleRate())

  -- Async capture: samples arrive over frames once the worklet runs.
  local n = 0
  for _ = 1, 300 do
    n = dev:getSampleCount()
    if n >= 2000 then break end
    coroutine.yield("capturing... (" .. tostring(n) .. " samples)")
  end
  check("captured >= 2000 samples", n >= 2000, n)

  local sd = dev:getData()
  check("getData returns a SoundData with samples",
    sd ~= nil and sd:getSampleCount() > 0, sd)
  dev:stop()

  -- Recover the 440 Hz tone from what real browser capture delivered.
  if sd ~= nil then
    local sr = dev:getSampleRate()
    local count = sd:getSampleCount()
    local function goertzel(freq)
      local w = 2 * math.pi * freq / sr
      local c = 2 * math.cos(w)
      local s1, s2 = 0.0, 0.0
      for i = 0, count - 1 do
        local s0 = sd:getSample(i) + c * s1 - s2
        s2 = s1; s1 = s0
      end
      return math.sqrt(s1 * s1 + s2 * s2 - c * s1 * s2) / count
    end
    local ratio = goertzel(440) / (goertzel(440 * 2.71 + 37) + 1e-9)
    check("real captured audio carries the 440 Hz tone (ratio > 8)", ratio > 8, ratio)
    coroutine.yield(("real mic: %d samples @ %d Hz, 440 Hz ratio %.0f"):format(count, sr, ratio))
  end
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP5-AUDIO-WITNESS: PASS" or "STEP5-AUDIO-WITNESS: FAIL"
