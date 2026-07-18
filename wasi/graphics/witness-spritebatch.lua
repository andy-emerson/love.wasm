-- Step-4 (4.10) spritebatch witness: SpriteBatch + Quad. Where 4.4 drew one
-- texture and 4.9 drew one mesh, this batches many textured quads into ONE draw
-- and selects sub-regions of a texture. The bridge builds a 2x2 four-texel
-- texture, makes a SpriteBatch on it, and adds two sprites from one batch: a
-- full-texture sprite (top-left, scaled 4x) and a Quad sprite selecting only the
-- texture's top-right texel (lower-right, scaled 4x). Drawing the batch once and
-- reading four pixels proves batched textured-quad drawing (multiple sprites in
-- one draw), per-sprite transforms (they land in different places), and Quad
-- sub-region sampling (the quad sprite is pure top-right colour). Chromium only.
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

local ok, s = pcall(function() return { __wasi_gfx_draw_spritebatch() } end)
check("newSpriteBatch + add(sprite) + add(quad) + draw + readback executes", ok, ok and "" or s)
if ok then
  local expect = {
    { name = "batch sprite 1: top-left texel recovered (51,102,153)",  r=51,  g=102, b=153 },
    { name = "batch sprite 1: bottom-right texel recovered (153,51,204)", r=153, g=51, b=204 },
    { name = "quad sprite: only the top-right texel sampled (204,51,51)", r=204, g=51, b=51 },
    { name = "background outside the batch is the clear colour (76,76,76)", r=76, g=76, b=76 },
  }
  for i, e in ipairs(expect) do
    local o = (i - 1) * 4
    local r, g, b, a = s[o+1], s[o+2], s[o+3], s[o+4]
    check(e.name, near(r, e.r) and near(g, e.g) and near(b, e.b) and near(a, 255), rgba(r, g, b, a))
  end
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-SPRITEBATCH-WITNESS: PASS" or "STEP4-SPRITEBATCH-WITNESS: FAIL"
