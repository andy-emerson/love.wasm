-- Step-3 witness: the real LÖVE core, booting under the pump.
-- Runs as the pump's resident coroutine; yields one line per check so the
-- host transcript shows each fact as it is established. The final return
-- value is the verdict.
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
check("love._version is 12", lok and type(love._version) == "string"
  and love._version:match("^12%."), lok and love._version or love)

-- A real, unmodified engine module runs: love.math (pure C++, no seams).
local mok = pcall(require, "love.math")
check("require 'love.math' (real module)", mok and type(love.math) == "table")
check("love.math.perlinNoise", math.type(love.math.perlinNoise(0.5, 0.5)) == "float")
local rng = love.math.newRandomGenerator(0xDEADBEEF)
local r = rng:random(1, 6)
check("RandomGenerator object round-trip", r >= 1 and r <= 6, r)

-- The luax_catchexcept pattern (the 145-call-site fidelity bar): a typed
-- love::Exception thrown in real C++ arrives here as a Lua error, message
-- intact, through the one wasm-EH runtime.
local sok, serr = pcall(rng.setState, rng, "not-a-valid-state")
check("love::Exception -> Lua error via luax_catchexcept",
  not sok and tostring(serr):find("Invalid random state"), serr)

-- Not-yet-ported modules are absent loudly, not faked.
local gok, gerr = pcall(require, "love.graphics")
check("love.graphics absent (seam not yet built)", not gok, gerr)

-- The seam stub reports the documented stop-line.
local fok, ferr = pcall(require, "love.filesystem")
check("love.filesystem stops at the documented seam",
  not fok and tostring(ferr):find("host%-import VFS"), ferr)

-- The real thing: boot.lua's chunk returns LÖVE 12's main-loop function —
-- upstream's own control flow is already coroutine-shaped (it ends in
-- coroutine.yield per frame). Run it under the pump: love.boot() hits the
-- filesystem seam, error_printer reports it, and main returns 1 — the
-- boot sequence's defined exit, reached through LÖVE's own xpcall chain.
local bok, main = pcall(require, "love.boot")
check("require 'love.boot' returns the main function",
  bok and type(main) == "function", main)
if bok and type(main) == "function" then
  local rok, ret = pcall(main)
  check("LÖVE main() exits 1 at the filesystem seam", rok and ret == 1, ret)
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP3-WITNESS: PASS" or "STEP3-WITNESS: FAIL"
