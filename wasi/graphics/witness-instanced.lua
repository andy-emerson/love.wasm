-- Step-4 (4.18) instancing witness: instanced drawing. ONE drawInstanced call
-- renders N copies of a single mesh, each placed by love_InstanceID (WebGL2's
-- native glDrawArraysInstanced, no seam). The bridge draws a 4x4 quad mesh 4x
-- with a vertex shader that offsets instance i into a 2x2 grid cell (spacing 8),
-- so the four instances land in four distinct cells from one call. Reading each
-- cell's colour plus an untouched gap between them proves the instances rendered
-- at their per-instance positions, not stacked at the origin. Chromium only.
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
local function cell(r,g,b,a) return near(r,51) and near(g,102) and near(b,153) and near(a,255) end

local ok, r0,g0,b0,a0, r1,g1,b1,a1, r2,g2,b2,a2, r3,g3,b3,a3, rg,gg,bg,ag = pcall(__wasi_gfx_draw_instanced)
check("newMesh + instance-shader + drawInstanced + readback executes", ok, ok and "" or r0)
if ok then
  coroutine.yield(("cells = %s %s %s %s   gap = %s"):format(
    rgba(r0,g0,b0,a0), rgba(r1,g1,b1,a1), rgba(r2,g2,b2,a2), rgba(r3,g3,b3,a3), rgba(rg,gg,bg,ag)))
  check("instance 0 rendered in its cell (51,102,153)", cell(r0,g0,b0,a0), rgba(r0,g0,b0,a0))
  check("instance 1 rendered in its cell (love_InstanceID offset applied)", cell(r1,g1,b1,a1), rgba(r1,g1,b1,a1))
  check("instance 2 rendered in its cell", cell(r2,g2,b2,a2), rgba(r2,g2,b2,a2))
  check("instance 3 rendered in its cell", cell(r3,g3,b3,a3), rgba(r3,g3,b3,a3))
  check("gap between instances stayed the clear colour (76,76,76) — not stacked",
    near(rg,76) and near(gg,76) and near(bg,76) and near(ag,255), rgba(rg,gg,bg,ag))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-INSTANCED-WITNESS: PASS" or "STEP4-INSTANCED-WITNESS: FAIL"
