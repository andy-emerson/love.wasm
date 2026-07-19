-- Issue-#27 witness: love.sensor as a warned-stub backend, and the one-time,
-- non-fatal "[love-wasi preview]" warning mechanism behind it. Runs as the
-- pump's resident coroutine (love is preloaded by pump-ext), yielding one line
-- per check so the host transcript shows each fact as it lands. The final return
-- value is the verdict.
--
-- What Lua CAN witness here is the NON-FATAL / SAFE-DEFAULT half: the module
-- loads, capability queries answer honestly without side effects, and USING a
-- sensor (getData) returns a benign, well-shaped default instead of throwing.
-- The ONE-TIME half — that the preview warning is emitted exactly once no matter
-- how many times the feature is used — is host-routed over stderr, which Lua
-- cannot see; the JS legs assert the "[love-wasi preview]" line count from the
-- host tap after this coroutine finishes (getData is called TWICE below; the tap
-- must hold exactly one preview line).
local failures = 0
local function check(name, cond, got)
  if cond then
    coroutine.yield("ok   " .. name)
  else
    failures = failures + 1
    coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got))
  end
end

-- The LÖVE core links and registers.
local lok, love = pcall(require, "love")
check("require 'love'", lok and type(love) == "table", love)

-- love.sensor loads: LOVE_ENABLE_SENSOR is defined and the wasm warned-stub
-- backend is constructed at the wrap_Sensor.cpp factory seam (in place of SDL).
local sok, serr = pcall(require, "love.sensor")
check("require 'love.sensor' SUCCEEDS", sok and type(love.sensor) == "table", serr)

-- Capability queries are benign: honest "no", NO preview warning (a game polls
-- these every frame to decide whether to try, and must be able to do so
-- silently). Neither throws.
local hok, has = pcall(love.sensor.hasSensor, "accelerometer")
check("hasSensor('accelerometer') does not throw", hok, has)
check("hasSensor('accelerometer') == false", hok and has == false, has)

local eok, en = pcall(love.sensor.isEnabled, "gyroscope")
check("isEnabled('gyroscope') does not throw", eok, en)
check("isEnabled('gyroscope') == false", eok and en == false, en)

-- ATTEMPTED USE: getData is the warned feature. It must NOT throw and must
-- return a benign, well-shaped default (three zeros: x, y, z). This is the first
-- use of the "sensor.getData" preview key, so the host tap gains ONE
-- "[love-wasi preview]" line here.
local g1ok, x1, y1, z1 = pcall(love.sensor.getData, "accelerometer")
check("getData('accelerometer') does not throw (non-fatal)", g1ok, x1)
check("getData returns three zeros (safe default)",
  g1ok and x1 == 0 and y1 == 0 and z1 == 0, g1ok and tostring(x1) or x1)

-- ONE-TIME: use the SAME warned feature a SECOND time. Still non-fatal, still
-- the safe default — and the host tap must NOT gain a second preview line (the
-- JS legs assert the count stays 1). The dedup is per-key and static.
local g2ok, x2, y2, z2 = pcall(love.sensor.getData, "accelerometer")
check("getData('accelerometer') again does not throw", g2ok, x2)
check("getData again returns three zeros (still safe default)",
  g2ok and x2 == 0 and y2 == 0 and z2 == 0, g2ok and tostring(x2) or x2)

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP27-WARN-WITNESS: PASS" or "STEP27-WARN-WITNESS: FAIL"
