-- Step-4 (4.2) draw witness: the first real primitive through the backend. The
-- 4.1c witness only cleared a framebuffer; here the real LÖVE opengl backend
-- draws a filled rectangle and we read pixels back to confirm the colour landed
-- WHERE the geometry was rasterised — position, not just "something is
-- coloured". This is the first time geometry + a shader actually run: the
-- batched-draw path compiles LÖVE's default shader (glslang -> GLSL -> real
-- WebGL2 glCompileShader), streams vertices into a VBO, and issues glDrawArrays
-- — none of which the clear path touched. Driven through the graphics-ext
-- bridge (__wasi_gfx_draw_read); Chromium only (a node mock cannot fake a real
-- GL driver through a shader + draw).
--
-- The bridge clears the 4x4 backbuffer to a DISTINCT clear colour, then fills
-- only its LEFT HALF with the draw colour, and reads one pixel inside (left) and
-- one outside (right). The witness asserts BOTH: left == draw colour, right ==
-- clear colour. Left-drawn/right-clear proves the primitive is positioned, and
-- the right pixel keeping the clear colour proves the draw did not simply flood
-- the whole buffer.
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

-- Draw colour 0.2,0.4,0.6 -> exact 8-bit (51,102,153); clear colour 0.6,0.4,0.2
-- -> (153,102,51). Distinct (r and b swapped) so neither can be mistaken for the
-- other, and a black/no-op result matches neither.
local okd, Rin, Gin, Bin, Ain, Rout, Gout, Bout, Aout =
  pcall(__wasi_gfx_draw_read, 0.2, 0.4, 0.6, 0.6, 0.4, 0.2)
check("setMode + clear + rectangle + flush + readback executes", okd, Rin)
if okd then
  coroutine.yield(("inside  rgba = (%s,%s,%s,%s)"):format(tostring(Rin), tostring(Gin), tostring(Bin), tostring(Ain)))
  coroutine.yield(("outside rgba = (%s,%s,%s,%s)"):format(tostring(Rout), tostring(Gout), tostring(Bout), tostring(Aout)))
  local function near(x, e) return x ~= nil and math.abs(x - e) <= 2 end
  check("inside pixel is the draw colour (51,102,153,255)",
    near(Rin, 51) and near(Gin, 102) and near(Bin, 153) and near(Ain, 255),
    ("(%s,%s,%s,%s)"):format(tostring(Rin), tostring(Gin), tostring(Bin), tostring(Ain)))
  check("outside pixel is the clear colour (153,102,51,255)",
    near(Rout, 153) and near(Gout, 102) and near(Bout, 51) and near(Aout, 255),
    ("(%s,%s,%s,%s)"):format(tostring(Rout), tostring(Gout), tostring(Bout), tostring(Aout)))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-DRAW-WITNESS: PASS" or "STEP4-DRAW-WITNESS: FAIL"
