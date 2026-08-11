-- Step-4 (4.8) render-state witness: the cross-cutting state that composites and
-- clips draws — blend, scissor, stencil. 4.2–4.7 proved WHAT can be drawn; 4.8
-- proves the state that controls HOW it lands. In one frame over a grey clear
-- (51,51,51) the bridge (1) draws a rectangle with ADDITIVE blend so the result
-- is grey + draw = (153,153,153), not a replace; (2) draws a full-buffer blue
-- rectangle with a SCISSOR set to a 6x6 sub-rect, so blue lands only inside it;
-- and (3) writes a 6x6 STENCIL mask then draws a full-buffer red rectangle tested
-- against it, so red lands only where the stencil was written. Five pixels are
-- read back to prove each: the additive sum, blue inside the scissor and the
-- clear colour just outside it (clipped), red inside the stencil and the clear
-- colour just outside it (masked). Chromium only.
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

local function near(x, e) return x ~= nil and math.abs(x - e) <= 3 end
local function rgba(r, g, b, a) return ("(%s,%s,%s,%s)"):format(tostring(r),tostring(g),tostring(b),tostring(a)) end

local ok, s = pcall(function() return { __wasi_gfx_draw_state() } end)
check("setMode(stencil) + blend/scissor/stencil draws + readback executes", ok, ok and "" or s)

if ok then
  local expect = {
    { name = "additive blend: grey + draw summed to (153,153,153)", r=153, g=153, b=153 },
    { name = "scissor: blue lands inside the scissor rect (51,102,153)", r=51, g=102, b=153 },
    { name = "scissor: blue is CLIPPED just outside the rect (grey 51,51,51)", r=51, g=51, b=51 },
    { name = "stencil: red lands inside the stencil mask (204,51,102)", r=204, g=51, b=102 },
    { name = "stencil: red is MASKED just outside the mask (grey 51,51,51)", r=51, g=51, b=51 },
  }
  for i, e in ipairs(expect) do
    local o = (i - 1) * 4
    local r, g, b, a = s[o+1], s[o+2], s[o+3], s[o+4]
    check(e.name, near(r, e.r) and near(g, e.g) and near(b, e.b) and near(a, 255), rgba(r, g, b, a))
  end
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-STATE-WITNESS: PASS" or "STEP4-STATE-WITNESS: FAIL"
