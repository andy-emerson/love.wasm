-- Step-4 (4.9) mesh witness: the first higher-level drawable — a Mesh, i.e.
-- custom vertex geometry through a USER-owned vertex buffer rather than the
-- engine's batched draw stream. The bridge builds a 3-vertex triangle in LÖVE's
-- default vertex format (position + texcoord + per-vertex colour), uploads it via
-- newMesh to a real VBO, and draws it over a distinct clear. Reading a pixel
-- inside the triangle (the mesh colour 51,102,153) and one outside (the clear
-- colour 153,102,51) proves mesh creation, the custom-format vertex upload, and
-- the mesh draw path. Chromium only.
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

local ok, Rin, Gin, Bin, Ain, Rout, Gout, Bout, Aout = pcall(__wasi_gfx_draw_mesh)
check("newMesh + upload + draw + readback executes", ok, ok and "" or Rin)
if ok then
  coroutine.yield(("mesh interior = %s   background = %s"):format(rgba(Rin,Gin,Bin,Ain), rgba(Rout,Gout,Bout,Aout)))
  check("mesh triangle recovered its vertex colour (51,102,153)",
    near(Rin,51) and near(Gin,102) and near(Bin,153) and near(Ain,255), rgba(Rin,Gin,Bin,Ain))
  check("background outside the mesh is the clear colour (153,102,51)",
    near(Rout,153) and near(Gout,102) and near(Bout,51) and near(Aout,255), rgba(Rout,Gout,Bout,Aout))
end

coroutine.yield(("checks done, %d failures"):format(failures))
return failures == 0 and "STEP4-MESH-WITNESS: PASS" or "STEP4-MESH-WITNESS: FAIL"
