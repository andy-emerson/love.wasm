-- Step-4 (4.13) MRT witness: multiple render targets. The bridge binds two 8x8
-- render-target textures together and runs ONE draw of an MRT pixel shader
-- (void effect() writing love_Canvases[0] and love_Canvases[1] to two distinct
-- colours), then draws each target onto the backbuffer side by side. Recovering
-- target 0's colour on the left AND target 1's DIFFERENT colour on the right,
-- from that single draw, proves the two colour attachments received independent
-- shader outputs (glDrawBuffers + a multi-output pixel shader). Chromium only.
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

local ok, r0,g0,b0,a0, r1,g1,b1,a1, rb,gb,bb,ab = pcall(__wasi_gfx_draw_mrt)
check("setRenderTargets(2) + MRT shader + draw + readback executes", ok, ok and "" or r0)
if ok then
  coroutine.yield(("target0=%s  target1=%s  bg=%s"):format(
    rgba(r0,g0,b0,a0), rgba(r1,g1,b1,a1), rgba(rb,gb,bb,ab)))
  check("render target 0 received love_Canvases[0] (51,102,153)",
    near(r0,51) and near(g0,102) and near(b0,153) and near(a0,255), rgba(r0,g0,b0,a0))
  check("render target 1 received love_Canvases[1], distinct from target 0 (204,51,51)",
    near(r1,204) and near(g1,51) and near(b1,51) and near(a1,255), rgba(r1,g1,b1,a1))
  check("background outside both targets is the clear colour (76,76,76)",
    near(rb,76) and near(gb,76) and near(bb,76) and near(ab,255), rgba(rb,gb,bb,ab))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-MRT-WITNESS: PASS" or "STEP4-MRT-WITNESS: FAIL"
