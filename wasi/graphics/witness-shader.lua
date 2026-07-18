-- Step-4 (4.5) custom-shader witness: the first USER shader through the backend.
-- 4.1c–4.4 all ran LÖVE's built-in shaders; 4.5 is the first time shader code
-- that did not ship with the engine makes the full trip — LÖVE-GLSL -> glslang
-- reflection + translation -> real WebGL2 glShaderSource/glCompileShader/
-- glLinkProgram -> bound -> executed. The bridge compiles a pixel shader whose
-- effect() INVERTS the incoming vertex colour (output is a function of input, not
-- a constant), draws a rectangle over the left half in setColor (0.8,0.6,0.4),
-- and reads back: the left half must be the inverted colour (0.2,0.4,0.6), the
-- right half the clear colour. If the default shader had run, the left half would
-- be (0.8,0.6,0.4) — so recovering the inversion proves the custom shader
-- compiled, bound, executed, and received its vertex-colour input. Chromium only.
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

local gok = pcall(require, "love.graphics")
check("require 'love.graphics' (opengl backend links + registers)",
  gok and type(love.graphics) == "table", love.graphics)

local function near(x, e) return x ~= nil and math.abs(x - e) <= 2 end
local function rgba(r, g, b, a) return ("(%s,%s,%s,%s)"):format(tostring(r),tostring(g),tostring(b),tostring(a)) end

local ok, Rin, Gin, Bin, Ain, Rout, Gout, Bout, Aout = pcall(__wasi_gfx_draw_shader)
check("newShader + setShader + draw + readback executes", ok, ok and "" or Rin)
if ok then
  coroutine.yield(("shader output = %s   background = %s"):format(rgba(Rin,Gin,Bin,Ain), rgba(Rout,Gout,Bout,Aout)))
  -- setColor (0.8,0.6,0.4) -> (204,153,102); inverted by effect() -> (51,102,153).
  check("custom shader ran: left half is the INVERTED colour (51,102,153)",
    near(Rin,51) and near(Gin,102) and near(Bin,153) and near(Ain,255), rgba(Rin,Gin,Bin,Ain))
  check("background is the clear colour (76,76,76)",
    near(Rout,76) and near(Gout,76) and near(Bout,76) and near(Aout,255), rgba(Rout,Gout,Bout,Aout))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-SHADER-WITNESS: PASS" or "STEP4-SHADER-WITNESS: FAIL"
