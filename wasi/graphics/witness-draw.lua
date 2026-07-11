-- Step-4 (4.2) draw witness: the first real primitive through the backend. The
-- 4.1c witness only cleared a framebuffer; here the real LÖVE opengl backend
-- draws a filled rectangle and we read the pixel back to confirm the colour
-- landed where the geometry was rasterised. This is the first time geometry +
-- a shader actually run: the batched-draw path compiles LÖVE's default shader
-- (glslang -> GLSL -> real WebGL2 glCompileShader), streams vertices into a VBO,
-- and issues glDrawArrays — none of which the clear path touched. Driven through
-- the graphics-ext bridge (__wasi_gfx_draw_read); Chromium only (a node mock
-- cannot fake a real GL driver through a shader + draw).
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

-- Draw a filled rectangle in a known colour: 0.2,0.4,0.6 -> exact 8-bit
-- (51,102,153), alpha 1.0 -> 255. The rectangle covers the whole 4x4 backbuffer
-- over a black clear, so the centre pixel is unambiguously the rectangle's.
local okd, R, G, B, A = pcall(__wasi_gfx_draw_read, 0.2, 0.4, 0.6)
check("setMode + clear + rectangle + present + readback executes", okd, R)
if okd then
  coroutine.yield(("readback rgba = (%s,%s,%s,%s)"):format(tostring(R), tostring(G), tostring(B), tostring(A)))
  local function near(x, e) return x ~= nil and math.abs(x - e) <= 2 end
  check("drawn pixel recovered (51,102,153,255)",
    near(R, 51) and near(G, 102) and near(B, 153) and near(A, 255),
    ("(%s,%s,%s,%s)"):format(tostring(R), tostring(G), tostring(B), tostring(A)))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-DRAW-WITNESS: PASS" or "STEP4-DRAW-WITNESS: FAIL"
