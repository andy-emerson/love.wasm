-- Step-4 (4.4) texture witness: the first image through the backend. 4.2/4.3
-- drew solid-colour geometry; 4.4 is the first time real pixel data makes the
-- round trip CPU -> GPU texture -> sampled fragment -> readback. The bridge
-- builds a 2x2 RGBA8 image with four distinct texels (image::ImageData ->
-- Texture -> glTexSubImage upload), sets NEAREST filtering, and draws it scaled
-- 4x over a distinct clear so each texel covers a 4x4 block. Reading the centre
-- of each block recovers that texel's colour AND its position, so this proves in
-- one shot: texture upload, sampler binding, the STANDARD_TEXTURE shader, and
-- correct UV mapping including orientation (texel (0,0) must land top-left).
-- Chromium only (a node mock cannot fake a real sampler + shader).
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

local ok, s = pcall(function() return { __wasi_gfx_draw_texture() } end)
check("newTexture + upload + draw + readback executes", ok, ok and "" or s)

if ok then
  -- Expected colours must mirror the texels/clear in graphics-ext.cpp.
  local expect = {
    { name = "texel (0,0) recovered top-left  (51,102,153)",  r=51,  g=102, b=153 },
    { name = "texel (1,0) recovered top-right (204,51,51)",   r=204, g=51,  b=51  },
    { name = "texel (0,1) recovered bottom-left (51,153,51)", r=51,  g=153, b=51  },
    { name = "texel (1,1) recovered bottom-right (153,51,204)", r=153, g=51, b=204 },
    { name = "background pixel is the clear colour (76,76,76)", r=76, g=76, b=76 },
  }
  for i, e in ipairs(expect) do
    local o = (i - 1) * 4
    local r, g, b, a = s[o+1], s[o+2], s[o+3], s[o+4]
    check(e.name, near(r, e.r) and near(g, e.g) and near(b, e.b) and near(a, 255), rgba(r, g, b, a))
  end
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-TEXTURE-WITNESS: PASS" or "STEP4-TEXTURE-WITNESS: FAIL"
