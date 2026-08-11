-- Step-4 (4.7) text witness: the first text — the last major drawing surface.
-- Text is FreeType (already linked and witnessed rasterizing/shaping) feeding the
-- textured-draw path 4.4 proved: a glyph is rasterised to a GPU atlas, then drawn
-- as shaped, positioned textured quads. The bridge prints "Aj" with the embedded
-- default font (NotoSans) at the top-left of a 32x16 backbuffer in the ink colour
-- (51,102,153) over a distinct clear. Because glyph shapes are anti-aliased and
-- font-specific, the check is coverage-based, not pixel-exact: real ink coverage
-- must appear in the left half (where the text is), the right half must stay
-- empty, and the background must survive — proving the glyphs rasterised and
-- landed where the text was drawn. Chromium only.
--
-- (Landing text needed one guarded seam: the glyph atlas's native LA8 format uses
-- texture swizzle, which WebGL2 lacks, so the OpenGL.cpp pixel-format seam reports
-- LA8 unsupported and the atlas falls back to RGBA8.)
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
-- love.font registers the font module the default-font rasterizer needs.
check("require 'love.font'", pcall(require, "love.font"), love.font)

local ok, inkLeft, inkRight, Rbg, Gbg, Bbg, Abg = pcall(__wasi_gfx_draw_text)
check("newDefaultFont + print + readback executes", ok, ok and "" or inkLeft)
if ok then
  coroutine.yield(("ink pixels: left=%s right=%s   background=(%s,%s,%s,%s)"):format(
    tostring(inkLeft), tostring(inkRight), tostring(Rbg), tostring(Gbg), tostring(Bbg), tostring(Abg)))
  local function near(x, e) return x ~= nil and math.abs(x - e) <= 2 end
  check("glyphs rasterised: real ink coverage where the text is (left half > 15px)",
    inkLeft ~= nil and inkLeft > 15, tostring(inkLeft))
  check("text is localised: no ink in the empty right half",
    inkRight == 0, tostring(inkRight))
  check("background survives: far corner is the clear colour (76,76,76)",
    near(Rbg,76) and near(Gbg,76) and near(Bbg,76) and near(Abg,255),
    ("(%s,%s,%s,%s)"):format(tostring(Rbg),tostring(Gbg),tostring(Bbg),tostring(Abg)))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-TEXT-WITNESS: PASS" or "STEP4-TEXT-WITNESS: FAIL"
