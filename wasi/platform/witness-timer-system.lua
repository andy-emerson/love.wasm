-- Build-order step 6.6a witness: love.timer + love.system. Runs as the pump's
-- resident coroutine (love preloaded by pump-ext), yielding one line per check;
-- the final return value is the verdict.
--
-- What this proves:
--   * love.timer requires and runs: getTime() is a number that ADVANCES (real
--     CLOCK_MONOTONIC through the LOVE_WASI arm of Timer.cpp's POSIX guard,
--     fulfilled by the WASI host's clock_time_get), and step() returns a dt >= 0.
--     love.timer.sleep is the honest browser no-op (returns immediately).
--   * love.system requires and runs on the wasm backend over the love_system host
--     seam: getOS() == "Web" (the guarded seam), getProcessorCount() is the
--     host's hardwareConcurrency, the clipboard set/get round-trips, openURL is
--     carried, and getPreferredLocales() has the documented shape.
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

local tok = pcall(require, "love.timer")
check("require 'love.timer' SUCCEEDS", tok and type(love.timer) == "table", tok)
local sok = pcall(require, "love.system")
check("require 'love.system' SUCCEEDS", sok and type(love.system) == "table", sok)

-- ── love.timer ────────────────────────────────────────────────────────────────

local t0 = love.timer.getTime()
check("love.timer.getTime() returns a number", type(t0) == "number", t0)

-- Yield a real frame (the pump ticks rAF / setTimeout between resumes), then
-- confirm the monotonic clock strictly advances. A bounded busy-spin backstops
-- the assertion so it is deterministic regardless of frame timing granularity.
coroutine.yield("... yielded a frame to let the monotonic clock advance")
local t1 = love.timer.getTime()
local spins = 0
while t1 <= t0 and spins < 20000000 do
  t1 = love.timer.getTime()
  spins = spins + 1
end
check("love.timer.getTime() ADVANCES (t1 > t0)", t1 > t0, tostring(t0) .. " -> " .. tostring(t1))

local dt = love.timer.step()
check("love.timer.step() returns dt >= 0", type(dt) == "number" and dt >= 0, dt)
check("love.timer.getDelta() == the last step dt", love.timer.getDelta() == dt, love.timer.getDelta())

-- getFPS is defined and integral; getAverageDelta is a number. (Values are not
-- asserted exactly — they depend on frame history — only their shape.)
check("love.timer.getFPS() is a number", type(love.timer.getFPS()) == "number", love.timer.getFPS())
check("love.timer.getAverageDelta() is a number", type(love.timer.getAverageDelta()) == "number", love.timer.getAverageDelta())

-- sleep is the honest browser no-op: it must return promptly without throwing.
local slok = pcall(love.timer.sleep, 0.0)
check("love.timer.sleep(0) does not throw (honest no-op)", slok, slok)

-- ── love.system ───────────────────────────────────────────────────────────────

check("love.system.getOS() == 'Web'", love.system.getOS() == "Web", love.system.getOS())
-- love._os is baked at love.cpp open time from the same getOS(); it must agree.
check("love._os == 'Web'", love._os == "Web", love._os)

local pc = love.system.getProcessorCount()
check("love.system.getProcessorCount() >= 1", type(pc) == "number" and pc >= 1, pc)
-- The witness host (system-host.mjs) bakes hardwareConcurrency = 4.
check("getProcessorCount() == 4 (host hardwareConcurrency)", pc == 4, pc)

-- Clipboard round-trip through the host cell (fronting the async Clipboard API).
local baked = love.system.getClipboardText()
check("getClipboardText() returns the host's baked cell", baked == "love-wasi clipboard", baked)
love.system.setClipboardText("round-trip 4242")
check("setClipboardText/getClipboardText round-trips",
  love.system.getClipboardText() == "round-trip 4242", love.system.getClipboardText())

-- openURL is carried to the host and reports success.
local urlok = love.system.openURL("https://love2d.org")
check("love.system.openURL() returns true (carried to host)", urlok == true, urlok)

-- getPreferredLocales() shape: a non-empty array of strings; the host bakes
-- {"en-US","en"}.
local locales = love.system.getPreferredLocales()
check("getPreferredLocales() is a table", type(locales) == "table", locales)
check("getPreferredLocales()[1] == 'en-US'", locales[1] == "en-US", locales[1])
check("getPreferredLocales()[2] == 'en'", locales[2] == "en", locales[2])

-- getPowerInfo() reports the honest 'unknown' (browser battery API is gated).
local state = love.system.getPowerInfo()
check("getPowerInfo() == 'unknown'", state == "unknown", state)

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP66A-TIMER-SYSTEM-WITNESS: PASS" or "STEP66A-TIMER-SYSTEM-WITNESS: FAIL"
