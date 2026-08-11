-- Step-4 (4.3) primitive-set witness: the rest of the 2D primitives through the
-- real LÖVE opengl backend, all in ONE frame. 4.2 drew a single filled
-- rectangle; 4.3 confirms the fill path generalises to a high-vertex fan
-- (circle) and an arbitrary triangle, that the distinct STROKE path (LÖVE builds
-- its own quad/join geometry for outlines and lines) draws, and that points draw
-- with gl_PointSize — every remaining primitive category, each compiled through
-- glslang and streamed through a real VBO. Chromium only.
--
-- The bridge draws all five primitives in five regions of a 16x16 backbuffer,
-- over a distinct clear, in a single setMode+clear+flush (the real per-frame
-- shape — see graphics-ext.cpp on why windowless witnesses must not clear between
-- draws). It reads seven pixels back: one each shape must cover, the hollow
-- centre of the line-mode rectangle (must stay the clear colour, proving outline
-- not fill), and an untouched background pixel (must stay the clear colour).
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

-- Draw colour 0.2,0.4,0.6 -> (51,102,153); clear 0.6,0.4,0.2 -> (153,102,51).
local function near(x, e) return x ~= nil and math.abs(x - e) <= 2 end
local function isdraw(r, g, b, a) return near(r,51) and near(g,102) and near(b,153) and near(a,255) end
local function isclear(r, g, b, a) return near(r,153) and near(g,102) and near(b,51) and near(a,255) end
local function rgba(r, g, b, a) return ("(%s,%s,%s,%s)"):format(tostring(r),tostring(g),tostring(b),tostring(a)) end

local ok, s = pcall(function() return { __wasi_gfx_draw_prims(0.2, 0.4, 0.6, 0.6, 0.4, 0.2) } end)
check("setMode + clear + 5 primitives + flush + readback executes", ok, ok and "" or s)

if ok then
  -- 7 samples * 4 channels, in the bridge's order.
  local samples = {
    { name = "circle fill: covered pixel is the draw colour",              want = "draw"  },
    { name = "points (gl_PointSize): covered pixel is the draw colour",     want = "draw"  },
    { name = "triangle fill: covered pixel is the draw colour",            want = "draw"  },
    { name = "line-mode rectangle: stroke pixel is the draw colour",        want = "draw"  },
    { name = "line-mode rectangle: hollow centre is the clear colour",      want = "clear" },
    { name = "polyline (stroke): covered pixel is the draw colour",         want = "draw"  },
    { name = "background pixel is the clear colour",                        want = "clear" },
  }
  for i, sample in ipairs(samples) do
    local o = (i - 1) * 4
    local r, g, b, a = s[o+1], s[o+2], s[o+3], s[o+4]
    local ok2 = (sample.want == "draw") and isdraw(r,g,b,a) or isclear(r,g,b,a)
    check(sample.name, ok2, rgba(r,g,b,a))
  end
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-PRIMS-WITNESS: PASS" or "STEP4-PRIMS-WITNESS: FAIL"
