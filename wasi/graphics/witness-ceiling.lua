-- Step-4 (4.17) ceiling witness: the WebGL2 ceiling, witnessed as gracefully
-- ABSENT (issue #36). WebGL2 is OpenGL ES 3.0 — no compute shaders, no indirect
-- draw, no texel/texture buffers, no SSBO. This does NOT implement them; it
-- proves the engine reports them unsupported and rejects them CLEANLY rather than
-- crashing. The bridge reads the capability flags (all expected false), tries to
-- compile a compute shader and confirms it throws a catchable error (not an
-- abort), then clears + reads a pixel to prove the module is still healthy after
-- the rejection. This is the difference between "we forgot compute" and "compute
-- is a declared, gracefully-handled divergence". Chromium only.
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

local ok, glsl4, indirect, texel, computeRejected, hr, hg, hb = pcall(__wasi_gfx_ceiling)
check("capability query + compute-rejection + health readback executes", ok, ok and "" or glsl4)
if ok then
  coroutine.yield(("GLSL4=%s indirect_draw=%s texel_buffer=%s  compute_rejected=%s  health=(%s,%s,%s)")
    :format(tostring(glsl4), tostring(indirect), tostring(texel), tostring(computeRejected),
            tostring(hr), tostring(hg), tostring(hb)))
  check("compute / GLSL4 reported unsupported on WebGL2 (ES 3.0)", glsl4 == 0, glsl4)
  check("indirect draw reported unsupported on WebGL2", indirect == 0, indirect)
  check("texel buffers reported unsupported on WebGL2", texel == 0, texel)
  check("a compute shader is rejected with a catchable error, not a crash", computeRejected == 1, computeRejected)
  check("graphics module still healthy after the rejection (clear round-trips, 51,102,153)",
    near(hr,51) and near(hg,102) and near(hb,153), ("(%s,%s,%s)"):format(tostring(hr),tostring(hg),tostring(hb)))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-CEILING-WITNESS: PASS" or "STEP4-CEILING-WITNESS: FAIL"
