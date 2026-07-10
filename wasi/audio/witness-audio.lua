-- Step-5 sub-step 1a witness: the real LÖVE core booting under the pump WITH
-- love.audio linked. Proves the audio module wires up and a Source's whole
-- lifecycle (create -> queue PCM -> play -> stop) executes without crashing,
-- through the one wasm-EH runtime. The backend's ACTUAL sound output is
-- witnessed separately at the host seam (PCM readback), not from Lua — so this
-- witness is backend-agnostic: it asserts the contract executes, not that the
-- inert null backend makes noise.
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

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP5-AUDIO-WITNESS: PASS" or "STEP5-AUDIO-WITNESS: FAIL"
