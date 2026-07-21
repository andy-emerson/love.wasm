-- love.sound decoder witness — pre-step-7 "unblock a real game" pass 2. Decodes a
-- REAL Ogg Vorbis asset (testing/resources/clickmono.ogg, base64-injected by the
-- run leg so node + browser compare the same bytes) into PCM via the lullaby
-- VorbisDecoder, proving the vendored libogg + libvorbis decode subset links and
-- runs under this build. Pure compute: decode from a love.data ByteData — no
-- love.filesystem, no love.audio, no host imports — so it runs on node:wasi AND
-- real Chromium. Runs as the pump's resident coroutine (love preloaded by
-- pump-ext); yields one line per check; the final return is the verdict.
local failures = 0
local function check(name, cond, got)
  if cond then
    coroutine.yield("ok   " .. name)
  else
    failures = failures + 1
    coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got))
  end
end

local lok, love = pcall(require, "love")
check("require 'love'", lok and type(love) == "table", love)
local dok = pcall(require, "love.data")
check("require 'love.data' SUCCEEDS", dok and type(love.data) == "table", dok)
local sok = pcall(require, "love.sound")
check("require 'love.sound' SUCCEEDS", sok and type(love.sound) == "table", sok)

-- The Ogg asset, base64-injected by the run leg (identical bytes on both legs).
local OGG_B64 = "__OGG_B64__"
local ok_b64, encoded = pcall(love.data.decode, "data", "base64", OGG_B64)
check("base64 decodes to a ByteData", ok_b64 and encoded ~= nil, ok_b64)

-- newSoundData(Data) routes through newDecoder -> the lullaby dispatch (Wave,
-- FLAC, Vorbis, ...), which recognises the Ogg and decodes it fully to PCM.
local ok_dec, sd = pcall(love.sound.newSoundData, encoded)
check("love.sound.newSoundData DECODED the Ogg", ok_dec and sd ~= nil,
  ok_dec and "ok" or tostring(sd))
if not (ok_dec and sd) then
  coroutine.yield("checks done, decode failed")
  return "STEP-SOUND-WITNESS: FAIL"
end

check("channel count == 1 (mono asset)", sd:getChannelCount() == 1, sd:getChannelCount())
local rate = sd:getSampleRate()
check("sample rate is sane (8k..48k)", type(rate) == "number" and rate >= 8000 and rate <= 48000, rate)
check("bit depth == 16", sd:getBitDepth() == 16, sd:getBitDepth())
local n = sd:getSampleCount()
check("sample count > 0", type(n) == "number" and n > 0, n)
check("duration > 0", sd:getDuration() > 0, sd:getDuration())

-- Real decoded audio, not silence: scan for a nonzero peak amplitude. getSample
-- returns a float in [-1, 1]; a decoded click asset must have energy somewhere.
local peak = 0
local last = math.min(n - 1, 20000)
for i = 0, last do
  local s = sd:getSample(i)
  local a = s < 0 and -s or s
  if a > peak then peak = a end
end
check("decoded PCM has nonzero energy (real audio, not silence)", peak > 0, peak)

coroutine.yield(("decoded %d samples @ %d Hz, peak %.3f, %d failures"):format(n, rate, peak, failures))
return failures == 0 and "STEP-SOUND-WITNESS: PASS" or "STEP-SOUND-WITNESS: FAIL"
