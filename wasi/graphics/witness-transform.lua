-- Step-4 (4.12) transform witness: the coordinate-system transform stack, first
-- of the compose-only API tail. The bridge draws three unit rectangles, each in
-- its own push/pop pair under a different transform — translate(8,8) → a quad at
-- (8..12,8..12), scale(4,4) on a 1x1 → (0..4,0..4), translate(16,16)+rotate(pi)
-- on a 4x4 → (12..16,12..16) — over a grey clear, then reads each quad's colour
-- at its predicted place plus an untouched background pixel. The scale quad
-- landing at the ORIGIN (not offset by the first translate) proves pop restored
-- the stack. Chromium only.
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

local ok, r1,g1,b1,a1, r2,g2,b2,a2, r3,g3,b3,a3, r4,g4,b4,a4 = pcall(__wasi_gfx_draw_transform)
check("push/translate/scale/rotate/pop + draw + readback executes", ok, ok and "" or r1)
if ok then
  coroutine.yield(("translate=%s  scale=%s  rotate=%s  bg=%s"):format(
    rgba(r1,g1,b1,a1), rgba(r2,g2,b2,a2), rgba(r3,g3,b3,a3), rgba(r4,g4,b4,a4)))
  check("translate(8,8) moved the quad to its offset cell (51,102,153)",
    near(r1,51) and near(g1,102) and near(b1,153) and near(a1,255), rgba(r1,g1,b1,a1))
  check("scale(4,4) grew a 1x1 to fill the origin cell, and pop restored identity (204,51,51)",
    near(r2,204) and near(g2,51) and near(b2,51) and near(a2,255), rgba(r2,g2,b2,a2))
  check("translate+rotate(pi) landed the quad in the far corner (51,153,51)",
    near(r3,51) and near(g3,153) and near(b3,51) and near(a3,255), rgba(r3,g3,b3,a3))
  check("untouched background stayed the clear colour (76,76,76)",
    near(r4,76) and near(g4,76) and near(b4,76) and near(a4,255), rgba(r4,g4,b4,a4))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-TRANSFORM-WITNESS: PASS" or "STEP4-TRANSFORM-WITNESS: FAIL"
