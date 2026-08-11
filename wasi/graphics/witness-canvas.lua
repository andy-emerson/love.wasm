-- Step-4 (4.6) canvas witness: the first render target. Every draw so far went
-- to the backbuffer; 4.6 renders INTO an off-screen texture and then samples it
-- back out. The bridge creates an 8x8 canvas (a render-target Texture), switches
-- rendering into it (an FBO switch), clears it to A (51,102,153) and fills its
-- top-left quadrant with B (204,51,51), switches back to the backbuffer, and
-- draws the canvas onto it over a distinct background clear. Four pixels are read
-- back: B must appear ONLY at the canvas's top-left (proving render-into-texture
-- + sample-out AND that orientation is preserved in both axes — no FBO Y-flip),
-- A elsewhere on the canvas, and the background clear outside it. Chromium only.
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

local ok, s = pcall(function() return { __wasi_gfx_draw_canvas() } end)
check("newCanvas + render-to-canvas + draw canvas + readback executes", ok, ok and "" or s)

if ok then
  local expect = {
    { name = "canvas rect B recovered top-left of canvas (204,51,51)", r=204, g=51,  b=51  },
    { name = "canvas clear A elsewhere: top-right (51,102,153)",       r=51,  g=102, b=153 },
    { name = "canvas clear A elsewhere: bottom-left (51,102,153)",     r=51,  g=102, b=153 },
    { name = "backbuffer background outside canvas (76,76,76)",        r=76,  g=76,  b=76  },
  }
  for i, e in ipairs(expect) do
    local o = (i - 1) * 4
    local r, g, b, a = s[o+1], s[o+2], s[o+3], s[o+4]
    check(e.name, near(r, e.r) and near(g, e.g) and near(b, e.b) and near(a, 255), rgba(r, g, b, a))
  end
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-CANVAS-WITNESS: PASS" or "STEP4-CANVAS-WITNESS: FAIL"
