-- Step-4 (4.15) readback witness: love.graphics' own texture readback. Every
-- prior witness recovered pixels with the bridge's raw glReadPixels; this one
-- draws into an 8x8 render target and calls the engine's readbackTexture() — the
-- path behind Texture:newImageData / love.graphics.readbackTexture — to pull the
-- GPU texture into a CPU ImageData, then samples it with getPixel(). Recovering
-- the draw colour at the drawn quadrant and the clear colour elsewhere (in
-- top-left ImageData space) proves the engine's readback and orientation
-- handling, not just the test harness's glReadPixels. Chromium only.
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
-- readbackTexture builds its result through the love.image module, so it must be
-- registered (the bridge constructs ImageData via the engine's Image instance).
local iok = pcall(require, "love.image")
check("require 'love.image' (readbackTexture's ImageData factory)",
  iok and type(love.image) == "table", love.image)

local function near(x, e) return x ~= nil and math.abs(x - e) <= 2 end
local function rgba(r, g, b, a) return ("(%s,%s,%s,%s)"):format(tostring(r),tostring(g),tostring(b),tostring(a)) end

local ok, rd,gd,bd,ad, rc,gc,bc,ac = pcall(__wasi_gfx_readback)
check("readbackTexture -> ImageData:getPixel executes", ok, ok and "" or rd)
if ok then
  coroutine.yield(("drawn=%s  cleared=%s"):format(rgba(rd,gd,bd,ad), rgba(rc,gc,bc,ac)))
  check("engine readback recovered the draw colour at the drawn quadrant (51,102,153)",
    near(rd,51) and near(gd,102) and near(bd,153) and near(ad,255), rgba(rd,gd,bd,ad))
  check("engine readback recovered the clear colour elsewhere, orientation correct (76,76,76)",
    near(rc,76) and near(gc,76) and near(bc,76) and near(ac,255), rgba(rc,gc,bc,ac))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-READBACK-WITNESS: PASS" or "STEP4-READBACK-WITNESS: FAIL"
