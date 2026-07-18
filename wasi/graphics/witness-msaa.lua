-- Step-4 (4.14) MSAA witness: a multisampled render target. The bridge makes an
-- 8x8 msaa=4 canvas, clears it black, draws a white right-triangle whose y=x
-- hypotenuse bisects pixel centres, unbinds it (resolving the multisample buffer
-- to the texture), and draws it to the backbuffer. The proof is the EDGE pixel:
-- a fully-interior pixel reads white and a fully-exterior pixel reads black, but
-- the pixel the hypotenuse bisects reads an INTERMEDIATE grey — only possible if
-- the edge was coverage-sampled (anti-aliased), i.e. the multisample resolve
-- ran. A plain single-sample canvas would give a hard white/black step with no
-- intermediate. Chromium only.
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

local function near(x, e) return x ~= nil and math.abs(x - e) <= 3 end
local function rgba(r, g, b, a) return ("(%s,%s,%s,%s)"):format(tostring(r),tostring(g),tostring(b),tostring(a)) end

local ok, ri,gi,bi,ai, re,ge,be,ae, ro,go,bo,ao, rb,gb,bb,ab = pcall(__wasi_gfx_draw_msaa)
check("msaa=4 canvas + draw + resolve + readback executes", ok, ok and "" or ri)
if ok then
  coroutine.yield(("interior=%s  edge=%s  exterior=%s  bg=%s"):format(
    rgba(ri,gi,bi,ai), rgba(re,ge,be,ae), rgba(ro,go,bo,ao), rgba(rb,gb,bb,ab)))
  check("triangle interior resolved to solid white (255,255,255)",
    near(ri,255) and near(gi,255) and near(bi,255) and near(ai,255), rgba(ri,gi,bi,ai))
  check("exterior resolved to the black canvas clear (0,0,0)",
    near(ro,0) and near(go,0) and near(bo,0) and near(ao,255), rgba(ro,go,bo,ao))
  -- The whole point: the edge pixel is neither fully white nor fully black.
  check("diagonal edge pixel is an intermediate grey (multisample coverage resolved)",
    re ~= nil and re > 20 and re < 235, rgba(re,ge,be,ae))
  check("background outside the canvas is the clear colour (76,76,76)",
    near(rb,76) and near(gb,76) and near(bb,76) and near(ab,255), rgba(rb,gb,bb,ab))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-MSAA-WITNESS: PASS" or "STEP4-MSAA-WITNESS: FAIL"
