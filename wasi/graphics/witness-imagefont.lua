-- Step-4 (4.20) image-font witness: a non-default font via a genuinely different
-- construction path. 4.7 proved the embedded default font (real FreeType). This
-- builds an ImageFont — glyphs from an image, not FreeType: a small RGBA image
-- with a magenta separator between two solid-white glyph blocks, made into a font
-- via newImageRasterizer + newFont. Printing "AB" in an ink colour renders the
-- glyph blocks in that colour. Counting ink pixels (the glyphs drew) and a clear
-- corner proves the image-glyph font path, distinct from FreeType. (Custom TTF
-- rides 4.7's proven FreeType path, so ImageFont is the one that adds coverage.)
-- Chromium only.
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
-- ImageFont is built through the love.font module (newImageRasterizer).
local fok = pcall(require, "love.font")
check("require 'love.font' (ImageFont rasterizer factory)",
  fok and type(love.font) == "table", love.font)
local iok = pcall(require, "love.image")
check("require 'love.image' (ImageData for the glyph image)",
  iok and type(love.image) == "table", love.image)

local function near(x, e) return x ~= nil and math.abs(x - e) <= 2 end

local ok, ink, cr, cg, cb = pcall(__wasi_gfx_draw_imagefont)
check("newImageRasterizer + newFont + print + readback executes", ok, ok and "" or ink)
if ok then
  coroutine.yield(("ink pixels = %s   corner = (%s,%s,%s)"):format(
    tostring(ink), tostring(cr), tostring(cg), tostring(cb)))
  check("ImageFont glyphs rendered ink in the draw colour (>= 10 px)", type(ink) == "number" and ink >= 10, ink)
  check("a corner away from the text stayed the clear colour (76,76,76)",
    near(cr,76) and near(cg,76) and near(cb,76), ("(%s,%s,%s)"):format(tostring(cr),tostring(cg),tostring(cb)))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-IMAGEFONT-WITNESS: PASS" or "STEP4-IMAGEFONT-WITNESS: FAIL"
