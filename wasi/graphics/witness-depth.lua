-- Step-4 (4.19) depth witness: the depth buffer + depth test (setDepthMode). The
-- bridge clears a depth-capable backbuffer to far, sets depth test LESS + write,
-- then draws a NEAR quad (green) over the left FIRST and a FAR quad (red) over
-- the right SECOND, overlapping. Painter's algorithm (draw order) would paint the
-- overlap red — but depth test REJECTS the later, farther quad where the nearer
-- one already wrote depth, so the overlap stays green. near-only=green,
-- overlap=green (depth beat draw order), far-only=red (far still draws where
-- nothing is in front) proves depth write + depth test. Chromium only.
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
local function green(r,g,b,a) return near(r,51) and near(g,153) and near(b,51) and near(a,255) end
local function red(r,g,b,a)   return near(r,204) and near(g,51) and near(b,51) and near(a,255) end

local ok, rn,gn,bn,an, ro,go,bo,ao, rf,gf,bf,af = pcall(__wasi_gfx_draw_depth)
check("depth-capable backbuffer + setDepthMode + overlapping draws + readback executes", ok, ok and "" or rn)
if ok then
  coroutine.yield(("near-only=%s  overlap=%s  far-only=%s"):format(
    rgba(rn,gn,bn,an), rgba(ro,go,bo,ao), rgba(rf,gf,bf,af)))
  check("near-only region is the near quad (51,153,51)", green(rn,gn,bn,an), rgba(rn,gn,bn,an))
  check("OVERLAP stays near-green — depth test beat draw order (far drawn last but rejected)",
    green(ro,go,bo,ao), rgba(ro,go,bo,ao))
  check("far-only region is the far quad (204,51,51) — far draws where nothing is in front",
    red(rf,gf,bf,af), rgba(rf,gf,bf,af))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-DEPTH-WITNESS: PASS" or "STEP4-DEPTH-WITNESS: FAIL"
