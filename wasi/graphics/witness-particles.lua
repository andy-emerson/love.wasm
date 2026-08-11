-- Step-4 (4.11) particlesystem witness: the last higher-level drawable. A
-- ParticleSystem emits, simulates, and draws particles as textured quads — the
-- first witness that runs a real per-frame simulation step (update) before
-- drawing. The bridge builds a solid (51,102,153) particle texture, emits 8
-- long-lived particles at the centre with zero speed/spread (so they stack into a
-- deterministic blob rather than scattering randomly), advances the sim one
-- frame, and draws it. Reading the blob centre (particle colour) and a corner
-- (clear colour) proves emit + update + draw. Chromium only.
local failures = 0
local function check(name, cond, got)
  if cond then coroutine.yield("ok   " .. name)
  else failures = failures + 1; coroutine.yield("FAIL " .. name .. "   got: " .. tostring(got)) end
end

local love = require("love")
check("require 'love'", type(love) == "table", love)
local gok = pcall(require, "love.graphics")
check("require 'love.graphics' (opengl backend links + registers)",
  gok and type(love.graphics) == "table", love.graphics)

local function near(x, e) return x ~= nil and math.abs(x - e) <= 2 end
local function rgba(r, g, b, a) return ("(%s,%s,%s,%s)"):format(tostring(r),tostring(g),tostring(b),tostring(a)) end

local ok, Rin, Gin, Bin, Ain, Rout, Gout, Bout, Aout = pcall(__wasi_gfx_draw_particles)
check("newParticleSystem + emit + update + draw + readback executes", ok, ok and "" or Rin)
if ok then
  coroutine.yield(("particle blob = %s   background = %s"):format(rgba(Rin,Gin,Bin,Ain), rgba(Rout,Gout,Bout,Aout)))
  check("emitted particles rendered at the emission point (51,102,153)",
    near(Rin,51) and near(Gin,102) and near(Bin,153) and near(Ain,255), rgba(Rin,Gin,Bin,Ain))
  check("background away from the particles is the clear colour (76,76,76)",
    near(Rout,76) and near(Gout,76) and near(Bout,76) and near(Aout,255), rgba(Rout,Gout,Bout,Aout))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-PARTICLES-WITNESS: PASS" or "STEP4-PARTICLES-WITNESS: FAIL"
